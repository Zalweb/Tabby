import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/supabase_config.dart';
import '../data/mock_tabby_repository.dart';
import '../data/supabase_tabby_repository.dart';
import '../domain/models.dart';
import 'tabby_state.dart';

/// Main Tabby Notifier managing bilateral tabs, activity logs, reminders, and mascot state machine
class TabbyNotifier extends StateNotifier<TabbyDashboardState> {
  TabbyNotifier()
      : super(
          // When Supabase is initialized, start with an empty live state.
          // When running unit tests (Supabase not initialized), use mock data.
          SupabaseConfig.isInitialized
              ? const TabbyDashboardState(tabs: [], activities: [], reminders: [])
              : TabbyDashboardState(
                  tabs: MockTabbyRepository.getInitialTabs(),
                  activities: MockTabbyRepository.getInitialActivities(),
                  reminders: MockTabbyRepository.getInitialReminders(),
                ),
        ) {
    _loadTabs();
  }

  Future<void> _loadTabs() async {
    String currentUserId = MockTabbyRepository.currentUser.id;
    if (SupabaseConfig.isInitialized) {
      try {
        currentUserId = SupabaseConfig.currentUserId ?? currentUserId;
      } catch (_) {}
    }

    final tabs = await SupabaseTabbyRepository.instance.fetchTabs(currentUserId);
    if (mounted) {
      state = state.copyWith(tabs: tabs);
    }
  }

  Timer? _emotionTimer;

