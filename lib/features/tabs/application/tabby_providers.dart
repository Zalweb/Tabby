import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/mock_tabby_repository.dart';
import '../domain/models.dart';
import 'tabby_state.dart';

/// Main Tabby Notifier managing bilateral tabs, activity logs, reminders, and mascot state machine
class TabbyNotifier extends StateNotifier<TabbyDashboardState> {
  TabbyNotifier()
      : super(
          TabbyDashboardState(
            tabs: MockTabbyRepository.getInitialTabs(),
            activities: MockTabbyRepository.getInitialActivities(),
            reminders: MockTabbyRepository.getInitialReminders(),
          ),
        );

  Timer? _emotionTimer;

  /// Rapid expense entry (<5s logging)
  void addExpense({
    required String counterpartId,
    required String counterpartName,
    required String title,
    required int totalAmountCentavos,
    required ExpenseCategory category,
    required bool paidByMe,
    required bool isEqualSplit,
    DateTime? dueDate,
  }) {
    const currentUser = MockTabbyRepository.currentUser;
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
      paidByUserId: paidByMe ? currentUser.id : counterpartId,
      paidByName: paidByMe ? currentUser.displayName : counterpartName,
      date: now,
      dueDate: dueDate,
      status: TransactionStatus.acknowledged,
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
        currentUser.id,
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
      actorName: currentUser.displayName,
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

    _scheduleEmotionReset();
  }

  /// Settle or partially pay a tab ("Record Settlement" or "Confirm Payment")
  void settleTab({
    required String tabId,
    required int amountCentavos,
    required PaymentMethod method,
    required bool isPayingMe, // true if counterpart paid user; false if user paid counterpart
    String? note,
  }) {
    const currentUser = MockTabbyRepository.currentUser;
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
      paidByUserId: isPayingMe ? tab.counterpart.id : currentUser.id,
      paidByName: isPayingMe ? tab.counterpart.displayName : currentUser.displayName,
      date: now,
      status: TransactionStatus.settled,
      isPayment: true,
      paymentMethod: method,
      note: note,
    );

    final updatedEntries = [paymentEntry, ...tab.entries];
    final newNetBalance = MockTabbyRepository.calculateNetBalance(
      updatedEntries,
      currentUser.id,
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
      actorName: isPayingMe ? tab.counterpart.displayName : currentUser.displayName,
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

  @override
  void dispose() {
    _emotionTimer?.cancel();
    super.dispose();
  }
}

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
    return tabs.firstWhere((t) => t.id == tabId);
  } catch (_) {
    return null;
  }
});
