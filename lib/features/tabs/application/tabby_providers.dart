import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../../../core/config/supabase_config.dart';
import '../data/mock_tabby_repository.dart';
import '../data/supabase_tabby_repository.dart';
import '../data/tabby_local_cache.dart';
import '../domain/models.dart';
import 'tabby_state.dart';

/// Main Tabby Notifier managing bilateral tabs, activity logs, reminders, and mascot state machine
class TabbyNotifier extends StateNotifier<TabbyDashboardState> {
  TabbyNotifier()
      : super(
          // When Supabase is initialized, start with an empty live state.
          // When running unit tests (Supabase not initialized), use mock data.
          SupabaseConfig.isInitialized
              ? const TabbyDashboardState(
                  tabs: [], activities: [], reminders: [])
              : TabbyDashboardState(
                  tabs: MockTabbyRepository.getInitialTabs(),
                  activities: MockTabbyRepository.getInitialActivities(),
                  reminders: MockTabbyRepository.getInitialReminders(),
                ),
        ) {
    _loadTabs();
  }

  Future<void> _loadTabs() async {
    final hasLiveSession =
        SupabaseConfig.isInitialized && SupabaseConfig.currentUserId != null;
    final currentUserId = hasLiveSession
        ? SupabaseConfig.currentUserId!
        : MockTabbyRepository.currentUser.id;

    if (hasLiveSession) {
      final requests = await SupabaseTabbyRepository.instance
          .fetchFriendRequests(currentUserId);
      if (mounted) {
        state = state.copyWith(friendRequests: requests);
      }
    }

    // 1. Offline resilience: load from local cache first to prevent blank screens
    List<BilateralTab>? cachedTabs;
    try {
      cachedTabs = await TabbyLocalCache.loadTabs(
        userId: hasLiveSession ? currentUserId : null,
      );
      final cachedActivities = await TabbyLocalCache.loadActivities(
        userId: hasLiveSession ? currentUserId : null,
      );
      final cachedReminders = await TabbyLocalCache.loadReminders(
        userId: hasLiveSession ? currentUserId : null,
      );
      if (mounted &&
          (cachedTabs != null ||
              cachedActivities != null ||
              cachedReminders != null)) {
        state = state.copyWith(
          tabs: cachedTabs ?? state.tabs,
          activities: cachedActivities ?? state.activities,
          reminders: cachedReminders ?? state.reminders,
        );
      }
    } catch (e) {
      debugPrint('[TabbyNotifier] Local cache load warning: $e');
    }

    // 2. Fetch live data from Supabase backend
    try {
      final serverTabs =
          await SupabaseTabbyRepository.instance.fetchTabs(currentUserId);
      if (mounted) {
        // Collect all candidate local tabs from in-memory state and local cache
        final localTabsPool = <String, BilateralTab>{};
        if (cachedTabs != null) {
          for (final t in cachedTabs) {
            localTabsPool[t.id] = t;
          }
        }
        for (final t in state.tabs) {
          localTabsPool[t.id] = t;
        }

        final mergedTabs = <BilateralTab>[];
        final processedLocalIds = <String>{};

        for (final st in serverTabs) {
          // Find matching local tab by tab id or counterpart id/name
          final localMatch =
              localTabsPool.values.cast<BilateralTab?>().firstWhere(
                    (lt) =>
                        lt != null &&
                        (lt.id == st.id ||
                            (!lt.isGroupTab &&
                                !st.isGroupTab &&
                                ((lt.counterpart.id.isNotEmpty &&
                                        lt.counterpart.id ==
                                            st.counterpart.id) ||
                                    lt.counterpart.displayName
                                            .trim()
                                            .toLowerCase() ==
                                        st.counterpart.displayName
                                            .trim()
                                            .toLowerCase()))),
                    orElse: () => null,
                  );

          if (localMatch != null) {
            processedLocalIds.add(localMatch.id);
            // Merge entries: combine server entries and any local entries that haven't synced yet
            final serverEntryIds = st.entries.map((e) => e.id).toSet();
            final combinedEntries = <LedgerEntry>[...st.entries];
            for (final le in localMatch.entries) {
              if (!serverEntryIds.contains(le.id)) {
                combinedEntries.add(le);
              }
            }
            combinedEntries.sort((a, b) => b.date.compareTo(a.date));

            final effectiveBalance = MockTabbyRepository.calculateNetBalance(
              combinedEntries,
              currentUserId,
            );

            mergedTabs.add(st.copyWith(
              entries: combinedEntries,
              itemCount: combinedEntries.length,
              netBalanceCentavos: effectiveBalance,
            ));
          } else {
            mergedTabs.add(st);
          }
        }

        // Add remaining local tabs that were not on server
        for (final entry in localTabsPool.entries) {
          if (!processedLocalIds.contains(entry.key)) {
            final alreadyInMerged = mergedTabs.any((m) =>
                m.id == entry.value.id ||
                (!m.isGroupTab &&
                    !entry.value.isGroupTab &&
                    ((m.counterpart.id.isNotEmpty &&
                            m.counterpart.id == entry.value.counterpart.id) ||
                        m.counterpart.displayName.trim().toLowerCase() ==
                            entry.value.counterpart.displayName
                                .trim()
                                .toLowerCase())));
            if (!alreadyInMerged) {
              mergedTabs.add(entry.value);
            }
          }
        }

        state = state.copyWith(tabs: mergedTabs);
        await TabbyLocalCache.saveTabs(
          mergedTabs,
          userId: hasLiveSession ? currentUserId : null,
        );
      }
    } catch (e) {
      debugPrint('[TabbyNotifier] Live fetch error: $e');
    }
  }