  Future<void> addExpense({
    required String counterpartId,
    required String counterpartName,
    required String title,
    required int totalAmountCentavos,
    required ExpenseCategory category,
    required bool paidByMe,
    required bool isEqualSplit,
    DateTime? dueDate,
    String? receiptUrl,
  }) async {
    final currentUserId = SupabaseConfig.isInitialized ? (SupabaseConfig.currentUserId ?? MockTabbyRepository.currentUser.id) : MockTabbyRepository.currentUser.id;
    final currentUserDisplayName = SupabaseConfig.isInitialized && SupabaseConfig.currentUser != null ? (SupabaseConfig.currentUser!.userMetadata?['display_name'] ?? MockTabbyRepository.currentUser.displayName) : MockTabbyRepository.currentUser.displayName;

    final now = DateTime.now();

    int myShare;
    int counterpartShare;

    if (isEqualSplit) {
      // 50/50 split with integer centavo division (ADR-001)
      myShare = totalAmountCentavos ~/ 2;
      counterpartShare = totalAmountCentavos - myShare;
    } else {
      // Full obligation allocation
      if (paidByMe) {
        myShare = 0;
        counterpartShare = totalAmountCentavos;
      } else {
        myShare = totalAmountCentavos;
        counterpartShare = 0;
      }
    }

    final newEntry = LedgerEntry(
      id: 'entry-${now.millisecondsSinceEpoch}',
      tabId: counterpartId,
      title: title.trim().isEmpty ? category.displayName : title.trim(),
      category: category,
      totalAmountCentavos: totalAmountCentavos,
      myShareCentavos: myShare,
      counterpartShareCentavos: counterpartShare,
      paidByUserId: paidByMe ? currentUserId : counterpartId,
      paidByName: paidByMe ? currentUserDisplayName : counterpartName,
      date: now,
      dueDate: dueDate,
      status: TransactionStatus.acknowledged,
      receiptUrl: receiptUrl,
    );

    // Find tab or create new tab
    final existingTabIndex = state.tabs.indexWhere(
      (t) => t.id == counterpartId || t.counterpart.id == counterpartId,
    );

    List<BilateralTab> updatedTabs;

    if (existingTabIndex >= 0) {
      final existingTab = state.tabs[existingTabIndex];
      final updatedEntries = [newEntry, ...existingTab.entries];
      final newNetBalance = MockTabbyRepository.calculateNetBalance(
        updatedEntries,
        currentUserId,
      );

      final updatedTab = existingTab.copyWith(
        entries: updatedEntries,
        netBalanceCentavos: newNetBalance,
        itemCount: updatedEntries.length,
        lastUpdated: now,
      );

      updatedTabs = List<BilateralTab>.from(state.tabs);
      updatedTabs[existingTabIndex] = updatedTab;
    } else {
      // Create new bilateral tab
      final newTab = BilateralTab(
        id: counterpartId,
        counterpart: TabbyUser(
          id: counterpartId,
          displayName: counterpartName,
          email: '',
          phone: '',
        ),
        netBalanceCentavos: paidByMe ? counterpartShare : -myShare,
        itemCount: 1,
        entries: [newEntry],
        lastUpdated: now,
      );
      updatedTabs = [newTab, ...state.tabs];
    }

    // Add activity log
    final newActivity = TabbyActivity(
      id: 'act-${now.millisecondsSinceEpoch}',
      actorName: currentUserDisplayName,
      description: 'logged $title with $counterpartName',
      amountCentavos: totalAmountCentavos,
      timestamp: now,
      iconData: category.icon,
    );

    // Add upcoming reminder if due date is specified
    List<UpcomingReminder> updatedReminders = List.from(state.reminders);
    if (dueDate != null) {
      updatedReminders.insert(
        0,
        UpcomingReminder(
          id: 'rem-${now.millisecondsSinceEpoch}',
          tabId: counterpartId,
          friendName: counterpartName,
          description: title,
          amountCentavos: paidByMe ? counterpartShare : myShare,
          dueDate: dueDate,
          isIWhoOwe: !paidByMe,
        ),
      );
    }

    state = state.copyWith(
      tabs: updatedTabs,
      activities: [newActivity, ...state.activities],
      reminders: updatedReminders,
      emotionOverride: MascotEmotion.calculating,
      emotionCustomMessage: 'Tab logged successfully! Calculating balances...',
    );

    // Synchronize with Supabase backend
    if (SupabaseConfig.isInitialized) {
      try {
        // Ensure counterpart exists in public.users (handles typed-name friends with synthetic IDs)
        final resolvedCounterpartId = await SupabaseTabbyRepository.instance
            .ensureUserExists(counterpartId, counterpartName);

        String realTabId = resolvedCounterpartId;
        if (existingTabIndex < 0) {
          realTabId = await SupabaseConfig.getOrCreateBilateralTab(
            userA: currentUserId,
            userB: resolvedCounterpartId,
          );
        }

        await SupabaseTabbyRepository.instance.logExpense(
          tabId: realTabId,
          title: title.trim().isEmpty ? category.displayName : title.trim(),
          totalAmountCentavos: totalAmountCentavos,
          category: category,
          paidByUserId: paidByMe ? currentUserId : resolvedCounterpartId,
          myShareCentavos: myShare,
          counterpartShareCentavos: counterpartShare,
          currentUserId: currentUserId,
          counterpartId: resolvedCounterpartId,
          dueDate: dueDate,
        );

        await _loadTabs();
      } catch (e) {
        debugPrint('[TabbyNotifier] Supabase sync error: $e');
      }
    }

    _scheduleEmotionReset();
  }

