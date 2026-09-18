import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/services/device_auth_service.dart';
import '../../../core/services/pin_protection_service.dart';
import '../data/mock_tabby_repository.dart';
import '../data/supabase_tabby_repository.dart';
import '../data/tabby_local_cache.dart';
import '../domain/models.dart';
import 'tabby_state.dart';

/// Main Tabby Notifier managing bilateral tabs, activity logs, reminders, and mascot state machine
class TabbyNotifier extends StateNotifier<TabbyDashboardState> {
  TabbyNotifier({bool loadInitialData = true})
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
    if (loadInitialData) {
      _loadTabs();
    }
  }

  Future<bool> _loadTabs() async {
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
          final localMatch = localTabsPool.values
              .cast<BilateralTab?>()
              .firstWhere(
                (lt) =>
                    lt != null &&
                    (lt.id == st.id ||
                        (!lt.isGroupTab &&
                            !st.isGroupTab &&
                            ((lt.counterpart.id.isNotEmpty &&
                                    lt.counterpart.id == st.counterpart.id) ||
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
        return true;
      }
    } catch (e) {
      debugPrint('[TabbyNotifier] Live fetch error: $e');
    }
    return !hasLiveSession;
  }

  Future<bool> refreshTabs() async {
    return _loadTabs();
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
          ...state.friendRequests
              .where((existing) => existing.id != request.id),
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
    if (!mounted ||
        !SupabaseTabbyRepository.instance.isConnected ||
        tabId == null) {
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
    int participantCount = 2,
    String? payerId,
    String? payerName,
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
    final splitParticipantCount = participantCount < 2 ? 2 : participantCount;
    final effectivePayerId =
        payerId ?? (paidByMe ? currentUserId : counterpartId);
    final effectivePayerName =
        payerName ?? (paidByMe ? currentUserDisplayName : counterpartName);

    int myShare;
    int counterpartShare;

    if (isEqualSplit) {
      // Equal split with integer centavo division (ADR-001). For a group,
      // the current user owns one share and the remaining shares belong to
      // the other participants.
      myShare = totalAmountCentavos ~/ splitParticipantCount;
      counterpartShare = paidByMe ? totalAmountCentavos - myShare : 0;
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
      paidByUserId: effectivePayerId,
      paidByName: effectivePayerName,
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
        isTabOnlyParticipant: existingTab.isTabOnlyParticipant ||
            (!existingTab.isGroupTab && !isConnectedFriend),
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
        isTabOnlyParticipant: !isConnectedFriend,
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
            paidByUserId:
                paidByMe ? currentUserId : (payerId ?? resolvedCounterpartId),
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

  /// Creates a one-to-one tab for an unregistered person.
  ///
  /// Connected Friends enter through the accepted Friendship flow. This
  /// legacy helper remains for contact-tab creation and never creates a
  /// Friends-list relationship.
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
      isTabOnlyParticipant: true,
    );

    final newActivity = TabbyActivity(
      id: 'act-${now.millisecondsSinceEpoch}',
      actorName: 'You',
      description: 'created a one-to-one tab for $name',
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
    unawaited(createGroupTab(
      groupName: groupName,
      memberNames: memberNames,
      memberUserIds: memberUserIds,
    ));
  }

  /// Creates a group tab and returns the local or server-backed tab ID.
  ///
  /// The returned ID lets a Create Tab flow append the first expense to the
  /// same group tab, including when Supabase assigns the real UUID remotely.
  Future<String?> createGroupTab({
    required String groupName,
    required List<String> memberNames,
    List<String>? memberUserIds,
  }) async {
    final hasLiveSession =
        SupabaseConfig.isInitialized && SupabaseConfig.currentUserId != null;
    final currentUserId = hasLiveSession
        ? SupabaseConfig.currentUserId!
        : MockTabbyRepository.currentUser.id;

    var eligibleMemberUserIds = filterEligibleGroupMemberIds(
      requestedIds: memberUserIds ?? const [],
      friendRequests: state.friendRequests,
    );

    // Local/mock fixtures represent registered friends with a friend code but
    // do not always include a Friendship row. Keep those fixtures usable while
    // the live path remains restricted to accepted Friendship records.
    if (!hasLiveSession && state.friendRequests.isEmpty) {
      final registeredFixtureIds = state.tabs
          .where((tab) =>
              !tab.isGroupTab &&
              !tab.isTabOnlyParticipant &&
              tab.counterpart.friendCode?.trim().isNotEmpty == true)
          .map((tab) => tab.counterpart.id)
          .toSet();
      eligibleMemberUserIds = (memberUserIds ?? const [])
          .where(registeredFixtureIds.contains)
          .toList();
    }

    final acceptedNamesById = <String, String>{
      for (final request in state.friendRequests
          .where((request) => request.status == FriendRequestStatus.accepted))
        request.otherUser.id: request.otherUser.displayName,
    };
    final fixtureNamesById = <String, String>{
      for (final tab in state.tabs)
        if (!tab.isGroupTab &&
            tab.counterpart.friendCode?.trim().isNotEmpty == true)
          tab.counterpart.id: tab.counterpart.displayName,
    };
    final eligibleMemberNames = eligibleMemberUserIds
        .map((id) => acceptedNamesById[id] ?? fixtureNamesById[id])
        .whereType<String>()
        .toList();
    final resolvedMemberNames =
        eligibleMemberNames.isNotEmpty ? eligibleMemberNames : memberNames;

    final now = DateTime.now();
    final groupId =
        'group-${groupName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-')}-${now.millisecondsSinceEpoch % 10000}';
    final groupTab = BilateralTab(
      id: groupId,
      counterpart: TabbyUser(
        id: groupId,
        displayName: groupName,
        email: 'group@tabby.ph',
        phone: resolvedMemberNames.join(', '),
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
          'created group $groupName with ${eligibleMemberUserIds.length} members',
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

    await TabbyLocalCache.saveTabs(
      updatedTabs,
      userId: hasLiveSession ? currentUserId : null,
    );
    await TabbyLocalCache.saveActivities(
      updatedActivities,
      userId: hasLiveSession ? currentUserId : null,
    );

    if (hasLiveSession) {
      try {
        final newTabId = await SupabaseTabbyRepository.instance.createGroupTab(
          groupName: groupName,
          currentUserId: SupabaseConfig.currentUserId!,
          memberUserIds: eligibleMemberUserIds,
        );
        if (newTabId != null && newTabId != groupId) {
          final currentIndex =
              state.tabs.indexWhere((tab) => tab.id == groupId);
          if (currentIndex >= 0) {
            final fixedTabs = List<BilateralTab>.from(state.tabs);
            fixedTabs[currentIndex] = fixedTabs[currentIndex].copyWith(
              id: newTabId,
              counterpart: fixedTabs[currentIndex].counterpart.copyWith(
                    id: newTabId,
                  ),
            );
            state = state.copyWith(tabs: fixedTabs);
            await TabbyLocalCache.saveTabs(
              fixedTabs,
              userId: currentUserId,
            );
          }
          return newTabId;
        }
      } catch (e) {
        debugPrint('[TabbyNotifier] createGroupTab warning: $e');
      }
    }

    return groupId;
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

  /// Removes the social Friend relationship while preserving all financial history.
  Future<void> removeFriend(String friendId) async {
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

    final updatedTabs = List<BilateralTab>.from(state.tabs);
    final updatedFriendRequests = state.friendRequests.map((request) {
      if (request.otherUser.id != friendId) return request;
      return FriendRequest(
        id: request.id,
        requesterId: request.requesterId,
        addresseeId: request.addresseeId,
        requester: request.requester,
        addressee: request.addressee,
        status: FriendRequestStatus.declined,
        createdAt: request.createdAt,
        respondedAt: now,
        currentUserId: request.currentUserId,
      );
    }).toList();

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
      friendRequests: updatedFriendRequests,
    );

    TabbyLocalCache.saveTabs(
      updatedTabs,
      userId: hasLiveSession ? currentUserId : null,
    );
    TabbyLocalCache.saveActivities(
      updatedActivities,
      userId: hasLiveSession ? currentUserId : null,
    );
    if (SupabaseConfig.isInitialized &&
        SupabaseTabbyRepository.isValidUuid(friendId)) {
      await SupabaseTabbyRepository.instance.removeFriend(
        friendUserId: friendId,
      );
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

/// Dynamic list of registered accepted friends.
///
/// Friend visibility is driven by accepted friendship records, not by the
/// presence of a financial tab. Tab-only unregistered participants therefore
/// remain visible in My Tabs without leaking into the Friends domain.
final friendsProvider = Provider<List<TabbyUser>>((ref) {
  final dashboardState = ref.watch(tabbyProvider);
  final tabs = dashboardState.tabs;

  final acceptedFriends = <String, TabbyUser>{};
  for (final request in dashboardState.friendRequests) {
    if (request.status == FriendRequestStatus.accepted) {
      final friend = request.otherUser;
      if (friend.id.isNotEmpty) {
        acceptedFriends[friend.id] = friend;
      }
    }
  }

  // Live sessions must use the server-backed accepted relationship list. The
  // fallback is only for the repository's local mock mode and existing local
  // fixtures that represent a registered friend with a shareable Tabby ID.
  if (dashboardState.friendRequests.isNotEmpty ||
      SupabaseConfig.isInitialized) {
    for (final tab in tabs) {
      if (!tab.isGroupTab &&
          !tab.isTabOnlyParticipant &&
          acceptedFriends.containsKey(tab.counterpart.id)) {
        acceptedFriends[tab.counterpart.id] = tab.counterpart;
      }
    }
    return acceptedFriends.values.toList();
  }

  final seenIds = <String>{};
  final friends = <TabbyUser>[];
  for (final tab in tabs) {
    if (!tab.isGroupTab &&
        !tab.isTabOnlyParticipant &&
        tab.counterpart.friendCode?.isNotEmpty == true &&
        !seenIds.contains(tab.counterpart.id)) {
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

/// Persistent user security, notification, appearance, currency, and locale preferences.
enum SecurityMethod { none, biometric, pin, biometricAndPin }

@immutable
class UserSettings {
  final bool biometricsEnabled;
  final bool passcodeEnabled;
  final bool autoLockEnabled;
  final bool notificationsEnabled;
  final bool paymentAlertsEnabled;
  final bool reminderNudgesEnabled;
  final String currencyCode;
  final String languageCode;
  final bool motionEnabled;
  final bool darkModeEnabled;

  const UserSettings({
    this.biometricsEnabled = false,
    this.passcodeEnabled = false,
    this.autoLockEnabled = true,
    this.notificationsEnabled = true,
    this.paymentAlertsEnabled = true,
    this.reminderNudgesEnabled = true,
    this.currencyCode = 'PHP',
    this.languageCode = 'en',
    this.motionEnabled = true,
    this.darkModeEnabled = false,
  });

  SecurityMethod get securityMethod {
    if (biometricsEnabled && passcodeEnabled) {
      return SecurityMethod.biometricAndPin;
    }
    if (biometricsEnabled) return SecurityMethod.biometric;
    if (passcodeEnabled) return SecurityMethod.pin;
    return SecurityMethod.none;
  }

  UserSettings copyWith({
    bool? biometricsEnabled,
    bool? passcodeEnabled,
    bool? autoLockEnabled,
    bool? notificationsEnabled,
    bool? paymentAlertsEnabled,
    bool? reminderNudgesEnabled,
    String? currencyCode,
    String? languageCode,
    bool? motionEnabled,
    bool? darkModeEnabled,
  }) {
    return UserSettings(
      biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
      passcodeEnabled: passcodeEnabled ?? this.passcodeEnabled,
      autoLockEnabled: autoLockEnabled ?? this.autoLockEnabled,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      paymentAlertsEnabled: paymentAlertsEnabled ?? this.paymentAlertsEnabled,
      reminderNudgesEnabled:
          reminderNudgesEnabled ?? this.reminderNudgesEnabled,
      currencyCode: currencyCode ?? this.currencyCode,
      languageCode: languageCode ?? this.languageCode,
      motionEnabled: motionEnabled ?? this.motionEnabled,
      darkModeEnabled: darkModeEnabled ?? this.darkModeEnabled,
    );
  }
}

class UserSettingsNotifier extends StateNotifier<UserSettings> {
  UserSettingsNotifier({
    DeviceAuthService? auth,
    PinProtectionService? pinProtection,
    String? userId,
  })  : _auth = auth ?? LocalDeviceAuthService(),
        _pinProtection = pinProtection ?? PinProtectionService(),
        _userId = userId ?? 'offline',
        super(const UserSettings()) {
    _loadPersistedSettings();
  }

  static const _storage = FlutterSecureStorage();
  final DeviceAuthService _auth;
  final PinProtectionService _pinProtection;
  final String _userId;

  String _key(String name) => 'tabby_${_userId}_$name';

  Future<String?> _read(String name) async {
    return await _storage.read(key: _key(name)) ??
        await _storage.read(key: 'tabby_$name');
  }

  Future<void> _loadPersistedSettings() async {
    try {
      final bioStr = await _read('biometrics_enabled');
      final passStr = await _read('passcode_enabled');
      final lockStr = await _read('auto_lock_enabled');
      final notifStr = await _read('notifications_enabled');
      final payStr = await _read('payment_alerts_enabled');
      final remStr = await _read('reminder_nudges_enabled');
      final currencyStr = await _read('currency_code');
      final languageStr = await _read('language_code');
      final motionStr = await _read('motion_enabled');
      final darkModeStr = await _read('dark_mode_enabled');

      state = UserSettings(
        biometricsEnabled: bioStr == 'true',
        passcodeEnabled: passStr == 'true',
        autoLockEnabled: lockStr != null ? lockStr == 'true' : true,
        notificationsEnabled: notifStr != null ? notifStr == 'true' : true,
        paymentAlertsEnabled: payStr != null ? payStr == 'true' : true,
        reminderNudgesEnabled: remStr != null ? remStr == 'true' : true,
        currencyCode: currencyStr == 'USD' ? 'USD' : 'PHP',
        languageCode: languageStr == 'fil' ? 'fil' : 'en',
        motionEnabled: motionStr != null ? motionStr == 'true' : true,
        darkModeEnabled: darkModeStr == 'true',
      );
    } catch (e) {
      debugPrint('[UserSettingsNotifier] Error loading settings: $e');
    }
  }

  Future<bool> toggleBiometrics(bool enable) async {
    if (enable) {
      if (!await _auth.isSupported()) return false;
      final didAuthenticate = await _auth.authenticate(
        reason: 'Confirm your identity to secure Tabby',
        allowDeviceCredential: false,
      );
      if (!didAuthenticate) return false;
    }

    await update(biometricsEnabled: enable);
    return true;
  }

  Future<bool> enableBiometric() => toggleBiometrics(true);

  Future<List<BiometricType>> availableAuthMethods() async {
    return _auth.availableBiometrics();
  }

  Future<String> biometricLabel() async {
    final methods = await availableAuthMethods();
    if (methods.contains(BiometricType.face)) return 'Face ID';
    if (methods.contains(BiometricType.fingerprint)) return 'Fingerprint';
    if (methods.isNotEmpty) return 'Device biometrics';
    return 'No biometric sensor detected';
  }

  Future<bool> setPin(String pin) async {
    try {
      await _pinProtection.setPin(_userId, pin);
      await update(passcodeEnabled: true);
      return true;
    } catch (error) {
      debugPrint('[UserSettingsNotifier] Error setting PIN: $error');
      return false;
    }
  }

  Future<bool> verifyPin(String pin) => _pinProtection.verifyPin(_userId, pin);

  Future<void> clearPin() async {
    await _pinProtection.clearPin(_userId);
    await update(passcodeEnabled: false);
  }

  Future<void> toggleNotifications(bool enable) async {
    await update(notificationsEnabled: enable);
  }

  Future<void> update({
    bool? biometricsEnabled,
    bool? passcodeEnabled,
    bool? autoLockEnabled,
    bool? notificationsEnabled,
    bool? paymentAlertsEnabled,
    bool? reminderNudgesEnabled,
    String? currencyCode,
    String? languageCode,
    bool? motionEnabled,
    bool? darkModeEnabled,
  }) async {
    state = state.copyWith(
      biometricsEnabled: biometricsEnabled,
      passcodeEnabled: passcodeEnabled,
      autoLockEnabled: autoLockEnabled,
      notificationsEnabled: notificationsEnabled,
      paymentAlertsEnabled: paymentAlertsEnabled,
      reminderNudgesEnabled: reminderNudgesEnabled,
      currencyCode: currencyCode,
      languageCode: languageCode,
      motionEnabled: motionEnabled,
      darkModeEnabled: darkModeEnabled,
    );

    try {
      final values = <String, String?>{
        'biometrics_enabled': biometricsEnabled?.toString(),
        'passcode_enabled': passcodeEnabled?.toString(),
        'auto_lock_enabled': autoLockEnabled?.toString(),
        'notifications_enabled': notificationsEnabled?.toString(),
        'payment_alerts_enabled': paymentAlertsEnabled?.toString(),
        'reminder_nudges_enabled': reminderNudgesEnabled?.toString(),
        'currency_code': currencyCode,
        'language_code': languageCode,
        'motion_enabled': motionEnabled?.toString(),
        'dark_mode_enabled': darkModeEnabled?.toString(),
      };
      for (final entry in values.entries) {
        if (entry.value != null) {
          await _storage.write(key: _key(entry.key), value: entry.value);
        }
      }
    } catch (e) {
      debugPrint('[UserSettingsNotifier] Error saving settings: $e');
    }
  }
}

final userSettingsProvider =
    StateNotifierProvider<UserSettingsNotifier, UserSettings>((ref) {
  final user = ref.watch(currentUserProvider);
  return UserSettingsNotifier(userId: user.id);
});