  Future<void> refreshTabs() async {
    await _loadTabs();
  }

  Future<TabbyUser?> findFriendByCode(String friendCode) {
    return SupabaseTabbyRepository.instance.findUserByFriendCode(friendCode);
  }

  Future<FriendRequest?> sendFriendRequestByCode(String friendCode) async {
    final request = await SupabaseTabbyRepository.instance
        .sendFriendRequest(friendCode: friendCode);
    if (request != null && mounted) {
      state = state.copyWith(
        friendRequests: [
          request,
          ...state.friendRequests.where((existing) => existing.id != request.id),
        ],
      );
    }
    return request;
  }

  Future<bool> respondToFriendRequest({
    required String friendshipId,
    required bool accept,
  }) async {
    final tabId = await SupabaseTabbyRepository.instance.respondToFriendRequest(
      friendshipId: friendshipId,
      accept: accept,
    );
    if (!mounted || !SupabaseTabbyRepository.instance.isConnected || tabId == null) {
      return false;
    }

    state = state.copyWith(
      friendRequests: state.friendRequests
          .where((request) => request.id != friendshipId)
          .toList(),
    );
    if (accept && tabId.isNotEmpty) {
      await _loadTabs();
    }
    return true;
  }

  void reset() {
    state = SupabaseConfig.isInitialized
        ? const TabbyDashboardState(tabs: [], activities: [], reminders: [])
        : TabbyDashboardState(
            tabs: MockTabbyRepository.getInitialTabs(),
            activities: MockTabbyRepository.getInitialActivities(),
            reminders: MockTabbyRepository.getInitialReminders(),
          );
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
    bool isConnectedFriend = false,
    DateTime? dueDate,
    String? receiptUrl,
  }) async {
    final currentUserId = SupabaseConfig.isInitialized
        ? (SupabaseConfig.currentUserId ?? MockTabbyRepository.currentUser.id)
        : MockTabbyRepository.currentUser.id;
    final currentUserDisplayName =
        SupabaseConfig.isInitialized && SupabaseConfig.currentUser != null
            ? (SupabaseConfig.currentUser!.userMetadata?['display_name'] ??
                MockTabbyRepository.currentUser.displayName)
            : MockTabbyRepository.currentUser.displayName;

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

    final cacheUserId =
        SupabaseConfig.isInitialized ? SupabaseConfig.currentUserId : null;
    await TabbyLocalCache.saveTabs(updatedTabs, userId: cacheUserId);
    await TabbyLocalCache.saveActivities([newActivity, ...state.activities],
        userId: cacheUserId);
    await TabbyLocalCache.saveReminders(updatedReminders, userId: cacheUserId);

    // Synchronize with Supabase backend
    if (SupabaseConfig.isInitialized) {
      try {
        final isGroupTab =
            existingTabIndex >= 0 && state.tabs[existingTabIndex].isGroupTab;

        // Ensure counterpart exists in public.users (handles typed-name friends with synthetic IDs)
        final resolvedCounterpartId = isGroupTab
            ? counterpartId
            : await SupabaseTabbyRepository.instance
                .ensureUserExists(counterpartId, counterpartName);

        String? realTabId;
        if (existingTabIndex >= 0 &&
            SupabaseTabbyRepository.isValidUuid(
                state.tabs[existingTabIndex].id)) {
          realTabId = state.tabs[existingTabIndex].id;
        } else if (!isGroupTab &&
            SupabaseTabbyRepository.isValidUuid(currentUserId) &&
            SupabaseTabbyRepository.isValidUuid(resolvedCounterpartId) &&
            currentUserId != resolvedCounterpartId) {
          realTabId = await SupabaseConfig.getOrCreateBilateralTab(
            userA: currentUserId,
            userB: resolvedCounterpartId,
          );
        }

        // Connected accounts must stay on the bilateral-tab path. Do not
        // silently create a private contact tab if that path is unavailable.
        if (realTabId == null &&
            !isGroupTab &&
            !isConnectedFriend &&
            SupabaseTabbyRepository.isValidUuid(currentUserId)) {
          final contactResult =
              await SupabaseTabbyRepository.instance.getOrCreateContactTab(
            ownerId: currentUserId,
            contactName: counterpartName,
          );
          if (contactResult != null && contactResult['tab_id'] != null) {
            realTabId = contactResult['tab_id'];
          }
        }

        if (realTabId != null) {
          // Update local tab id if it was synthetic
          final currentIdx = state.tabs.indexWhere(
            (t) =>
                t.id == counterpartId ||
                t.counterpart.id == counterpartId ||
                t.id == realTabId,
          );
          if (currentIdx >= 0 && state.tabs[currentIdx].id != realTabId) {
            final fixedTabs = List<BilateralTab>.from(state.tabs);
            fixedTabs[currentIdx] =
                fixedTabs[currentIdx].copyWith(id: realTabId);
            state = state.copyWith(tabs: fixedTabs);
            await TabbyLocalCache.saveTabs(
              fixedTabs,
              userId: cacheUserId,
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
            receiptUrl: receiptUrl,
          );

          await _loadTabs();
        }
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
    required bool
        isPayingMe, // true if counterpart paid user; false if user paid counterpart
    String? note,
  }) async {
    final currentUserId = SupabaseConfig.isInitialized
        ? (SupabaseConfig.currentUserId ?? MockTabbyRepository.currentUser.id)
        : MockTabbyRepository.currentUser.id;
    final currentUserDisplayName =
        SupabaseConfig.isInitialized && SupabaseConfig.currentUser != null
            ? (SupabaseConfig.currentUser!.userMetadata?['display_name'] ??
                MockTabbyRepository.currentUser.displayName)
            : MockTabbyRepository.currentUser.displayName;

    final now = DateTime.now();

    final tabIndex = state.tabs
        .indexWhere((t) => t.id == tabId || t.counterpart.id == tabId);
    if (tabIndex < 0) return;

    final tab = state.tabs[tabIndex];

    final paymentEntry = LedgerEntry(
      id: 'payment-${now.millisecondsSinceEpoch}',
      tabId: tab.id,
      title: isPayingMe
          ? '${tab.counterpart.displayName} paid via ${method.label}'
          : 'You paid ${tab.counterpart.displayName} via ${method.label}',
      category: ExpenseCategory.borrowedCash,
      totalAmountCentavos: amountCentavos,
      myShareCentavos: 0,
      counterpartShareCentavos: 0,
      paidByUserId: isPayingMe ? tab.counterpart.id : currentUserId,
      paidByName:
          isPayingMe ? tab.counterpart.displayName : currentUserDisplayName,
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
    final updatedReminders = state.reminders
        .where((r) =>
            (r.tabId != tab.id && r.tabId != tab.counterpart.id) ||
            newNetBalance.abs() > 0)
        .toList();

    final newActivity = TabbyActivity(
      id: 'act-${now.millisecondsSinceEpoch}',
      actorName:
          isPayingMe ? tab.counterpart.displayName : currentUserDisplayName,
      description:
          'settled ₱${(amountCentavos / 100).toStringAsFixed(2)} via ${method.label}',
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

    final cacheUserId =
        SupabaseConfig.isInitialized ? SupabaseConfig.currentUserId : null;
    await TabbyLocalCache.saveTabs(updatedTabs, userId: cacheUserId);
    await TabbyLocalCache.saveActivities([newActivity, ...state.activities],
        userId: cacheUserId);
    await TabbyLocalCache.saveReminders(updatedReminders, userId: cacheUserId);

    // Synchronize payment with Supabase backend
    if (SupabaseConfig.isInitialized) {
      try {
        String? realTabId;
        if (SupabaseTabbyRepository.isValidUuid(tab.id)) {
          realTabId = tab.id;
        } else if (SupabaseTabbyRepository.isValidUuid(currentUserId) &&
            SupabaseTabbyRepository.isValidUuid(tab.counterpart.id) &&
            currentUserId != tab.counterpart.id) {
          realTabId = await SupabaseConfig.getOrCreateBilateralTab(
            userA: currentUserId,
            userB: tab.counterpart.id,
          );
        } else if (SupabaseTabbyRepository.isValidUuid(currentUserId)) {
          final contactResult =
              await SupabaseTabbyRepository.instance.getOrCreateContactTab(
            ownerId: currentUserId,
            contactName: tab.counterpart.displayName,
          );
          if (contactResult != null) {
            realTabId = contactResult['tab_id'];
          }
        }

        if (realTabId != null) {
          final effectivePaidBy =
              SupabaseTabbyRepository.isValidUuid(tab.counterpart.id)
                  ? (isPayingMe ? tab.counterpart.id : currentUserId)
                  : currentUserId;
          final effectiveReceivedBy =
              SupabaseTabbyRepository.isValidUuid(tab.counterpart.id)
                  ? (isPayingMe ? currentUserId : tab.counterpart.id)
                  : currentUserId;

          await SupabaseTabbyRepository.instance.recordPayment(
            tabId: realTabId,
            amountCentavos: amountCentavos,
            method: method,
            paidByUserId: effectivePaidBy,
            receivedByUserId: effectiveReceivedBy,
            note: note,
            confirmedByUserId: currentUserId,
          );
          await _loadTabs();
        }
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
      emotionCustomMessage:
          'Friendly reminder sent to $friendName for our shared tab.',
    );

    _scheduleEmotionReset(seconds: 5);
  }

  void setTemporaryEmotion(MascotEmotion emotion,
      {String? message, int durationSeconds = 3}) {
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
  Future<void> addFriend({
    required String name,
    required String phone,
    String email = '',
    String gcashNumber = '',
    String mayaNumber = '',
  }) async {
    final hasLiveSession =
        SupabaseConfig.isInitialized && SupabaseConfig.currentUserId != null;
    final currentUserId = hasLiveSession
        ? SupabaseConfig.currentUserId!
        : MockTabbyRepository.currentUser.id;

    final now = DateTime.now();
    String tabId =
        'user-${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-')}-${now.millisecondsSinceEpoch % 10000}';
    String counterpartId = tabId;

    if (hasLiveSession && SupabaseTabbyRepository.isValidUuid(currentUserId)) {
      try {
        final contactRes =
            await SupabaseTabbyRepository.instance.getOrCreateContactTab(
          ownerId: currentUserId,
          contactName: name,
        );
        if (contactRes != null) {
          if (contactRes['tab_id'] != null &&
              contactRes['tab_id']!.isNotEmpty) {
            tabId = contactRes['tab_id']!;
          }
          if (contactRes['contact_id'] != null &&
              contactRes['contact_id']!.isNotEmpty) {
            counterpartId = contactRes['contact_id']!;
          }
        }
      } catch (e) {
        debugPrint('[TabbyNotifier] addFriend Supabase sync error: $e');
      }
    }

    final newFriend = TabbyUser(
      id: counterpartId,
      displayName: name,
      email: email.isNotEmpty
          ? email
          : '${name.toLowerCase().replaceAll(RegExp(r'\s+'), '.')}@example.com',
      phone: phone,
      gcashNumber: gcashNumber,
      mayaNumber: mayaNumber,
    );

    final newTab = BilateralTab(
      id: tabId,
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

    final updatedTabs = [newTab, ...state.tabs];
    final updatedActivities = [newActivity, ...state.activities];

    state = state.copyWith(
      tabs: updatedTabs,
      activities: updatedActivities,
    );

    await TabbyLocalCache.saveTabs(
      updatedTabs,
      userId: hasLiveSession ? currentUserId : null,
    );
    await TabbyLocalCache.saveActivities(
      updatedActivities,
      userId: hasLiveSession ? currentUserId : null,
    );
  }

  /// Adds a new group tab
  void addGroupTab({
    required String groupName,
    required List<String> memberNames,
    List<String>? memberUserIds,
  }) {
    final hasLiveSession =
        SupabaseConfig.isInitialized && SupabaseConfig.currentUserId != null;
    final currentUserId = hasLiveSession
        ? SupabaseConfig.currentUserId!
        : MockTabbyRepository.currentUser.id;

    final now = DateTime.now();
    final groupId =
        'group-${groupName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-')}-${now.millisecondsSinceEpoch % 10000}';
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
      description:
          'created group $groupName with ${memberNames.length} members',
      amountCentavos: 0,
      timestamp: now,
      iconData: Icons.group_add_rounded,
    );

    final updatedTabs = [groupTab, ...state.tabs];
    final updatedActivities = [newActivity, ...state.activities];

    state = state.copyWith(
      tabs: updatedTabs,
      activities: updatedActivities,
    );

    TabbyLocalCache.saveTabs(
      updatedTabs,
      userId: hasLiveSession ? currentUserId : null,
    );
    TabbyLocalCache.saveActivities(
      updatedActivities,
      userId: hasLiveSession ? currentUserId : null,
    );

    if (SupabaseConfig.isInitialized && SupabaseConfig.currentUserId != null) {
      SupabaseTabbyRepository.instance
          .createGroupTab(
        groupName: groupName,
        currentUserId: SupabaseConfig.currentUserId!,
        memberUserIds: memberUserIds,
      )
          .then((newTabId) {
        if (newTabId != null) {
          _loadTabs();
        }
      }).catchError((e) {
        debugPrint('[TabbyNotifier] createGroupTab warning: $e');
        return null;
      });
    }
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
    final hasLiveSession =
        SupabaseConfig.isInitialized && SupabaseConfig.currentUserId != null;
    final currentUserId = hasLiveSession
        ? SupabaseConfig.currentUserId!
        : MockTabbyRepository.currentUser.id;

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
    TabbyLocalCache.saveTabs(
      updatedTabs,
      userId: hasLiveSession ? currentUserId : null,
    );
  }

  /// Removes a friend and their bilateral tab
  void removeFriend(String friendId) {
    final hasLiveSession =
        SupabaseConfig.isInitialized && SupabaseConfig.currentUserId != null;
    final currentUserId = hasLiveSession
        ? SupabaseConfig.currentUserId!
        : MockTabbyRepository.currentUser.id;

    final tabToRemove = state.tabs
        .where((t) => t.counterpart.id == friendId || t.id == friendId)
        .firstOrNull;
    final friendName = tabToRemove?.counterpart.displayName ?? 'Friend';
    final now = DateTime.now();

    final updatedTabs = state.tabs
        .where((t) => t.counterpart.id != friendId && t.id != friendId)
        .toList();
    final updatedReminders =
        state.reminders.where((r) => r.tabId != friendId).toList();

    final newActivity = TabbyActivity(
      id: 'act-${now.millisecondsSinceEpoch}',
      actorName: 'You',
      description: 'removed $friendName from your friends list',
      amountCentavos: 0,
      timestamp: now,
      iconData: Icons.person_remove_rounded,
    );

    final updatedActivities = [newActivity, ...state.activities];

    state = state.copyWith(
      tabs: updatedTabs,
      activities: updatedActivities,
      reminders: updatedReminders,
    );

    TabbyLocalCache.saveTabs(
      updatedTabs,
      userId: hasLiveSession ? currentUserId : null,
    );
    TabbyLocalCache.saveActivities(
      updatedActivities,
      userId: hasLiveSession ? currentUserId : null,
    );
    TabbyLocalCache.saveReminders(
      updatedReminders,
      userId: hasLiveSession ? currentUserId : null,
    );

    if (SupabaseConfig.isInitialized &&
        tabToRemove != null &&
        SupabaseTabbyRepository.isValidUuid(tabToRemove.id)) {
      SupabaseTabbyRepository.instance.archiveTab(tabToRemove.id);
    }
  }

  /// Removes a group tab and its associated records
  void removeGroupTab(String groupId) {
    final hasLiveSession =
        SupabaseConfig.isInitialized && SupabaseConfig.currentUserId != null;
    final currentUserId = hasLiveSession
        ? SupabaseConfig.currentUserId!
        : MockTabbyRepository.currentUser.id;

    final groupToRemove = state.tabs
        .where((t) => t.id == groupId || t.counterpart.id == groupId)
        .firstOrNull;
    final groupName = groupToRemove?.groupName ??
        groupToRemove?.counterpart.displayName ??
        'Group';
    final now = DateTime.now();

    final updatedTabs = state.tabs
        .where((t) => t.id != groupId && t.counterpart.id != groupId)
        .toList();
    final updatedReminders =
        state.reminders.where((r) => r.tabId != groupId).toList();

    final newActivity = TabbyActivity(
      id: 'act-${now.millisecondsSinceEpoch}',
      actorName: 'You',
      description: 'deleted group tab "$groupName"',
      amountCentavos: 0,
      timestamp: now,
      iconData: Icons.delete_outline_rounded,
    );

    final updatedActivities = [newActivity, ...state.activities];

    state = state.copyWith(
      tabs: updatedTabs,
      reminders: updatedReminders,
      activities: updatedActivities,
    );

    TabbyLocalCache.saveTabs(
      updatedTabs,
      userId: hasLiveSession ? currentUserId : null,
    );
    TabbyLocalCache.saveActivities(
      updatedActivities,
      userId: hasLiveSession ? currentUserId : null,
    );
    TabbyLocalCache.saveReminders(
      updatedReminders,
      userId: hasLiveSession ? currentUserId : null,
    );

    if (SupabaseConfig.isInitialized &&
        groupToRemove != null &&
        SupabaseTabbyRepository.isValidUuid(groupToRemove.id)) {
      SupabaseTabbyRepository.instance.archiveTab(groupToRemove.id);
    }
  }

  /// Attaches a receipt or bill photo URL to a transaction entry
  void attachReceiptToEntry({
    required String tabId,
    required String entryId,
    required String receiptUrl,
  }) {
    final hasLiveSession =
        SupabaseConfig.isInitialized && SupabaseConfig.currentUserId != null;
    final currentUserId = hasLiveSession
        ? SupabaseConfig.currentUserId!
        : MockTabbyRepository.currentUser.id;

    final tabIndex = state.tabs
        .indexWhere((t) => t.id == tabId || t.counterpart.id == tabId);
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
    TabbyLocalCache.saveTabs(
      updatedTabs,
      userId: hasLiveSession ? currentUserId : null,
    );

    if (SupabaseConfig.isInitialized &&
        SupabaseTabbyRepository.isValidUuid(entryId)) {
      SupabaseTabbyRepository.instance.attachReceipt(entryId, receiptUrl);
    }
  }

  @override
  void dispose() {
    _emotionTimer?.cancel();
    super.dispose();
  }
}

/// Current user profile state notifier
class CurrentUserNotifier extends StateNotifier<TabbyUser> {
  CurrentUserNotifier() : super(_resolveInitialUser()) {
    loadFromSupabase();
  }

  static TabbyUser _resolveInitialUser() {
    if (SupabaseConfig.isInitialized && SupabaseConfig.currentUser != null) {
      final user = SupabaseConfig.currentUser!;
      final meta = user.userMetadata ?? {};
      return TabbyUser(
        id: user.id,
        displayName: meta['display_name'] as String? ??
            (user.email?.split('@').first ?? 'User'),
        email: user.email ?? '',
        phone: (meta['phone'] ?? user.phone) as String? ?? '',
        avatarUrl: meta['avatar_url'] as String?,
        friendCode: meta['friend_code'] as String?,
      );
    }
    return MockTabbyRepository.currentUser;
  }

  Future<void> loadFromSupabase() async {
    if (!SupabaseConfig.isInitialized) return;
    final authUser = SupabaseConfig.currentUser;
    if (authUser == null) return;

    final profile =
        await SupabaseTabbyRepository.instance.fetchUserProfile(authUser.id);
    if (profile != null) {
      final metadata = authUser.userMetadata ?? {};
      final metadataName =
          (metadata['display_name'] ?? metadata['name']) as String?;
      final metadataPhone = (metadata['phone'] ?? authUser.phone) as String?;
      final displayName = profile.displayName.trim().isEmpty
          ? (metadataName?.trim().isNotEmpty == true
              ? metadataName!.trim()
              : profile.displayName)
          : profile.displayName;
      final phone = profile.phone.trim().isEmpty
          ? (metadataPhone?.trim().isNotEmpty == true
              ? metadataPhone!.trim()
              : profile.phone)
          : profile.phone;

      if (displayName != profile.displayName || phone != profile.phone) {
        await SupabaseTabbyRepository.instance.updateUserProfile(
          userId: authUser.id,
          displayName: displayName,
          phone: phone,
        );
        state = profile.copyWith(
          displayName: displayName,
          phone: phone,
        );
      } else {
        state = profile;
      }
    } else {
      final meta = authUser.userMetadata ?? {};
      final displayName = meta['display_name'] as String? ??
          (authUser.email?.split('@').first ?? 'User');
      final phone = (meta['phone'] ?? authUser.phone) as String? ?? '';

      await SupabaseTabbyRepository.instance
          .ensureUserExists(authUser.id, displayName);

      state = TabbyUser(
        id: authUser.id,
        displayName: displayName,
        email: authUser.email ?? '',
        phone: phone,
        avatarUrl: meta['avatar_url'] as String?,
        friendCode: meta['friend_code'] as String?,
      );
    }
  }

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

    if (SupabaseConfig.isInitialized && SupabaseConfig.currentUserId != null) {
      SupabaseTabbyRepository.instance.updateUserProfile(
        userId: state.id,
        displayName: displayName,
        phone: phone,
        avatarUrl: avatarUrl,
        gcashNumber: gcashNumber,
        mayaNumber: mayaNumber,
        qrCodeUrl: qrCodeUrl,
      );
    }
  }

  /// Saves the required details collected after Google OAuth.
  ///
  /// This path waits for the Supabase write so the router never unlocks an
  /// account before its profile details are actually persisted.
  Future<bool> completeProfile({
    required String displayName,
    required String phone,
  }) async {
    if (!SupabaseConfig.isInitialized || SupabaseConfig.currentUserId == null) {
      return false;
    }

    final saved = await SupabaseTabbyRepository.instance.updateUserProfile(
      userId: state.id,
      displayName: displayName,
      phone: phone,
    );
    if (!saved) return false;

    state = state.copyWith(
      displayName: displayName,
      phone: phone,
    );
    return true;
  }

  void reset() {
    state = MockTabbyRepository.currentUser;
  }
}