  Future<void> settleTab({
    required String tabId,
    required int amountCentavos,
    required PaymentMethod method,
    required bool isPayingMe, // true if counterpart paid user; false if user paid counterpart
    String? note,
  }) async {
    final currentUserId = SupabaseConfig.isInitialized ? (SupabaseConfig.currentUserId ?? MockTabbyRepository.currentUser.id) : MockTabbyRepository.currentUser.id;
    final currentUserDisplayName = SupabaseConfig.isInitialized && SupabaseConfig.currentUser != null ? (SupabaseConfig.currentUser!.userMetadata?['display_name'] ?? MockTabbyRepository.currentUser.displayName) : MockTabbyRepository.currentUser.displayName;

    final now = DateTime.now();

    final tabIndex = state.tabs.indexWhere((t) => t.id == tabId);
    if (tabIndex < 0) return;

    final tab = state.tabs[tabIndex];

    final paymentEntry = LedgerEntry(
      id: 'payment-${now.millisecondsSinceEpoch}',
      tabId: tabId,
      title: isPayingMe
          ? '${tab.counterpart.displayName} paid via ${method.label}'
          : 'You paid ${tab.counterpart.displayName} via ${method.label}',
      category: ExpenseCategory.borrowedCash,
      totalAmountCentavos: amountCentavos,
      myShareCentavos: 0,
      counterpartShareCentavos: 0,
      paidByUserId: isPayingMe ? tab.counterpart.id : currentUserId,
      paidByName: isPayingMe ? tab.counterpart.displayName : currentUserDisplayName,
      date: now,
      status: TransactionStatus.settled,
      isPayment: true,
      paymentMethod: method,
      note: note,
    );

    final updatedEntries = [paymentEntry, ...tab.entries];
    final newNetBalance = MockTabbyRepository.calculateNetBalance(
      updatedEntries,
      currentUserId,
    );

    final updatedTab = tab.copyWith(
      entries: updatedEntries,
      netBalanceCentavos: newNetBalance,
      itemCount: updatedEntries.length,
      lastUpdated: now,
    );

    final updatedTabs = List<BilateralTab>.from(state.tabs);
    updatedTabs[tabIndex] = updatedTab;

    // Filter out resolved reminders for this tab if now settled
    final updatedReminders = state.reminders.where((r) => r.tabId != tabId || newNetBalance.abs() > 0).toList();

    final newActivity = TabbyActivity(
      id: 'act-${now.millisecondsSinceEpoch}',
      actorName: isPayingMe ? tab.counterpart.displayName : currentUserDisplayName,
      description: 'settled ₱${(amountCentavos / 100).toStringAsFixed(2)} via ${method.label}',
      amountCentavos: amountCentavos,
      timestamp: now,
      iconData: method.iconData,
    );

    state = state.copyWith(
      tabs: updatedTabs,
      activities: [newActivity, ...state.activities],
      reminders: updatedReminders,
      emotionOverride: MascotEmotion.celebrating,
      emotionCustomMessage: newNetBalance == 0
          ? 'Nice! That tab is completely settled!'
          : 'Payment recorded! Remaining balance updated.',
    );

    // Synchronize payment with Supabase backend
    if (SupabaseConfig.isInitialized) {
      try {
        await SupabaseTabbyRepository.instance.recordPayment(
          tabId: tabId,
          amountCentavos: amountCentavos,
          method: method,
          paidByUserId: isPayingMe ? tab.counterpart.id : currentUserId,
          receivedByUserId: isPayingMe ? currentUserId : tab.counterpart.id,
          note: note,
        );
        await _loadTabs();
      } catch (e) {
        debugPrint('[TabbyNotifier] Supabase sync error: $e');
      }
    }

    _scheduleEmotionReset(seconds: 4);

  }

  /// Sends a gentle reminder to a friend
  void sendGentleNudge({
    required String tabId,
    required String friendName,
    required int amountCentavos,
  }) {
    final now = DateTime.now();
    final newActivity = TabbyActivity(
      id: 'act-${now.millisecondsSinceEpoch}',
      actorName: MockTabbyRepository.currentUser.displayName,
      description: 'sent friendly reminder to $friendName',
      amountCentavos: amountCentavos,
      timestamp: now,
      iconData: Icons.send_rounded,
    );

    state = state.copyWith(
      activities: [newActivity, ...state.activities],
      emotionOverride: MascotEmotion.gentleNudge,
      emotionCustomMessage: 'Friendly reminder sent to $friendName for our shared tab.',
    );

    _scheduleEmotionReset(seconds: 5);
  }

  void setTemporaryEmotion(MascotEmotion emotion, {String? message, int durationSeconds = 3}) {
    state = state.copyWith(
      emotionOverride: emotion,
      emotionCustomMessage: message,
    );
    _scheduleEmotionReset(seconds: durationSeconds);
  }

  void clearTemporaryEmotion() {
    _emotionTimer?.cancel();
    state = state.copyWith(clearOverride: true);
  }

  void _scheduleEmotionReset({int seconds = 3}) {
    _emotionTimer?.cancel();
    _emotionTimer = Timer(Duration(seconds: seconds), () {
      if (mounted) {
        state = state.copyWith(clearOverride: true);
      }
    });
  }

  /// Adds a new friend and creates an initial bilateral tab
  void addFriend({
    required String name,
    required String phone,
    String email = '',
    String gcashNumber = '',
    String mayaNumber = '',
  }) {
    final now = DateTime.now();
    final friendId = 'user-${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-')}-${now.millisecondsSinceEpoch % 10000}';
    final newFriend = TabbyUser(
      id: friendId,
      displayName: name,
      email: email.isNotEmpty ? email : '${name.toLowerCase().replaceAll(RegExp(r'\s+'), '.')}@example.com',
      phone: phone,
      gcashNumber: gcashNumber,
      mayaNumber: mayaNumber,
    );

    final newTab = BilateralTab(
      id: friendId,
      counterpart: newFriend,
      entries: const [],
      netBalanceCentavos: 0,
      itemCount: 0,
      lastUpdated: now,
    );

    final newActivity = TabbyActivity(
      id: 'act-${now.millisecondsSinceEpoch}',
      actorName: 'You',
      description: 'added $name to your friends list',
      amountCentavos: 0,
      timestamp: now,
      iconData: Icons.person_add_rounded,
    );

    state = state.copyWith(
      tabs: [newTab, ...state.tabs],
      activities: [newActivity, ...state.activities],
    );
  }

  /// Adds a new group tab
  void addGroupTab({
    required String groupName,
    required List<String> memberNames,
  }) {
    final now = DateTime.now();
    final groupId = 'group-${groupName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-')}-${now.millisecondsSinceEpoch % 10000}';
    final groupTab = BilateralTab(
      id: groupId,
      counterpart: TabbyUser(
        id: groupId,
        displayName: groupName,
        email: 'group@tabby.ph',
        phone: memberNames.join(', '),
      ),
      entries: const [],
      netBalanceCentavos: 0,
      itemCount: 0,
      lastUpdated: now,
      isGroupTab: true,
      groupName: groupName,
    );

    final newActivity = TabbyActivity(
      id: 'act-${now.millisecondsSinceEpoch}',
      actorName: 'You',
      description: 'created group $groupName with ${memberNames.length} members',
      amountCentavos: 0,
      timestamp: now,
      iconData: Icons.group_add_rounded,
    );

    state = state.copyWith(
      tabs: [groupTab, ...state.tabs],
      activities: [newActivity, ...state.activities],
    );
  }

  /// Updates details of an existing friend
  void updateFriend({
    required String id,
    required String name,
    required String phone,
    String email = '',
    String gcashNumber = '',
    String mayaNumber = '',
  }) {
    final updatedTabs = state.tabs.map((tab) {
      if (tab.counterpart.id == id || tab.id == id) {
        return tab.copyWith(
          counterpart: tab.counterpart.copyWith(
            displayName: name,
            phone: phone,
            email: email,
            gcashNumber: gcashNumber,
            mayaNumber: mayaNumber,
          ),
        );
      }
      return tab;
    }).toList();

    state = state.copyWith(tabs: updatedTabs);
  }

  /// Removes a friend and their bilateral tab
  void removeFriend(String friendId) {
    final tabToRemove = state.tabs.where((t) => t.counterpart.id == friendId || t.id == friendId).firstOrNull;
    final friendName = tabToRemove?.counterpart.displayName ?? 'Friend';
    final now = DateTime.now();

    final updatedTabs = state.tabs.where((t) => t.counterpart.id != friendId && t.id != friendId).toList();
    final updatedReminders = state.reminders.where((r) => r.tabId != friendId).toList();

    final newActivity = TabbyActivity(
      id: 'act-${now.millisecondsSinceEpoch}',
      actorName: 'You',
      description: 'removed $friendName from your friends list',
      amountCentavos: 0,
      timestamp: now,
      iconData: Icons.person_remove_rounded,
    );

    state = state.copyWith(
      tabs: updatedTabs,
      reminders: updatedReminders,
      activities: [newActivity, ...state.activities],
    );
  }

  /// Removes a group tab and its associated records
  void removeGroupTab(String groupId) {
    final groupToRemove = state.tabs.where((t) => t.id == groupId || t.counterpart.id == groupId).firstOrNull;
    final groupName = groupToRemove?.groupName ?? groupToRemove?.counterpart.displayName ?? 'Group';
    final now = DateTime.now();

    final updatedTabs = state.tabs.where((t) => t.id != groupId && t.counterpart.id != groupId).toList();
    final updatedReminders = state.reminders.where((r) => r.tabId != groupId).toList();

    final newActivity = TabbyActivity(
      id: 'act-${now.millisecondsSinceEpoch}',
      actorName: 'You',
      description: 'deleted group tab "$groupName"',
      amountCentavos: 0,
      timestamp: now,
      iconData: Icons.delete_outline_rounded,
    );

    state = state.copyWith(
      tabs: updatedTabs,
      reminders: updatedReminders,
      activities: [newActivity, ...state.activities],
    );
  }

  /// Attaches a receipt or bill photo URL to a transaction entry
  void attachReceiptToEntry({
    required String tabId,
    required String entryId,
    required String receiptUrl,
  }) {
    final tabIndex = state.tabs.indexWhere((t) => t.id == tabId || t.counterpart.id == tabId);
    if (tabIndex < 0) return;
    final tab = state.tabs[tabIndex];

    final updatedEntries = tab.entries.map((e) {
      if (e.id == entryId) {
        return e.copyWith(receiptUrl: receiptUrl);
      }
      return e;
    }).toList();

    final updatedTab = tab.copyWith(entries: updatedEntries);
    final updatedTabs = List<BilateralTab>.from(state.tabs);
    updatedTabs[tabIndex] = updatedTab;

    state = state.copyWith(tabs: updatedTabs);
  }

  @override
  void dispose() {
    _emotionTimer?.cancel();
    super.dispose();
  }
}