/// Global provider for Current User profile
final currentUserProvider =
    StateNotifierProvider<CurrentUserNotifier, TabbyUser>((ref) {
  return CurrentUserNotifier();
});

/// Global provider for Tabby Dashboard state & operations
final tabbyProvider =
    StateNotifierProvider<TabbyNotifier, TabbyDashboardState>((ref) {
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
      reminderNudgesEnabled:
          reminderNudgesEnabled ?? this.reminderNudgesEnabled,
    );
  }
}

class UserSettingsNotifier extends StateNotifier<UserSettings> {
  static const _storage = FlutterSecureStorage();
  static final _auth = LocalAuthentication();

  UserSettingsNotifier() : super(const UserSettings()) {
    _loadPersistedSettings();
  }

  Future<void> _loadPersistedSettings() async {
    try {
      final bioStr = await _storage.read(key: 'tabby_biometrics_enabled');
      final passStr = await _storage.read(key: 'tabby_passcode_enabled');
      final lockStr = await _storage.read(key: 'tabby_auto_lock_enabled');
      final notifStr = await _storage.read(key: 'tabby_notifications_enabled');
      final payStr = await _storage.read(key: 'tabby_payment_alerts_enabled');
      final remStr = await _storage.read(key: 'tabby_reminder_nudges_enabled');

      state = UserSettings(
        biometricsEnabled: bioStr != null ? bioStr == 'true' : true,
        passcodeEnabled: passStr != null ? passStr == 'true' : false,
        autoLockEnabled: lockStr != null ? lockStr == 'true' : true,
        notificationsEnabled: notifStr != null ? notifStr == 'true' : true,
        paymentAlertsEnabled: payStr != null ? payStr == 'true' : true,
        reminderNudgesEnabled: remStr != null ? remStr == 'true' : true,
      );
    } catch (e) {
      debugPrint('[UserSettingsNotifier] Error loading settings: $e');
    }
  }