/// Current user profile state notifier
class CurrentUserNotifier extends StateNotifier<TabbyUser> {
  CurrentUserNotifier() : super(MockTabbyRepository.currentUser);

  void updateProfile({
    String? displayName,
    String? email,
    String? phone,
    String? avatarUrl,
    String? gcashNumber,
    String? mayaNumber,
    String? qrCodeUrl,
  }) {
    state = state.copyWith(
      displayName: displayName,
      email: email,
      phone: phone,
      avatarUrl: avatarUrl,
      gcashNumber: gcashNumber,
      mayaNumber: mayaNumber,
      qrCodeUrl: qrCodeUrl,
    );
  }
}

/// Global provider for Current User profile
final currentUserProvider = StateNotifierProvider<CurrentUserNotifier, TabbyUser>((ref) {
  return CurrentUserNotifier();
});

/// Global provider for Tabby Dashboard state & operations
final tabbyProvider = StateNotifierProvider<TabbyNotifier, TabbyDashboardState>((ref) {
  return TabbyNotifier();
});

/// Search query provider for My Tabs screen
final tabSearchQueryProvider = StateProvider<String>((ref) => '');

/// Filtered tabs provider
final filteredTabsProvider = Provider<List<BilateralTab>>((ref) {
  final dashboardState = ref.watch(tabbyProvider);
  final query = ref.watch(tabSearchQueryProvider).trim().toLowerCase();

  if (query.isEmpty) {
    return dashboardState.tabs;
  }

  return dashboardState.tabs.where((tab) {
    final nameMatch = tab.counterpart.displayName.toLowerCase().contains(query);
    final groupMatch = tab.groupName?.toLowerCase().contains(query) ?? false;
    return nameMatch || groupMatch;
  }).toList();
});

/// Individual tab provider by tab ID
final tabDetailProvider = Provider.family<BilateralTab?, String>((ref, tabId) {
  final tabs = ref.watch(tabbyProvider).tabs;
  try {
    return tabs.firstWhere((t) => t.id == tabId || t.counterpart.id == tabId);
  } catch (_) {
    return null;
  }
});

/// Dynamic list of friends derived from active tabs (excluding group tabs)
final friendsProvider = Provider<List<TabbyUser>>((ref) {
  final tabs = ref.watch(tabbyProvider).tabs;
  final seenIds = <String>{};
  final friends = <TabbyUser>[];
  for (final tab in tabs) {
    if (!tab.isGroupTab && !seenIds.contains(tab.counterpart.id)) {
      seenIds.add(tab.counterpart.id);
      friends.add(tab.counterpart);
    }
  }
  return friends;
});

/// Dynamic list of group tabs
final groupsProvider = Provider<List<BilateralTab>>((ref) {
  final tabs = ref.watch(tabbyProvider).tabs;
  return tabs.where((t) => t.isGroupTab).toList();
});

/// Persistent user security & notification preferences
@immutable
class UserSettings {
  final bool biometricsEnabled;
  final bool passcodeEnabled;
  final bool autoLockEnabled;
  final bool notificationsEnabled;
  final bool paymentAlertsEnabled;
  final bool reminderNudgesEnabled;

  const UserSettings({
    this.biometricsEnabled = true,
    this.passcodeEnabled = false,
    this.autoLockEnabled = true,
    this.notificationsEnabled = true,
    this.paymentAlertsEnabled = true,
    this.reminderNudgesEnabled = true,
  });

  UserSettings copyWith({
    bool? biometricsEnabled,
    bool? passcodeEnabled,
    bool? autoLockEnabled,
    bool? notificationsEnabled,
    bool? paymentAlertsEnabled,
    bool? reminderNudgesEnabled,
  }) {
    return UserSettings(
      biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
      passcodeEnabled: passcodeEnabled ?? this.passcodeEnabled,
      autoLockEnabled: autoLockEnabled ?? this.autoLockEnabled,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      paymentAlertsEnabled: paymentAlertsEnabled ?? this.paymentAlertsEnabled,
      reminderNudgesEnabled: reminderNudgesEnabled ?? this.reminderNudgesEnabled,
    );
  }
}

class UserSettingsNotifier extends StateNotifier<UserSettings> {
  UserSettingsNotifier() : super(const UserSettings());

  void update({
    bool? biometricsEnabled,
    bool? passcodeEnabled,
    bool? autoLockEnabled,
    bool? notificationsEnabled,
    bool? paymentAlertsEnabled,
    bool? reminderNudgesEnabled,
  }) {
    state = state.copyWith(
      biometricsEnabled: biometricsEnabled,
      passcodeEnabled: passcodeEnabled,
      autoLockEnabled: autoLockEnabled,
      notificationsEnabled: notificationsEnabled,
      paymentAlertsEnabled: paymentAlertsEnabled,
      reminderNudgesEnabled: reminderNudgesEnabled,
    );
  }
}

final userSettingsProvider = StateNotifierProvider<UserSettingsNotifier, UserSettings>((ref) {
  return UserSettingsNotifier();
});