  Future<bool> toggleBiometrics(bool enable) async {
    if (enable) {
      try {
        final canCheck = await _auth.canCheckBiometrics;
        final isSupported = await _auth.isDeviceSupported();
        if (!canCheck && !isSupported) {
          debugPrint(
              '[UserSettingsNotifier] Biometrics not supported on device');
          return false;
        }

        final didAuthenticate = await _auth.authenticate(
          localizedReason: 'Confirm biometric identity to secure Tabby',
          options: const AuthenticationOptions(
              stickyAuth: true, biometricOnly: true),
        );

        if (!didAuthenticate) {
          return false;
        }
      } catch (e) {
        debugPrint('[UserSettingsNotifier] Biometric check failed: $e');
        return false;
      }
    }

    state = state.copyWith(biometricsEnabled: enable);
    try {
      await _storage.write(
          key: 'tabby_biometrics_enabled', value: enable.toString());
    } catch (e) {
      debugPrint('[UserSettingsNotifier] Error saving biometrics: $e');
    }
    return true;
  }

  Future<void> toggleNotifications(bool enable) async {
    state = state.copyWith(notificationsEnabled: enable);
    try {
      await _storage.write(
          key: 'tabby_notifications_enabled', value: enable.toString());
    } catch (e) {
      debugPrint('[UserSettingsNotifier] Error saving notifications: $e');
    }
  }

  Future<void> update({
    bool? biometricsEnabled,
    bool? passcodeEnabled,
    bool? autoLockEnabled,
    bool? notificationsEnabled,
    bool? paymentAlertsEnabled,
    bool? reminderNudgesEnabled,
  }) async {
    state = state.copyWith(
      biometricsEnabled: biometricsEnabled,
      passcodeEnabled: passcodeEnabled,
      autoLockEnabled: autoLockEnabled,
      notificationsEnabled: notificationsEnabled,
      paymentAlertsEnabled: paymentAlertsEnabled,
      reminderNudgesEnabled: reminderNudgesEnabled,
    );

    try {
      if (biometricsEnabled != null) {
        await _storage.write(
            key: 'tabby_biometrics_enabled',
            value: biometricsEnabled.toString());
      }
      if (passcodeEnabled != null) {
        await _storage.write(
            key: 'tabby_passcode_enabled', value: passcodeEnabled.toString());
      }
      if (autoLockEnabled != null) {
        await _storage.write(
            key: 'tabby_auto_lock_enabled', value: autoLockEnabled.toString());
      }
      if (notificationsEnabled != null) {
        await _storage.write(
            key: 'tabby_notifications_enabled',
            value: notificationsEnabled.toString());
      }
      if (paymentAlertsEnabled != null) {
        await _storage.write(
            key: 'tabby_payment_alerts_enabled',
            value: paymentAlertsEnabled.toString());
      }
      if (reminderNudgesEnabled != null) {
        await _storage.write(
            key: 'tabby_reminder_nudges_enabled',
            value: reminderNudgesEnabled.toString());
      }
    } catch (e) {
      debugPrint('[UserSettingsNotifier] Error saving settings: $e');
    }
  }
}

final userSettingsProvider =
    StateNotifierProvider<UserSettingsNotifier, UserSettings>((ref) {
  return UserSettingsNotifier();
});
