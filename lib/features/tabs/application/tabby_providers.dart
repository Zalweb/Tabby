import '../data/m2_command_queue.dart';
import '../../../core/services/appearance_preferences.dart';

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show
        AuthState,
        AuthChangeEvent,
        PostgresChangeEvent,
        PostgresChangePayload,
        RealtimeChannel,
        PostgrestException;
import 'package:uuid/uuid.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/config/session_scope.dart';
import '../../../core/services/device_auth_service.dart';
import '../../../core/services/reminder_submission_service.dart';
import '../../../core/services/pin_protection_service.dart';
import '../../../core/services/receipt_attachment_service.dart';
import '../../../core/services/tabby_notification_banner.dart';
import '../../../core/services/tabby_notification_service.dart';
import '../../../core/services/notification_preferences.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/philippine_phone.dart';
import '../data/mock_tabby_repository.dart';
import '../data/supabase_tabby_repository.dart';
import '../data/tabby_local_cache.dart';
import '../domain/models.dart';
import '../domain/activity_reconciliation.dart';
import '../domain/due_reminders.dart';
import '../domain/sync_report.dart';
import '../domain/ledger_validation.dart';
import '../domain/pair_obligations.dart';
import 'tabby_state.dart';

typedef ReminderScheduler = Future<void> Function(
  List<UpcomingReminder> previous,
  List<UpcomingReminder> next,
  String actorId,
);

Future<void> _updateDueAlarms(
  List<UpcomingReminder> previous,
  List<UpcomingReminder> next,
  String actorId,
) async {
  final session = SupabaseConfig.captureSession();
  bool active() =>
      SupabaseConfig.isCurrentSession(session) &&
      (!SupabaseConfig.isInitialized || session.accountId == actorId);
  final current = next.map((r) => r.id).toSet();
  for (final reminder in previous) {
    if (!active()) return;
    if (!current.contains(reminder.id)) {
      await TabbyNotificationService.instance.cancelReminder(reminder.id);
    }
  }
  for (final reminder in next) {
    if (!active()) return;
    await TabbyNotificationService.instance.scheduleDueReminder(
      reminderId: reminder.id,
      friendName: reminder.friendName,
      description: reminder.description,
      formattedAmount: CurrencyFormatter.formatCentavos(
        reminder.amountCentavos,
      ),
      dueDate: reminder.dueDate,
      iOweThem: reminder.isIWhoOwe,
      tabId: reminder.tabId,
    );
  }
}

/// Main Tabby Notifier managing bilateral tabs, activity logs, reminders, and mascot state machine
class TabbyNotifier extends StateNotifier<TabbyDashboardState> {
  TabbyNotifier({
    bool loadInitialData = true,
    ReminderScheduler? reminderScheduler,
    ReminderSubmissionService? reminderSubmission,
    Future<String?> Function(String, bool, String?)? paymentDecision,
    Future<List<BilateralTab>> Function(String)? tabLoader,
  }) : _reminderSubmission =
           reminderSubmission ??
           ReminderSubmissionService(
             send: SupabaseTabbyRepository.instance.submitReminderCommand,
           ),
       _reminderScheduler = reminderScheduler ?? _updateDueAlarms,
       _paymentDecision =
           paymentDecision ?? SupabaseTabbyRepository.instance.decidePayment,
       _tabLoader = tabLoader ?? SupabaseTabbyRepository.instance.fetchTabs,
       super(
         // When Supabase is initialized, start with an empty live state.
         // When running unit tests (Supabase not initialized), use mock data.
         SupabaseConfig.isInitialized
             ? TabbyDashboardState(
                 viewerUserId: SupabaseConfig.currentUserId,
                 tabs: const [],
                 activities: const [],
                 reminders: const [],
               )
             : TabbyDashboardState(
                 viewerUserId: MockTabbyRepository.currentUser.id,
                 tabs: MockTabbyRepository.getInitialTabs(),
                 activities: MockTabbyRepository.getInitialActivities(),
                 reminders: MockTabbyRepository.getInitialReminders(),
               ),
       ) {
    if (loadInitialData) {
      _loadTabs();
      if (SupabaseConfig.isInitialized &&
          SupabaseConfig.currentUserId != null) {
        _startRealtimeSubscription();
        unawaited(_syncPendingOps());
      }
    }
    // Re-load data whenever the user signs in (e.g. Google Sign-In).
    if (SupabaseConfig.isInitialized) {
      _authSub = SupabaseConfig.auth.onAuthStateChange.listen((data) {
        if (data.session != null && mounted) {
          if (data.event == AuthChangeEvent.signedIn) {
            _stopRealtimeSubscription();
            reset();
          }
          _startRealtimeSubscription();
          _loadTabs();
          _syncPendingOps();
        } else if (data.session == null && mounted) {
          _stopRealtimeSubscription();
          reset();
        }
      }, onError: (Object _, StackTrace __) {});
    }
    _startConnectivityWatch();
  }

  int _friendRequestRevision = 0;
  int _ledgerReadRevision = 0;
  final Future<List<BilateralTab>> Function(String) _tabLoader;

  static List<TabbyActivity> deduplicateActivities(List<TabbyActivity> list) =>
      reconcileActivityIds(list);

  static List<TabbyActivity> _deduplicateActivities(List<TabbyActivity> list) =>
      deduplicateActivities(list);

  static List<LedgerEntry> deduplicateLedgerEntries(List<LedgerEntry> list) =>
      MockTabbyRepository.deduplicateLedgerEntries(list);

  static List<BilateralTab> deduplicateTabs(
    List<BilateralTab> tabs, {
    String? currentUserId,
  }) => MockTabbyRepository.deduplicateTabs(tabs, currentUserId: currentUserId);

  Future<bool> _loadTabs({bool replayPending = true}) async {
    final ledgerRevision = ++_ledgerReadRevision;
    final requestRevision = _friendRequestRevision;
    final session = SupabaseConfig.captureSession();
    bool active() =>
        mounted &&
        ledgerRevision == _ledgerReadRevision &&
        SupabaseConfig.isCurrentSession(session);
    final hasLiveSession =
        SupabaseConfig.isInitialized && SupabaseConfig.currentUserId != null;
    if (SupabaseConfig.isInitialized && !hasLiveSession) {
      if (active()) {
        state = const TabbyDashboardState(
          tabs: [],
          activities: [],
          reminders: [],
        );
      }
      return false;
    }
    final currentUserId = hasLiveSession
        ? SupabaseConfig.currentUserId!
        : MockTabbyRepository.currentUser.id;
    if (active()) state = state.copyWith(viewerUserId: currentUserId);

    if (hasLiveSession) {
      if (_realtimeChannel == null) {
        _startRealtimeSubscription();
      }
      if (replayPending) unawaited(_syncPendingOps());
      final requests = await SupabaseTabbyRepository.instance
          .fetchFriendRequests(currentUserId);
      if (!active()) return false;
      if (active() && requestRevision == _friendRequestRevision) {
        state = state.copyWith(friendRequests: requests);
      }
    }

    // 1. Offline resilience: load from local cache first to prevent blank screens
    List<BilateralTab>? cachedTabs;
    try {
      final rawCachedTabs = await TabbyLocalCache.loadTabs(
        userId: hasLiveSession ? currentUserId : null,
      );
      if (rawCachedTabs != null) {
        cachedTabs = deduplicateTabs(
          rawCachedTabs,
          currentUserId: currentUserId,
        );
      }
      final cachedActivities = await TabbyLocalCache.loadActivities(
        userId: hasLiveSession ? currentUserId : null,
      );
      final cachedReminders = await TabbyLocalCache.loadReminders(
        userId: hasLiveSession ? currentUserId : null,
      );
      final cachedNotifications = await TabbyLocalCache.loadNotifications(
        userId: hasLiveSession ? currentUserId : null,
      );
      if (active() &&
          (cachedTabs != null ||
              cachedActivities != null ||
              cachedReminders != null ||
              cachedNotifications != null)) {
        final previous = cachedReminders ?? state.reminders;
        final reminders = deriveDueReminders(
          cachedTabs ?? state.tabs,
          currentUserId,
        );
        state = state.copyWith(
          tabs: cachedTabs ?? state.tabs,
          activities: _deduplicateActivities(
            cachedActivities ?? state.activities,
          ),
          reminders: reminders,
          notifications: cachedNotifications ?? state.notifications,
        );
        await _reconcileDueAlarmChanges(previous, reminders, currentUserId);
      }
    } catch (e) {
      debugPrint('[TabbyNotifier] Local cache load warning: $e');
    }

    // 2. Fetch live data from Supabase backend
    if (!active()) return false;
    try {
      final serverTabs = await _tabLoader(currentUserId);
      if (active()) {
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
          final localMatches = localTabsPool.values
              .where((lt) => MockTabbyRepository.sameRelationship(lt, st))
              .toList();

          for (final lm in localMatches) {
            processedLocalIds.add(lm.id);
          }

          // Combine entries: server entries take priority, merged with any unsynced local entries
          final cleanEntries = MockTabbyRepository.mergeServerEntries(
            st.entries,
            localMatches.expand((tab) => tab.entries),
          );
          final effectiveBalance = MockTabbyRepository.calculateNetBalance(
            cleanEntries,
            currentUserId,
          );

          mergedTabs.add(
            st.copyWith(
              entries: cleanEntries,
              itemCount: cleanEntries.length,
              netBalanceCentavos: effectiveBalance,
            ),
          );
        }

        // Add remaining local tabs that were not on server
        for (final entry in localTabsPool.entries) {
          if (!processedLocalIds.contains(entry.key)) {
            final alreadyInMerged = mergedTabs.any(
              (m) => MockTabbyRepository.sameRelationship(m, entry.value),
            );
            if (!alreadyInMerged) {
              final cleanLocalEntries = deduplicateLedgerEntries(
                entry.value.entries,
              );
              final effectiveBalance = MockTabbyRepository.calculateNetBalance(
                cleanLocalEntries,
                currentUserId,
              );
              mergedTabs.add(
                entry.value.copyWith(
                  entries: cleanLocalEntries,
                  itemCount: cleanLocalEntries.length,
                  netBalanceCentavos: effectiveBalance,
                ),
              );
            }
          }
        }

        // Final deduplication across all merged tabs to guarantee zero duplicate tabs
        final finalMergedTabs = deduplicateTabs(
          mergedTabs,
          currentUserId: currentUserId,
        );

        // Synthesize activities from all entries across merged tabs
        final serverActivities = <TabbyActivity>[];
        for (final tab in finalMergedTabs) {
          for (final entry in tab.entries) {
            serverActivities.add(
              activityForEntry(
                entry,
                currentUserId,
                tab.counterpart.displayName,
              ),
            );
          }
        }
        final allActivities = await TabbyLocalCache.resolveActivityMappings([
          ...serverActivities,
          ...state.activities,
        ], userId: hasLiveSession ? currentUserId : null);
        if (!active()) return false;
        allActivities.sort((a, b) => b.timestamp.compareTo(a.timestamp));

        final previousReminders = state.reminders;
        final allReminders = deriveDueReminders(finalMergedTabs, currentUserId);

        state = state.copyWith(
          tabs: finalMergedTabs,
          activities: allActivities,
          reminders: allReminders,
        );
        await TabbyLocalCache.saveTabs(
          finalMergedTabs,
          userId: hasLiveSession ? currentUserId : null,
        );
        if (!active()) return false;
        await TabbyLocalCache.saveActivities(
          allActivities,
          userId: hasLiveSession ? currentUserId : null,
        );
        if (!active()) return false;
        await TabbyLocalCache.saveReminders(
          allReminders,
          userId: hasLiveSession ? currentUserId : null,
        );
        if (!active()) return false;
        await _reconcileDueAlarmChanges(
          previousReminders,
          allReminders,
          currentUserId,
        );
        if (!active()) return false;

        if (hasLiveSession) {
          try {
            final remoteNotifs = await SupabaseTabbyRepository.instance
                .fetchNotifications(currentUserId);
            if (remoteNotifs.isNotEmpty && active()) {
              final seen = <String>{};
              final mergedNotifs = <AppNotification>[];
              for (final n in [...remoteNotifs, ...state.notifications]) {
                if (n.id.isNotEmpty && seen.add(n.id)) {
                  mergedNotifs.add(n);
                }
              }
              mergedNotifs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
              state = state.copyWith(notifications: mergedNotifs);
              await TabbyLocalCache.saveNotifications(
                mergedNotifs,
                userId: currentUserId,
              );
            }
          } catch (e) {
            debugPrint(
              '[TabbyNotifier] Remote notifications fetch warning: $e',
            );
          }
        }

        return active();
      }
    } catch (e) {
      debugPrint('[TabbyNotifier] Live fetch error: $e');
    }
    return active() && !hasLiveSession;
  }

  Future<bool> refreshTabs() async {
    final report = await synchronize();
    return report.synchronized || report.localSaved;
  }

  /// Entry checks only read server history; selecting a person cannot replay
  /// or create financial commands as a side effect.
  Future<bool> refreshExpenseHistory() => _loadTabs(replayPending: false);

  Future<BilateralTab?> inspectSharedTab(String otherUserId) async {
    final actor = SupabaseConfig.currentUserId;
    if (SupabaseConfig.isInitialized) {
      if (actor == null) throw StateError('Sign in again.');
      final id = await SupabaseTabbyRepository.instance.findSharedTabId(
        actor,
        otherUserId,
      );
      if (id == null) return null;
      if (!await refreshExpenseHistory()) {
        throw StateError('History is unavailable.');
      }
      final tab = state.tabs
          .where(
            (t) =>
                t.id == id &&
                !t.isGroupTab &&
                !t.isTabOnlyParticipant &&
                t.counterpart.id == otherUserId,
          )
          .firstOrNull;
      if (tab == null) {
        throw StateError('Refresh this shared tab before adding an expense.');
      }
      return tab;
    }
    return state.tabs
        .where(
          (t) =>
              !t.isGroupTab &&
              !t.isTabOnlyParticipant &&
              t.counterpart.id == otherUserId,
        )
        .firstOrNull;
  }

  Future<SyncReport> synchronize() async {
    final userId = SupabaseConfig.currentUserId;
    final live = SupabaseConfig.isInitialized && userId != null;
    await _syncPendingOps(refreshAfter: false);
    final refreshed = await _loadTabs(replayPending: false);
    final pending = await pendingSyncReport();
    return SyncReport(
      serverRefreshed: live && refreshed,
      localSaved: !SupabaseConfig.isInitialized && refreshed,
      pendingWrites: pending.pendingWrites,
      needsAttention: pending.needsAttention,
    );
  }

  Future<SyncReport> pendingSyncReport() async {
    final ops = await TabbyLocalCache.loadPendingOps(
      userId: SupabaseConfig.currentUserId,
      strict: true,
    );
    final attention = ops
        .where((op) => op['sync_state'] == 'needsAttention')
        .length;
    return SyncReport(
      serverRefreshed: false,
      pendingWrites: ops.length - attention,
      needsAttention: attention,
    );
  }

  Future<void> retryPendingWrites() async {
    final userId = SupabaseConfig.currentUserId;
    if (userId == null) return;
    await TabbyLocalCache.retryPendingWrites(userId: userId);
  }

  Future<TabbyUser?> findFriendByCode(String friendCode) async {
    final session = SupabaseConfig.captureSession();
    final user = await SupabaseTabbyRepository.instance.findUserByFriendCode(
      friendCode,
    );
    return mounted && SupabaseConfig.isCurrentSession(session) ? user : null;
  }

  Future<FriendRequest?> sendFriendRequestByCode(String friendCode) async {
    final session = SupabaseConfig.captureSession();
    final request = await SupabaseTabbyRepository.instance.sendFriendRequest(
      friendCode: friendCode,
    );
    if (!mounted || !SupabaseConfig.isCurrentSession(session)) return null;
    if (request != null) {
      ++_friendRequestRevision;
      state = state.copyWith(
        friendRequests: [
          request,
          ...state.friendRequests.where(
            (existing) => existing.id != request.id,
          ),
        ],
      );
    }
    return request;
  }

  Future<bool> respondToFriendRequest({
    required String friendshipId,
    required bool accept,
  }) async {
    final session = SupabaseConfig.captureSession();
    final tabId = await SupabaseTabbyRepository.instance.respondToFriendRequest(
      friendshipId: friendshipId,
      accept: accept,
    );
    if (!mounted ||
        !SupabaseConfig.isCurrentSession(session) ||
        !SupabaseTabbyRepository.instance.isConnected ||
        tabId == null) {
      return false;
    }

    ++_friendRequestRevision;
    final updatedRequests = state.friendRequests.map((request) {
      if (request.id == friendshipId) {
        return request.copyWith(
          status: accept
              ? FriendRequestStatus.accepted
              : FriendRequestStatus.declined,
          respondedAt: DateTime.now(),
        );
      }
      return request;
    }).toList();

    state = state.copyWith(friendRequests: updatedRequests);
    unawaited(_refreshFriendRequestsAndTabs());
    return true;
  }

  Future<void> _refreshFriendRequestsAndTabs() async {
    final requestRevision = _friendRequestRevision;
    final session = SupabaseConfig.captureSession();
    final currentUserId = SupabaseConfig.currentUserId;
    if (currentUserId == null || !mounted) return;
    try {
      final requests = await SupabaseTabbyRepository.instance
          .fetchFriendRequests(currentUserId);
      if (!mounted || !SupabaseConfig.isCurrentSession(session)) return;
      if (requestRevision == _friendRequestRevision) {
        state = state.copyWith(friendRequests: requests);
      }
      await _loadTabs();
    } catch (e) {
      debugPrint('[TabbyNotifier] _refreshFriendRequestsAndTabs error: $e');
    }
  }

  void reset() {
    ++_ledgerReadRevision;
    _stopRealtimeSubscription();
    state = SupabaseConfig.isInitialized
        ? TabbyDashboardState(
            viewerUserId: SupabaseConfig.currentUserId,
            tabs: const [],
            activities: const [],
            reminders: const [],
            notifications: const [],
          )
        : TabbyDashboardState(
            viewerUserId: MockTabbyRepository.currentUser.id,
            tabs: MockTabbyRepository.getInitialTabs(),
            activities: MockTabbyRepository.getInitialActivities(),
            reminders: MockTabbyRepository.getInitialReminders(),
            notifications: const [],
          );
  }

  /// Marks all notifications as read in state, local cache, and Supabase.
  Future<void> markAllNotificationsAsRead() async {
    final updated = state.notifications
        .map((n) => n.copyWith(isRead: true, readAt: DateTime.now()))
        .toList();
    state = state.copyWith(notifications: updated);
    final userId = SupabaseConfig.currentUserId;
    if (userId != null) {
      unawaited(TabbyLocalCache.saveNotifications(updated, userId: userId));
      unawaited(
        SupabaseTabbyRepository.instance.markAllNotificationsAsRead(userId),
      );
    }
  }

  /// Marks a specific notification as read in state, local cache, and Supabase.
  Future<void> markNotificationAsRead(String id) async {
    final updated = state.notifications.map((n) {
      if (n.id == id) {
        return n.copyWith(isRead: true, readAt: DateTime.now());
      }
      return n;
    }).toList();
    state = state.copyWith(notifications: updated);
    final userId = SupabaseConfig.currentUserId;
    if (userId != null) {
      unawaited(TabbyLocalCache.saveNotifications(updated, userId: userId));
      unawaited(SupabaseTabbyRepository.instance.markNotificationAsRead(id));
    }
  }

  void _recordAndDispatchNotification(AppNotification notif, {IconData? icon}) {
    if (!mounted) return;
    if (state.notifications.any((n) => n.id == notif.id)) return;
    final updated = [notif, ...state.notifications];
    state = state.copyWith(notifications: updated);

    final userId = SupabaseConfig.currentUserId;
    if (userId != null) {
      unawaited(TabbyLocalCache.saveNotifications(updated, userId: userId));
    }

    unawaited(_dispatchNotificationAlert(notif, icon: icon));
  }

  Future<void> _dispatchNotificationAlert(
    AppNotification notif, {
    IconData? icon,
  }) async {
    final session = SupabaseConfig.captureSession();
    final actor = session.accountId;
    if (actor == null) return;
    final kind = ['payment_submitted', 'payment_confirmed'].contains(notif.type)
        ? NotificationKind.payment
        : ['tab_reminder', 'manual_nudge', 'reminder'].contains(notif.type)
        ? NotificationKind.reminder
        : NotificationKind.system;
    try {
      final preferences = await const NotificationPreferencesStore().load(
        actor,
      );
      if (!mounted ||
          !SupabaseConfig.isCurrentSession(session) ||
          !preferences.allows(kind)) {
        return;
      }
    } catch (_) {
      return;
    }
    TabbyNotificationBanner.show(
      title: notif.title,
      body: notif.body,
      tabId: notif.relatedTabId,
      icon: icon ?? Icons.notifications_active_rounded,
    );

    if (notif.type == 'friend_request') {
      unawaited(
        TabbyNotificationService.instance.showFriendRequestAlert(
          eventId: notif.id,
          title: notif.title,
          body: notif.body,
          tabId: notif.relatedTabId,
        ),
      );
    } else if (notif.type == 'tab_reminder' ||
        notif.type == 'manual_nudge' ||
        notif.type == 'reminder') {
      unawaited(
        TabbyNotificationService.instance.showTabReminderAlert(
          eventId: notif.id,
          title: notif.title,
          body: notif.body,
          tabId: notif.relatedTabId,
        ),
      );
    } else if (notif.type == 'payment_submitted' ||
        notif.type == 'payment_confirmed') {
      unawaited(
        TabbyNotificationService.instance.showPaymentAlert(
          eventId: notif.id,
          title: notif.title,
          body: notif.body,
          tabId: notif.relatedTabId,
        ),
      );
    } else if (notif.type == 'expense_added' || notif.type == 'debt_created') {
      unawaited(
        TabbyNotificationService.instance.showExpenseAdded(
          eventId: notif.id,
          title: notif.title,
          body: notif.body,
          tabId: notif.relatedTabId,
        ),
      );
    } else {
      unawaited(
        TabbyNotificationService.instance.showNewTabCreated(
          eventId: notif.id,
          title: notif.title,
          body: notif.body,
          tabId: notif.relatedTabId,
        ),
      );
    }
  }

  @visibleForTesting
  void handleRealtimePayloadForTesting(PostgresChangePayload payload) {
    _handleRealtimePayload(payload);
  }

  void _handleRealtimePayload(PostgresChangePayload payload) {
    final currentUserId = SupabaseConfig.currentUserId;
    if (currentUserId == null) return;

    final table = payload.table;
    final newRec = payload.newRecord;
    final oldRec = payload.oldRecord;

    try {
      if (table == SupabaseConfig.tableNotifications) {
        if (payload.eventType == PostgresChangeEvent.insert &&
            newRec.isNotEmpty) {
          final recipient = newRec['recipient_user_id'] as String?;
          if (recipient == currentUserId) {
            final notif = AppNotification.fromSupabaseRow(newRec);
            if (notif != null) {
              _recordAndDispatchNotification(notif);
            }
          }
        }
      } else if (table == SupabaseConfig.tableTransactions) {
        if (payload.eventType == PostgresChangeEvent.insert &&
            newRec.isNotEmpty) {
          final createdBy = newRec['created_by'] as String?;
          if (createdBy != null && createdBy != currentUserId) {
            final title = (newRec['title'] as String?)?.trim();
            final safeTitle = (title != null && title.isNotEmpty)
                ? title
                : 'New expense';
            final amountCentavos =
                (newRec['total_amount_centavos'] as num?)?.toInt() ?? 0;
            final tabId = newRec['tab_id'] as String?;
            final formatted = CurrencyFormatter.formatCentavos(amountCentavos);
            final notif = AppNotification(
              id: 'tx_${newRec['id'] ?? DateTime.now().millisecondsSinceEpoch}',
              recipientUserId: currentUserId,
              type: 'expense_added',
              relatedTabId: tabId,
              relatedTransactionId: newRec['id'] as String?,
              title: 'New Expense Added',
              body: '$safeTitle ($formatted) was added to your tab.',
              isRead: false,
              createdAt: DateTime.now(),
            );
            _recordAndDispatchNotification(
              notif,
              icon: Icons.receipt_long_rounded,
            );
          }
        }
      } else if (table == SupabaseConfig.tablePayments) {
        if (newRec.isNotEmpty) {
          final payerId = newRec['payer_id'] as String?;
          final receiverId = newRec['receiver_id'] as String?;
          final submittedBy = newRec['submitted_by'] as String?;
          final confirmedBy = newRec['confirmed_by'] as String?;
          final status = newRec['status'] as String? ?? 'confirmed';
          final oldStatus = oldRec['status'] as String?;
          final tabId = newRec['tab_id'] as String?;
          final amountCentavos =
              (newRec['amount_centavos'] as num?)?.toInt() ?? 0;
          final formatted = CurrencyFormatter.formatCentavos(amountCentavos);

          if (payload.eventType == PostgresChangeEvent.insert) {
            if (submittedBy != currentUserId &&
                (payerId != currentUserId || receiverId == currentUserId)) {
              final notif = AppNotification(
                id: 'pay_${newRec['id'] ?? DateTime.now().millisecondsSinceEpoch}',
                recipientUserId: currentUserId,
                type: 'payment_submitted',
                relatedTabId: tabId,
                relatedPaymentId: newRec['id'] as String?,
                title: 'Payment Received',
                body: 'A payment of $formatted was recorded on your tab.',
                isRead: false,
                createdAt: DateTime.now(),
              );
              _recordAndDispatchNotification(
                notif,
                icon: Icons.payments_rounded,
              );
            }
          } else if (payload.eventType == PostgresChangeEvent.update) {
            if (status == 'confirmed' && oldStatus != 'confirmed') {
              if (payerId == currentUserId && confirmedBy != currentUserId) {
                final notif = AppNotification(
                  id: 'conf_${newRec['id'] ?? DateTime.now().millisecondsSinceEpoch}',
                  recipientUserId: currentUserId,
                  type: 'payment_confirmed',
                  relatedTabId: tabId,
                  relatedPaymentId: newRec['id'] as String?,
                  title: 'Payment Confirmed',
                  body: 'Your payment of $formatted was confirmed.',
                  isRead: false,
                  createdAt: DateTime.now(),
                );
                _recordAndDispatchNotification(
                  notif,
                  icon: Icons.check_circle_rounded,
                );
              }
            }
          }
        }
      } else if (table == SupabaseConfig.tableTabs) {
        if (payload.eventType == PostgresChangeEvent.insert &&
            newRec.isNotEmpty) {
          final createdBy = newRec['created_by'] as String?;
          if (createdBy != null && createdBy != currentUserId) {
            final tabId = newRec['id'] as String?;
            final tabTitle =
                (newRec['title'] as String?) ??
                (newRec['name'] as String?) ??
                'A tab';
            final notif = AppNotification(
              id: 'tab_${newRec['id'] ?? DateTime.now().millisecondsSinceEpoch}',
              recipientUserId: currentUserId,
              type: 'debt_created',
              relatedTabId: tabId,
              title: 'New Tab Opened',
              body: '$tabTitle was opened with you.',
              isRead: false,
              createdAt: DateTime.now(),
            );
            _recordAndDispatchNotification(
              notif,
              icon: Icons.bookmark_add_rounded,
            );
          }
        }
      } else if (table == SupabaseConfig.tableTabMembers) {
        if (payload.eventType == PostgresChangeEvent.insert &&
            newRec.isNotEmpty) {
          final memberUserId = newRec['user_id'] as String?;
          final createdBy = newRec['created_by'] as String?;
          if (memberUserId == currentUserId &&
              createdBy != null &&
              createdBy != currentUserId) {
            final tabId = newRec['tab_id'] as String?;
            final notif = AppNotification(
              id: 'member_${newRec['id'] ?? DateTime.now().millisecondsSinceEpoch}',
              recipientUserId: currentUserId,
              type: 'debt_created',
              relatedTabId: tabId,
              title: 'Added to Tab',
              body: 'You were added to a new shared tab.',
              isRead: false,
              createdAt: DateTime.now(),
            );
            _recordAndDispatchNotification(
              notif,
              icon: Icons.group_add_rounded,
            );
          }
        }
      } else if (table == SupabaseConfig.tableFriendships) {
        if (newRec.isNotEmpty) {
          final requesterId = newRec['requester_id'] as String?;
          final addresseeId = newRec['addressee_id'] as String?;
          final status = newRec['status'] as String?;

          debugPrint(
            '[TabbyNotifier] Realtime friendship event: status=$status, requester=$requesterId, addressee=$addresseeId, currentUserId=$currentUserId',
          );

          if (status == 'pending' && addresseeId == currentUserId) {
            final notif = AppNotification(
              id: 'fr_${newRec['id'] ?? DateTime.now().millisecondsSinceEpoch}',
              recipientUserId: currentUserId,
              type: 'friend_request',
              title: 'New Friend Request',
              body: 'You received a new friend request.',
              isRead: false,
              createdAt: DateTime.now(),
            );
            _recordAndDispatchNotification(
              notif,
              icon: Icons.person_add_rounded,
            );
          } else if (status == 'accepted') {
            if (requesterId == currentUserId) {
              final notif = AppNotification(
                id: 'fa_${newRec['id'] ?? DateTime.now().millisecondsSinceEpoch}',
                recipientUserId: currentUserId,
                type: 'friend_request',
                title: 'Friend Request Accepted',
                body: 'Your friend request was accepted.',
                isRead: false,
                createdAt: DateTime.now(),
              );
              _recordAndDispatchNotification(
                notif,
                icon: Icons.how_to_reg_rounded,
              );
            }
          }

          unawaited(_refreshFriendRequestsAndTabs());
        }
      } else if (table == SupabaseConfig.tableNotifications) {
        if (payload.eventType == PostgresChangeEvent.insert &&
            newRec.isNotEmpty) {
          final recipientId = newRec['recipient_user_id'] as String?;
          if (recipientId == currentUserId) {
            final notifId =
                newRec['id'] as String? ??
                'notif_${DateTime.now().millisecondsSinceEpoch}';
            final notifType =
                newRec['notification_type'] as String? ?? 'general';
            final title = newRec['title'] as String? ?? 'Notification';
            final body = newRec['body'] as String? ?? '';
            final tabId = newRec['related_tab_id'] as String?;

            final notif = AppNotification(
              id: notifId,
              recipientUserId: currentUserId,
              type: notifType,
              relatedTabId: tabId,
              title: title,
              body: body,
              isRead: false,
              createdAt: DateTime.now(),
            );

            IconData notifIcon = Icons.notifications_active_rounded;
            if (notifType == 'friend_request') {
              notifIcon = title.toLowerCase().contains('accepted')
                  ? Icons.how_to_reg_rounded
                  : Icons.person_add_rounded;
            } else if (notifType.contains('payment')) {
              notifIcon = Icons.payments_rounded;
            } else if (notifType.contains('expense') ||
                notifType.contains('debt')) {
              notifIcon = Icons.receipt_long_rounded;
            } else if (notifType == 'tab_reminder' ||
                notifType == 'manual_nudge') {
              notifIcon = Icons.alarm_rounded;
            }

            _recordAndDispatchNotification(notif, icon: notifIcon);

            if (notifType == 'friend_request') {
              unawaited(_refreshFriendRequestsAndTabs());
            } else {
              _realtimeDebounceTimer?.cancel();
              _realtimeDebounceTimer = Timer(
                const Duration(milliseconds: 350),
                () {
                  if (mounted) {
                    _loadTabs();
                  }
                },
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[TabbyNotifier] _handleRealtimePayload error: $e');
    }
  }

  Timer? _emotionTimer;
  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _syncInFlight = false;
  bool _syncRequested = false;
  RealtimeChannel? _realtimeChannel;
  Timer? _realtimeDebounceTimer;

  void _startRealtimeSubscription() {
    if (!SupabaseConfig.isInitialized) return;
    final userId = SupabaseConfig.currentUserId;
    if (userId == null) return;
    if (_realtimeChannel != null) return;

    try {
      final channel = SupabaseConfig.client.channel(
        'public:tabby_realtime_$userId',
      );

      void onPostgresChange(PostgresChangePayload payload) {
        debugPrint(
          '[TabbyNotifier] Realtime Postgres change on ${payload.table} (${payload.eventType})',
        );
        _handleRealtimePayload(payload);
        _realtimeDebounceTimer?.cancel();
        _realtimeDebounceTimer = Timer(const Duration(milliseconds: 350), () {
          if (mounted) {
            _loadTabs();
          }
        });
      }

      final tables = [
        SupabaseConfig.tableTabs,
        SupabaseConfig.tableTabMembers,
        SupabaseConfig.tableTransactions,
        SupabaseConfig.tableTransactionParticipants,
        SupabaseConfig.tablePayments,
        SupabaseConfig.tablePaymentProofs,
        SupabaseConfig.tableFriendships,
        SupabaseConfig.tableNotifications,
        SupabaseConfig.tableActivityLogs,
        SupabaseConfig.tableGroups,
        SupabaseConfig.tableGroupMembers,
      ];

      for (final table in tables) {
        channel.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          callback: onPostgresChange,
        );
      }

      channel.subscribe((status, [error]) {
        if (error != null) {
          debugPrint('[TabbyNotifier] Realtime subscription error: $error');
        } else {
          debugPrint('[TabbyNotifier] Realtime subscription status: $status');
        }
      });

      _realtimeChannel = channel;
    } catch (e) {
      debugPrint('[TabbyNotifier] Failed to start Realtime subscription: $e');
    }
  }

  void _stopRealtimeSubscription() {
    _realtimeDebounceTimer?.cancel();
    _realtimeDebounceTimer = null;
    if (_realtimeChannel != null && SupabaseConfig.isInitialized) {
      try {
        SupabaseConfig.client.removeChannel(_realtimeChannel!);
      } catch (e) {
        debugPrint('[TabbyNotifier] Error removing Realtime channel: $e');
      }
      _realtimeChannel = null;
    }
  }

  Future<void> addExpense({
    String? operationId,
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
    Map<String, int>? customAmounts,
  }) async {
    if (totalAmountCentavos <= 0) {
      throw ArgumentError.value(
        totalAmountCentavos,
        'totalAmountCentavos',
        'must be greater than zero',
      );
    }
    final currentUserId = SupabaseConfig.isInitialized
        ? (SupabaseConfig.currentUserId ?? MockTabbyRepository.currentUser.id)
        : MockTabbyRepository.currentUser.id;
    final currentUserDisplayName =
        SupabaseConfig.isInitialized && SupabaseConfig.currentUser != null
        ? (SupabaseConfig.currentUser!.userMetadata?['display_name'] ??
              MockTabbyRepository.currentUser.displayName)
        : MockTabbyRepository.currentUser.displayName;

    final exactTabIndex = state.tabs.indexWhere((t) => t.id == counterpartId);
    final existingTabIndex = exactTabIndex >= 0
        ? exactTabIndex
        : state.tabs.indexWhere(
            (t) => !t.isGroupTab && t.counterpart.id == counterpartId,
          );
    final groupTab = existingTabIndex < 0 ? null : state.tabs[existingTabIndex];
    final isGroup = groupTab?.isGroupTab == true;
    final financialCounterpartId = !isGroup && groupTab != null
        ? groupTab.counterpart.id
        : counterpartId;
    final now = DateTime.now();
    final splitParticipantCount = isGroup
        ? groupTab!.members.length
        : (participantCount < 2 ? 2 : participantCount);
    final effectivePayerId =
        payerId ?? (paidByMe ? currentUserId : financialCounterpartId);
    final effectivePayerName =
        payerName ?? (paidByMe ? currentUserDisplayName : counterpartName);

    LedgerValidation.validateExpense(
      totalAmountCentavos: totalAmountCentavos,
      isEqualSplit: isEqualSplit,
      participantCount: splitParticipantCount,
      paidByMe: paidByMe,
      currentUserId: currentUserId,
      counterpartId: isGroup ? effectivePayerId : financialCounterpartId,
      payerId: payerId,
      payerName: payerName,
    );

    int myShare;
    int counterpartShare;
    final customShares = customAmounts == null
        ? null
        : LedgerValidation.customShares(
            total: totalAmountCentavos,
            members: isGroup
                ? groupTab!.members
                : [
                    TabbyUser(
                      id: currentUserId,
                      displayName: currentUserDisplayName,
                      email: '',
                      phone: '',
                    ),
                    groupTab?.counterpart ??
                        TabbyUser(
                          id: counterpartId,
                          displayName: counterpartName,
                          email: '',
                          phone: '',
                        ),
                  ],
            payerId: effectivePayerId,
            amounts: customAmounts,
          );
    final explicitShares = isGroup
        ? customShares ??
              LedgerValidation.groupShares(
                total: totalAmountCentavos,
                members: groupTab!.members,
                payerId: effectivePayerId,
                equalSplit: isEqualSplit,
              )
        : const <ParticipantShare>[];

    if (customShares != null) {
      myShare = customShares
          .singleWhere((p) => p.userId == currentUserId)
          .shareAmountCentavos;
      counterpartShare = totalAmountCentavos - myShare;
    } else if (isGroup) {
      myShare = explicitShares
          .singleWhere((p) => p.userId == currentUserId)
          .shareAmountCentavos;
      counterpartShare = totalAmountCentavos - myShare;
    } else if (isEqualSplit) {
      // Equal split with integer centavo division (ADR-001). For a group,
      // the current user owns one share and the remaining shares belong to
      // the other participants.
      myShare = LedgerValidation.equalSplitShare(
        totalAmountCentavos: totalAmountCentavos,
        participantCount: splitParticipantCount,
      );
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

    final expenseOperationId = operationId ?? const Uuid().v4();
    final newEntry = LedgerEntry(
      receiptHistory: receiptUrl == null ? const [] : [receiptUrl],
      participants: explicitShares,
      id: 'entry-$expenseOperationId',
      tabId: groupTab?.id ?? counterpartId,
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

    // A retained form may retry after the durable handoff or server ACK. Reuse
    // the original operation; never append a second local representation.
    if (operationId != null) {
      final stamp = SupabaseConfig.captureSession();
      final mapping = await TabbyLocalCache.loadEntryMapping(
        newEntry.id,
        userId: currentUserId,
      );
      if (!mounted || !SupabaseConfig.isCurrentSession(stamp)) {
        throw StateError('Session changed.');
      }
      final prior = state.tabs
          .expand((tab) => tab.entries)
          .where(
            (entry) =>
                entry.id == newEntry.id || entry.id == mapping?['entry_id'],
          )
          .firstOrNull;
      if (prior != null) {
        if (existingTabIndex < 0 ||
            !state.tabs[existingTabIndex].entries.any(
              (entry) => entry.id == prior.id,
            )) {
          throw StateError('Operation ID belongs to a different tab.');
        }
        if (prior.totalAmountCentavos != newEntry.totalAmountCentavos ||
            prior.title != newEntry.title ||
            prior.category != newEntry.category ||
            prior.paidByUserId != newEntry.paidByUserId ||
            prior.myShareCentavos != newEntry.myShareCentavos ||
            prior.counterpartShareCentavos !=
                newEntry.counterpartShareCentavos ||
            prior.dueDate != newEntry.dueDate ||
            (isGroup &&
                (prior.participants
                            .map((p) => '${p.userId}:${p.shareAmountCentavos}')
                            .toList()
                          ..sort())
                        .toString() !=
                    (newEntry.participants
                            .map((p) => '${p.userId}:${p.shareAmountCentavos}')
                            .toList()
                          ..sort())
                        .toString())) {
          throw StateError(
            'Operation ID reused with different expense details.',
          );
        }
        return;
      }
      if (mapping != null) return; // acknowledged, awaiting history refresh
    }

    // Find tab or create new tab
    List<BilateralTab> updatedTabs;

    if (existingTabIndex >= 0) {
      final existingTab = state.tabs[existingTabIndex];
      final updatedEntries = deduplicateLedgerEntries([
        newEntry,
        ...existingTab.entries,
      ]);
      final newNetBalance = MockTabbyRepository.calculateNetBalance(
        updatedEntries,
        currentUserId,
      );

      final updatedTab = existingTab.copyWith(
        entries: updatedEntries,
        netBalanceCentavos: newNetBalance,
        itemCount: updatedEntries.length,
        lastUpdated: now,
        isTabOnlyParticipant:
            existingTab.isTabOnlyParticipant ||
            (!existingTab.isGroupTab && !isConnectedFriend),
      );

      updatedTabs = List<BilateralTab>.from(state.tabs);
      updatedTabs[existingTabIndex] = updatedTab;
    } else {
      // Create new bilateral tab
      final newTab = BilateralTab(
        isLocalOnly: true,
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
    final expenseTitle = title.trim().isEmpty
        ? category.displayName
        : title.trim();
    final newActivity = TabbyActivity(
      id: newEntry.id,
      actorName: paidByMe ? 'You' : counterpartName,
      description: expenseTitle,
      amountCentavos: totalAmountCentavos,
      timestamp: now,
      icon: category.name,
      iconData: category.icon,
    );

    final previousReminders = state.reminders;
    final updatedReminders = deriveDueReminders(updatedTabs, currentUserId);

    final updatedActivities = _deduplicateActivities([
      newActivity,
      ...state.activities,
    ]);

    final cacheUserId = SupabaseConfig.isInitialized
        ? SupabaseConfig.currentUserId
        : null;
    final isGroupTab =
        existingTabIndex >= 0 && state.tabs[existingTabIndex].isGroupTab;
    final pendingExpenseOp = <String, dynamic>{
      'operation_id': expenseOperationId,
      'type': 'add_expense',
      'local_entry_id': newEntry.id,
      'needs_tab_resolution':
          existingTabIndex < 0 || state.tabs[existingTabIndex].isLocalOnly,
      'tab_id': existingTabIndex >= 0
          ? state.tabs[existingTabIndex].id
          : counterpartId,
      'is_group_tab': isGroupTab,
      if (isGroupTab)
        'participants': explicitShares.map((p) => p.toMap()).toList(),
      'is_connected_friend': isConnectedFriend,
      'title': expenseTitle,
      'total_amount_centavos': totalAmountCentavos,
      'category': category.name,
      'paid_by_user_id': effectivePayerId,
      'my_share_centavos': myShare,
      'counterpart_share_centavos': counterpartShare,
      'counterpart_id': financialCounterpartId,
      'counterpart_name': counterpartName,
      'paid_by_me': paidByMe,
      'due_date': dueDate?.toIso8601String(),
      'receipt_url': receiptUrl,
    };
    // The write intent must be durable before local state claims the expense.
    if (cacheUserId != null) {
      pendingExpenseOp['receipt_bytes'] =
          await ReceiptAttachmentService.readPendingReceiptBytes(
            receiptUrl,
            userId: cacheUserId,
          );
      await TabbyLocalCache.enqueuePendingOp(
        pendingExpenseOp,
        userId: cacheUserId,
      );
      if (!mounted || SupabaseConfig.currentUserId != cacheUserId) return;
    }

    state = state.copyWith(
      tabs: updatedTabs,
      activities: updatedActivities,
      reminders: updatedReminders,
      emotionOverride: MascotEmotion.calculating,
      emotionCustomMessage: 'Tab logged successfully! Calculating balances...',
    );

    await TabbyLocalCache.saveTabs(updatedTabs, userId: cacheUserId);
    await TabbyLocalCache.saveActivities(
      updatedActivities,
      userId: cacheUserId,
    );
    await TabbyLocalCache.saveReminders(updatedReminders, userId: cacheUserId);
    await _reconcileDueAlarmChanges(
      previousReminders,
      updatedReminders,
      currentUserId,
    );

    if (cacheUserId != null) await _syncPendingOps();

    _scheduleEmotionReset();
  }

  final ReminderScheduler _reminderScheduler;
  Future<void>? _reminderWork;

  Future<void> _reconcileDueAlarmChanges(
    List<UpcomingReminder> previous,
    List<UpcomingReminder> next,
    String actorId,
  ) {
    final session = SupabaseConfig.captureSession();
    final prior = _reminderWork;
    late final Future<void> guard;
    Future<void> execute() async {
      try {
        await Future<void>.value();
        if (prior != null) await prior;
        if (!mounted ||
            !SupabaseConfig.isCurrentSession(session) ||
            (SupabaseConfig.isInitialized && session.accountId != actorId)) {
          return;
        }
        await _reminderScheduler(previous, next, actorId);
      } catch (error) {
        // Alarm failure does not undo an acknowledged financial command.
        debugPrint('[TabbyNotifier] Due alarm update failed: $error');
      } finally {
        if (identical(_reminderWork, guard)) _reminderWork = null;
      }
    }

    final work = execute();
    guard = work.catchError((Object _) {});
    _reminderWork = guard;
    return work;
  }

  Future<void> refreshDueReminders() async {
    final session = SupabaseConfig.captureSession();
    final actor =
        SupabaseConfig.currentUserId ??
        (SupabaseConfig.isInitialized
            ? null
            : MockTabbyRepository.currentUser.id);
    if (actor == null || !mounted) return;
    final previous = state.reminders;
    final next = deriveDueReminders(state.tabs, actor);
    state = state.copyWith(reminders: next);
    await TabbyLocalCache.saveReminders(
      next,
      userId: SupabaseConfig.isInitialized ? actor : null,
    );
    if (mounted && SupabaseConfig.isCurrentSession(session)) {
      await _reconcileDueAlarmChanges(previous, next, actor);
    }
  }

  final Future<String?> Function(String, bool, String?) _paymentDecision;

  Future<void> decidePayment(
    String paymentId, {
    required bool confirm,
    String? reason,
  }) async {
    final session = SupabaseConfig.captureSession();
    void current() {
      if (!mounted || !SupabaseConfig.isCurrentSession(session)) {
        throw StateError('Session changed.');
      }
    }

    final actor =
        SupabaseConfig.currentUserId ?? MockTabbyRepository.currentUser.id;
    final tab = state.tabs
        .where((t) => t.entries.any((e) => e.id == paymentId))
        .firstOrNull;
    final payment = tab?.entries.where((e) => e.id == paymentId).firstOrNull;
    if (payment == null ||
        !payment.isPayment ||
        payment.recipient?.kind != PartyKind.user ||
        payment.recipient?.id != actor) {
      throw const TabValidationException(
        'Only the recipient can decide this payment.',
      );
    }
    if (!confirm &&
        ((reason?.trim().isEmpty ?? true) || reason!.length > 500)) {
      throw const TabValidationException(
        'Add a rejection reason of 1 to 500 characters.',
      );
    }
    final result = await _paymentDecision(paymentId, confirm, reason?.trim());
    current();
    if (result != paymentId) {
      throw StateError('The payment decision was not saved. Please try again.');
    }
    // A snapshot captured before this decision cannot replace its acknowledged
    // status/balance, even when it belongs to this same account and session.
    ++_ledgerReadRevision;
    final updated = state.tabs.map((t) {
      if (t.id != tab!.id) return t;
      final entries = t.entries
          .map(
            (e) => e.id == paymentId
                ? e.copyWith(
                    status: confirm
                        ? TransactionStatus.settled
                        : TransactionStatus.cancelled,
                    rejectionReason: confirm ? null : reason?.trim(),
                  )
                : e,
          )
          .toList();
      return t.copyWith(
        entries: entries,
        netBalanceCentavos: MockTabbyRepository.calculateNetBalance(
          entries,
          actor,
        ),
      );
    }).toList();
    final previousReminders = state.reminders;
    final reminders = deriveDueReminders(updated, actor);
    final decided = updated
        .firstWhere((t) => t.id == tab!.id)
        .entries
        .firstWhere((entry) => entry.id == paymentId);
    state = state.copyWith(
      tabs: updated,
      reminders: reminders,
      activities: reconcileActivityIds([
        activityForEntry(decided, actor, tab!.counterpart.displayName),
        ...state.activities,
      ]),
    );
    await TabbyLocalCache.saveTabs(
      updated,
      userId: SupabaseConfig.currentUserId,
      strict: true,
    );
    current();
    await TabbyLocalCache.saveActivities(
      state.activities,
      userId: actor,
      strict: true,
    );
    current();
    await TabbyLocalCache.saveReminders(reminders, userId: actor);
    current();
    await _reconcileDueAlarmChanges(previousReminders, reminders, actor);
    current();
  }

  Future<void> settleTab({
    String? operationId,
    required String tabId,
    required int amountCentavos,
    required PaymentMethod method,
    required bool isPayingMe,
    String? note,
    String? proofPath,
    String? paymentReference,
  }) => _recordSettlement(
    operationId: operationId,
    tabId: tabId,
    amountCentavos: amountCentavos,
    method: method,
    isPayingMe: isPayingMe,
    note: note,
    proofPath: proofPath,
    paymentReference: paymentReference,
  );

  Future<void> settleGroupPair({
    String? operationId,
    required String tabId,
    required String counterpartyUserId,
    required int amountCentavos,
    required PaymentMethod method,
    required bool isPayingMe,
    String? note,
    String? proofPath,
    String? paymentReference,
  }) => _recordSettlement(
    operationId: operationId,
    tabId: tabId,
    counterpartyUserId: counterpartyUserId,
    amountCentavos: amountCentavos,
    method: method,
    isPayingMe: isPayingMe,
    note: note,
    proofPath: proofPath,
    paymentReference: paymentReference,
  );

  Future<void> _recordSettlement({
    String? operationId,
    String? counterpartyUserId,
    required String tabId,
    required int amountCentavos,
    required PaymentMethod method,
    required bool
    isPayingMe, // true if counterpart paid user; false if user paid counterpart
    String? note,
    String? proofPath,
    String? paymentReference,
  }) async {
    if (isPayingMe && method != PaymentMethod.cash) {
      throw const TabValidationException(
        'Confirm the original wallet submission, or record cash received.',
      );
    }
    if (amountCentavos <= 0) {
      throw ArgumentError.value(
        amountCentavos,
        'amountCentavos',
        'must be greater than zero',
      );
    }
    final currentUserId = SupabaseConfig.isInitialized
        ? (SupabaseConfig.currentUserId ?? MockTabbyRepository.currentUser.id)
        : MockTabbyRepository.currentUser.id;
    final currentUserDisplayName =
        SupabaseConfig.isInitialized && SupabaseConfig.currentUser != null
        ? (SupabaseConfig.currentUser!.userMetadata?['display_name'] ??
              MockTabbyRepository.currentUser.displayName)
        : MockTabbyRepository.currentUser.displayName;

    final now = DateTime.now();

    var tabIndex = state.tabs.indexWhere(
      (t) => t.id == tabId || t.counterpart.id == tabId,
    );
    if (tabIndex < 0) {
      throw const TabValidationException(
        'This tab is no longer available. Refresh before paying.',
      );
    }

    var tab = state.tabs[tabIndex];
    final counterpart = tab.isGroupTab
        ? tab.members
              .where((m) => m.id == counterpartyUserId && m.id != currentUserId)
              .firstOrNull
        : tab.counterpart;
    if (counterpart == null) {
      throw const TabValidationException(
        'Select the actual group member for this payment.',
      );
    }
    if (operationId != null) {
      final replayStamp = SupabaseConfig.captureSession();
      final mapping = await TabbyLocalCache.loadEntryMapping(
        'payment-$operationId',
        userId: currentUserId,
      );
      if (!mounted || !SupabaseConfig.isCurrentSession(replayStamp)) {
        throw StateError('Session changed.');
      }
      final prior = state.tabs
          .expand((tab) => tab.entries)
          .where(
            (entry) =>
                entry.id == 'payment-$operationId' ||
                entry.id == mapping?['entry_id'],
          )
          .firstOrNull;
      if (prior != null) {
        if (!tab.entries.any((entry) => entry.id == prior.id)) {
          throw StateError('Operation ID belongs to a different tab.');
        }
        if (!prior.isPayment ||
            prior.totalAmountCentavos != amountCentavos ||
            prior.paymentMethod != method ||
            prior.paidByUserId !=
                (isPayingMe ? counterpart.id : currentUserId) ||
            prior.recipient?.id !=
                (isPayingMe ? currentUserId : counterpart.id) ||
            prior.paymentReference != paymentReference?.trim()) {
          throw StateError(
            'Operation ID reused with different payment details.',
          );
        }
        return;
      }
      if (mapping != null) return;
    }
    int outstanding(BilateralTab value) => value.isGroupTab
        ? -pairOutstanding(value.entries, currentUserId, counterpart.id)
        : value.netBalanceCentavos;
    if (outstanding(tab) == 0 || amountCentavos > outstanding(tab).abs()) {
      throw ArgumentError(
        'Payment cannot exceed the current outstanding tab balance.',
      );
    }

    LedgerValidation.validatePayment(
      amountCentavos: amountCentavos,
      netBalanceCentavos: outstanding(tab),
      isPayingMe: isPayingMe,
    );

    final cacheUserId = SupabaseConfig.isInitialized
        ? SupabaseConfig.currentUserId
        : null;
    final session = SupabaseConfig.captureSession();
    final reference = paymentReference?.trim();
    if (reference != null && reference.length > 200) {
      throw const TabValidationException(
        'Payment reference must be at most 200 characters.',
      );
    }
    final hasProof = proofPath != null || (reference?.isNotEmpty ?? false);
    final proofBytes = await ReceiptAttachmentService.readPendingReceiptBytes(
      proofPath,
      userId: currentUserId,
    );
    final paymentOperationId = operationId ?? const Uuid().v4();
    final pendingPaymentOp = <String, dynamic>{
      'operation_id': paymentOperationId,
      'type': 'settle_payment',
      if (proofPath != null) 'proof_path': proofPath,
      if (proofBytes != null) 'proof_bytes': proofBytes,
      if (reference?.isNotEmpty ?? false) 'payment_reference': reference,
      'tab_id': tab.id,
      'amount_centavos': amountCentavos,
      'method': method.name,
      'is_paying_me': isPayingMe,
      'counterpart_id': counterpart.id,
      'counterpart_name': counterpart.displayName,
      'note': note,
      'local_entry_id': 'payment-$paymentOperationId',
      'is_contact': tab.isTabOnlyParticipant,
      'is_group_tab': tab.isGroupTab,
      'needs_tab_resolution': tab.isLocalOnly,
    };
    // The payment intent must be durable before local state records it.
    if (cacheUserId != null || hasProof) {
      await TabbyLocalCache.enqueuePendingOp(
        pendingPaymentOp,
        userId: cacheUserId,
      );
      if (!mounted || !SupabaseConfig.isCurrentSession(session)) return;
      tabIndex = state.tabs.indexWhere(
        (t) => t.id == tabId || t.counterpart.id == tabId,
      );
      if (tabIndex < 0) return;
      tab = state.tabs[tabIndex];
      if (outstanding(tab) == 0 || amountCentavos > outstanding(tab).abs()) {
        await TabbyLocalCache.removePendingOp(
          pendingPaymentOp,
          userId: cacheUserId,
        );
        throw ArgumentError(
          'Payment cannot exceed the current outstanding tab balance.',
        );
      }
    }

    final paymentEntry = LedgerEntry(
      receiptHistory: proofPath == null ? const [] : [proofPath],
      receiptUrl: proofPath,
      paymentReference: reference,
      id: 'payment-$paymentOperationId',
      tabId: tab.id,
      title: isPayingMe
          ? '${counterpart.displayName} paid via ${method.label}'
          : 'You paid ${counterpart.displayName} via ${method.label}',
      category: ExpenseCategory.borrowedCash,
      totalAmountCentavos: amountCentavos,
      myShareCentavos: 0,
      counterpartShareCentavos: 0,
      paidByUserId: isPayingMe ? counterpart.id : currentUserId,
      payer: PartyRef(
        kind: isPayingMe && tab.isTabOnlyParticipant
            ? PartyKind.contact
            : PartyKind.user,
        id: isPayingMe ? counterpart.id : currentUserId,
      ),
      recipient: PartyRef(
        kind: !isPayingMe && tab.isTabOnlyParticipant
            ? PartyKind.contact
            : PartyKind.user,
        id: isPayingMe ? currentUserId : counterpart.id,
      ),
      paidByName: isPayingMe ? counterpart.displayName : currentUserDisplayName,
      date: now,
      status:
          (isPayingMe ||
              (tab.isTabOnlyParticipant && method == PaymentMethod.cash))
          ? TransactionStatus.settled
          : TransactionStatus.paymentSubmitted,
      isPayment: true,
      paymentMethod: method,
      note: note,
    );

    final updatedEntries = deduplicateLedgerEntries([
      paymentEntry,
      ...tab.entries,
    ]);
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

    final previousReminders = state.reminders;
    final updatedReminders = deriveDueReminders(updatedTabs, currentUserId);
    final actorSettled = updatedTab.isGroupTab
        ? !groupObligations(updatedTab).any(
            (pair) =>
                pair.payerId == currentUserId ||
                pair.recipientId == currentUserId,
          )
        : newNetBalance == 0;

    final newActivity = TabbyActivity(
      id: paymentEntry.id,
      actorName: isPayingMe ? counterpart.displayName : 'You',
      description: paymentEntry.title,
      amountCentavos: amountCentavos,
      timestamp: now,
      icon: 'payment',
      iconData: method.iconData,
    );

    final updatedActivities = _deduplicateActivities([
      newActivity,
      ...state.activities,
    ]);

    state = state.copyWith(
      tabs: updatedTabs,
      activities: updatedActivities,
      reminders: updatedReminders,
      emotionOverride: isPayingMe
          ? MascotEmotion.celebrating
          : MascotEmotion.calculating,
      emotionCustomMessage:
          tab.isTabOnlyParticipant && method == PaymentMethod.cash
          ? 'Cash payment recorded.'
          : !isPayingMe
          ? 'Payment submitted. Your balance updates after confirmation.'
          : actorSettled
          ? 'Your balance in this tab is clear.'
          : 'Payment recorded! Remaining balance updated.',
    );

    await TabbyLocalCache.saveTabs(updatedTabs, userId: cacheUserId);
    await TabbyLocalCache.saveActivities(
      updatedActivities,
      userId: cacheUserId,
    );
    await TabbyLocalCache.saveReminders(updatedReminders, userId: cacheUserId);
    await _reconcileDueAlarmChanges(
      previousReminders,
      updatedReminders,
      currentUserId,
    );

    if (cacheUserId != null) await _syncPendingOps();

    _scheduleEmotionReset(seconds: 4);
  }

  final ReminderSubmissionService _reminderSubmission;

  /// Accepted means queued in the recipient's inbox, never delivered/read.
  Future<ReminderSendResult> sendGentleNudge({
    required String tabId,
    required String friendName,
    required int amountCentavos,
    String? recipientUserId,
    String? description,
    String? customTitle,
    String? customBody,
  }) async {
    final session = SupabaseConfig.captureSession();
    final actor = session.accountId ?? MockTabbyRepository.currentUser.id;
    final tab = state.tabs.where((t) => t.id == tabId).firstOrNull;
    final recipient =
        recipientUserId ??
        (tab?.isGroupTab == false && tab?.isTabOnlyParticipant == false
            ? tab!.counterpart.id
            : null);
    if (tab == null ||
        recipient == null ||
        recipient == actor ||
        pairOutstanding(tab.entries, recipient, actor) <= 0) {
      return ReminderSendResult.unavailable;
    }
    bool current() => mounted && SupabaseConfig.isCurrentSession(session);
    final name =
        SupabaseConfig.currentUser?.userMetadata?['display_name'] as String? ??
        MockTabbyRepository.currentUser.displayName;
    final command = <String, dynamic>{
      'tab_id': tabId,
      'recipient_user_id': recipient,
      'title': customTitle ?? '$name sent you a friendly reminder',
      'body': customBody ?? 'You have an outstanding balance on our shared tab. Open Tabby to review it.',
    };
    try {
      final id = await _reminderSubmission.submit(
        actor,
        command,
        current: current,
      );
      if (!current()) return ReminderSendResult.sessionChanged;
      if (id == null) return ReminderSendResult.failed;
      final activity = TabbyActivity(
        id: id,
        actorName: name,
        description: 'sent friendly reminder to $friendName',
        amountCentavos: amountCentavos,
        timestamp: DateTime.now(),
        iconData: Icons.send_rounded,
      );
      state = state.copyWith(
        activities: reconcileActivityIds([activity, ...state.activities]),
        emotionOverride: MascotEmotion.gentleNudge,
        emotionCustomMessage: ReminderSendResult.accepted.message,
      );
      await TabbyLocalCache.saveActivities(state.activities, userId: actor);
      if (!current()) return ReminderSendResult.sessionChanged;
      _scheduleEmotionReset(seconds: 5);
      return ReminderSendResult.accepted;
    } catch (_) {
      return current()
          ? ReminderSendResult.failed
          : ReminderSendResult.sessionChanged;
    }
  }

  void setTemporaryEmotion(
    MascotEmotion emotion, {
    String? message,
    int durationSeconds = 3,
  }) {
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
    String tabId = const Uuid().v4();
    String counterpartId = tabId;

    if (hasLiveSession && SupabaseTabbyRepository.isValidUuid(currentUserId)) {
      try {
        final contactRes = await SupabaseTabbyRepository.instance
            .getOrCreateContactTab(
              ownerId: currentUserId,
              contactId: counterpartId,
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
      isLocalOnly: tabId == counterpartId,
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
    final updatedActivities = _deduplicateActivities([
      newActivity,
      ...state.activities,
    ]);

    state = state.copyWith(tabs: updatedTabs, activities: updatedActivities);

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
    unawaited(
      createGroupTab(
        groupName: groupName,
        memberNames: memberNames,
        memberUserIds: memberUserIds,
      ),
    );
  }

  /// Creates a group tab and returns the local or server-backed tab ID.
  ///
  /// The returned ID lets a Create Tab flow append the first expense to the
  /// same group tab, including when Supabase assigns the real UUID remotely.
  Future<String?> createGroupTab({
    String? operationId,
    required String groupName,
    required List<String> memberNames,
    List<String>? memberUserIds,
  }) async {
    final session = SupabaseConfig.captureSession();
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
          .where(
            (tab) =>
                !tab.isGroupTab &&
                !tab.isTabOnlyParticipant &&
                tab.counterpart.friendCode?.trim().isNotEmpty == true,
          )
          .map((tab) => tab.counterpart.id)
          .toSet();
      eligibleMemberUserIds = (memberUserIds ?? const [])
          .where(registeredFixtureIds.contains)
          .toList();
    }

    final acceptedNamesById = <String, String>{
      for (final request in state.friendRequests.where(
        (request) => request.status == FriendRequestStatus.accepted,
      ))
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
    final resolvedMemberNames = eligibleMemberNames.isNotEmpty
        ? eligibleMemberNames
        : memberNames;

    final commandId = operationId ?? const Uuid().v4();
    String? remoteId;
    if (hasLiveSession) {
      if (eligibleMemberUserIds.isEmpty ||
          eligibleMemberUserIds.length !=
              (memberUserIds ?? const []).toSet().length) {
        throw const TabValidationException(
          'Choose accepted registered friends for this group.',
        );
      }
      remoteId = await SupabaseTabbyRepository.instance.createGroupTab(
        groupName: groupName,
        currentUserId: currentUserId,
        operationId: commandId,
        memberUserIds: eligibleMemberUserIds,
      );
      if (!mounted ||
          !SupabaseConfig.isCurrentSession(session) ||
          remoteId == null) {
        return null;
      }
      if (state.tabs.any((t) => t.id == remoteId)) return remoteId;
    }
    final now = DateTime.now();
    final groupId = remoteId ?? 'group-$commandId';
    if (state.tabs.any((tab) => tab.id == groupId)) return groupId;
    final groupTab = BilateralTab(
      isLocalOnly: !hasLiveSession,
      members: [
        TabbyUser(id: currentUserId, displayName: 'You', email: '', phone: ''),
        for (final id in eligibleMemberUserIds)
          TabbyUser(
            id: id,
            displayName:
                acceptedNamesById[id] ?? fixtureNamesById[id] ?? 'Member',
            email: '',
            phone: '',
          ),
      ],
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
    final updatedActivities = _deduplicateActivities([
      newActivity,
      ...state.activities,
    ]);

    state = state.copyWith(tabs: updatedTabs, activities: updatedActivities);

    await TabbyLocalCache.saveTabs(
      updatedTabs,
      userId: hasLiveSession ? currentUserId : null,
    );
    await TabbyLocalCache.saveActivities(
      updatedActivities,
      userId: hasLiveSession ? currentUserId : null,
    );

    return groupId;
  }

  /// End the social link only after its server acknowledgment. All ledger,
  /// pair balances, receipts, reminders and group membership remain intact.
  Future<bool> removeFriend(
    String friendId, {
    Future<bool> Function()? persist,
  }) async {
    _friendRequestRevision++;
    final session = SupabaseConfig.captureSession();
    final actor = state.viewerUserId;
    try {
      final accepted = persist != null
          ? await persist()
          : SupabaseConfig.isInitialized
          ? await SupabaseTabbyRepository.instance.removeFriend(
              friendUserId: friendId,
            )
          : true;
      if (!accepted ||
          !mounted ||
          state.viewerUserId != actor ||
          !SupabaseConfig.isCurrentSession(session)) {
        return false;
      }
      final now = DateTime.now();
      var requests = state.friendRequests
          .map(
            (request) => request.otherUser.id == friendId
                ? request.copyWith(
                    status: FriendRequestStatus.declined,
                    respondedAt: now,
                  )
                : request,
          )
          .toList();
      if (!SupabaseConfig.isInitialized && requests.isEmpty) {
        final friend = state.tabs
            .where((tab) => !tab.isGroupTab && tab.counterpart.id == friendId)
            .firstOrNull
            ?.counterpart;
        if (friend != null) {
          requests = [
            FriendRequest(
              id: 'local-removed-$friendId',
              requesterId: actor ?? MockTabbyRepository.currentUser.id,
              addresseeId: friendId,
              requester: MockTabbyRepository.currentUser,
              addressee: friend,
              status: FriendRequestStatus.declined,
              createdAt: now,
              respondedAt: now,
              currentUserId: actor ?? MockTabbyRepository.currentUser.id,
            ),
          ];
        }
      }
      state = state.copyWith(friendRequests: requests);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Attaches a receipt or bill photo URL to a transaction entry
  Future<void> attachReceiptToEntry({
    String? operationId,
    required String tabId,
    required String entryId,
    required String receiptUrl,
  }) async {
    final session = SupabaseConfig.captureSession();
    final hasLiveSession =
        SupabaseConfig.isInitialized && SupabaseConfig.currentUserId != null;
    final currentUserId = hasLiveSession
        ? SupabaseConfig.currentUserId!
        : MockTabbyRepository.currentUser.id;
    final mapping = await TabbyLocalCache.loadEntryMapping(
      entryId,
      userId: hasLiveSession ? currentUserId : null,
    );
    if (!mounted || !SupabaseConfig.isCurrentSession(session)) return;
    if (mapping != null) {
      entryId = mapping['entry_id'] as String;
      tabId = mapping['tab_id'] as String;
    }

    var tabIndex = state.tabs.indexWhere(
      (t) => t.id == tabId || t.counterpart.id == tabId,
    );
    if (tabIndex < 0) return;
    var tab = state.tabs[tabIndex];
    final entry = tab.entries.where((e) => e.id == entryId).firstOrNull;
    if (entry == null) throw StateError('Entry unavailable.');
    if (entry.receiptHistory.contains(receiptUrl)) return;
    {
      final bytes = await ReceiptAttachmentService.readPendingReceiptBytes(
        receiptUrl,
        userId: currentUserId,
      );
      await TabbyLocalCache.enqueuePendingOp({
        'operation_id': operationId ?? const Uuid().v4(),
        'type': 'append_receipt',
        'target_kind': entry.isPayment ? 'payment' : 'transaction',
        'local_entry_id': entryId,
        'target_entry_id': entryId,
        if (entryId.startsWith('entry-'))
          'depends_on_operation_id': entryId.substring(6),
        if (entryId.startsWith('payment-'))
          'depends_on_operation_id': entryId.substring(8),
        'proof_path': receiptUrl,
        if (bytes != null) 'proof_bytes': bytes,
      }, userId: hasLiveSession ? currentUserId : null);
    }

    if (!mounted || !SupabaseConfig.isCurrentSession(session)) return;
    tabIndex = state.tabs.indexWhere((t) => t.id == tab.id);
    if (tabIndex < 0) return;
    tab = state.tabs[tabIndex];
    final updatedEntries = tab.entries.map((e) {
      if (e.id == entryId) {
        return e.copyWith(
          receiptUrl: receiptUrl,
          receiptHistory: {
            ...e.receiptHistory,
            if (e.receiptUrl != null) e.receiptUrl!,
            receiptUrl,
          }.toList(),
        );
      }
      return e;
    }).toList();

    final updatedTab = tab.copyWith(entries: updatedEntries);
    final updatedTabs = List<BilateralTab>.from(state.tabs);
    updatedTabs[tabIndex] = updatedTab;

    state = state.copyWith(tabs: updatedTabs);
    await TabbyLocalCache.saveTabs(
      updatedTabs,
      userId: hasLiveSession ? currentUserId : null,
    );

    if (hasLiveSession) await _syncPendingOps();
  }

  /// Starts watching connectivity changes. When the device comes back online
  /// and a Supabase session exists, drains the pending-ops queue and syncs
  /// any tabs that were logged offline.
  void _startConnectivityWatch() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      (results) {
        final isOnline = results.any((r) => r != ConnectivityResult.none);
        if (isOnline &&
            SupabaseConfig.isInitialized &&
            SupabaseConfig.currentUserId != null) {
          _syncPendingOps();
        }
      },
      onError: (Object error) {
        debugPrint(
          '[TabbyNotifier] Connectivity watcher unavailable (${error.runtimeType}).',
        );
      },
    );
  }

  Future<bool> _hasNetworkConnection() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((result) => result != ConnectivityResult.none);
    } catch (e) {
      debugPrint('[TabbyNotifier] Connectivity check warning: $e');
      return false;
    }
  }

  Future<String?> _finishContactProof(
    Map<String, dynamic> op,
    String paymentId,
    String userId,
    SessionStamp session,
  ) async {
    if (op['proof_path'] == null && op['payment_reference'] == null) {
      return null;
    }
    var command = op['proof_command'] as Map?;
    if (command == null) {
      final path = await ReceiptAttachmentService.uploadPendingReceipt(
        op['proof_path'] as String?,
        entryKey: op['operation_id'] as String,
        userId: userId,
        encodedBytes: op['proof_bytes'] as String?,
      );
      if (!SupabaseConfig.isCurrentSession(session)) {
        throw StateError('Session changed.');
      }
      command = await TabbyLocalCache.prepareProofCommand(
        op['operation_id'] as String,
        userId: userId,
        command: {
          (op['target_kind'] == 'transaction'
                  ? 'transaction_id'
                  : 'payment_id'):
              paymentId,
          'proof_path': path,
          'reference': op['payment_reference'],
        },
      );
    }
    final result = await SupabaseConfig.client.rpc(
      op['target_kind'] == 'transaction'
          ? 'append_transaction_receipt_v1'
          : 'append_payment_proof_v1',
      params: {'p_operation_id': op['operation_id'], 'p_command': command},
    );
    if (result is! String || !SupabaseTabbyRepository.isValidUuid(result)) {
      throw StateError('Invalid proof result.');
    }
    if (!SupabaseConfig.isCurrentSession(session)) {
      throw StateError('Session changed.');
    }
    return command['proof_path'] as String?;
  }

  Future<void> _commitMoneyResult(
    Map<String, dynamic> op,
    String result,
    String remoteTabId,
    String userId,
    SessionStamp session,
  ) async {
    final durable =
        (await TabbyLocalCache.loadPendingOps(userId: userId, strict: true))
            .where((pending) => pending['operation_id'] == op['operation_id'])
            .firstOrNull;
    final wire = durable?['rpc_command'] as Map?;
    final proof = durable?['proof_command'] as Map?;
    final proofPath =
        (wire?['proof_path'] ?? wire?['p_receipt_url'] ?? proof?['proof_path'])
            as String?;
    final cached = await TabbyLocalCache.loadTabs(userId: userId);
    if (!mounted ||
        !SupabaseConfig.isCurrentSession(session) ||
        SupabaseConfig.currentUserId != userId) {
      return;
    }
    final candidates = deduplicateTabs([
      ...?cached,
      ...state.tabs,
    ], currentUserId: userId);
    final mapped = MockTabbyRepository.applyOperationResult(
      candidates,
      localEntryId: op['local_entry_id'] as String,
      remoteTabId: remoteTabId,
      remoteEntryId: result,
      currentUserId: userId,
    );
    final tabs = proofPath == null
        ? mapped
        : mapped
              .map(
                (tab) => tab.copyWith(
                  entries: tab.entries
                      .map(
                        (entry) => entry.id == result
                            ? entry.copyWith(
                                receiptUrl: proofPath,
                                receiptHistory: entry.receiptHistory
                                    .map(
                                      (ref) =>
                                          ref == op['proof_path'] ||
                                              ref == op['receipt_url']
                                          ? proofPath
                                          : ref,
                                    )
                                    .toSet()
                                    .toList(),
                              )
                            : entry,
                      )
                      .toList(),
                ),
              )
              .toList();
    // Persist server identity before acknowledging the queue. A crash/retry
    // between these writes replays the same server result without reinserting.
    state = state.copyWith(
      tabs: tabs,
      activities: reconcileActivityIds(
        state.activities,
        mappings: {op['local_entry_id'] as String: result},
      ),
    );
    await TabbyLocalCache.saveTabs(tabs, userId: userId, strict: true);
    if (!mounted ||
        !SupabaseConfig.isCurrentSession(session) ||
        SupabaseConfig.currentUserId != userId) {
      return;
    }
    await TabbyLocalCache.saveEntryMapping(
      op['local_entry_id'] as String,
      result,
      remoteTabId,
      userId: userId,
    );
    if (!mounted || !SupabaseConfig.isCurrentSession(session)) return;
    await TabbyLocalCache.saveActivities(
      state.activities,
      userId: userId,
      strict: true,
    );
    if (!mounted || !SupabaseConfig.isCurrentSession(session)) return;
    await TabbyLocalCache.remapPendingProofTargets(
      op['local_entry_id'] as String,
      result,
      userId: userId,
    );
    await TabbyLocalCache.removePendingOp(op, userId: userId);
    if (mounted && SupabaseConfig.isCurrentSession(session)) {
      await refreshDueReminders();
    }
  }

  /// Replays queued offline expense and settlement operations against Supabase.
  /// Each operation remains durable until its remote write succeeds.
  M2CommandQueue get m2Commands =>
      M2CommandQueue.forSession(() => _syncPendingOps());

  Future<void> _syncPendingOps({bool refreshAfter = true}) async {
    final session = SupabaseConfig.captureSession();
    final userId = SupabaseConfig.currentUserId;
    if (userId == null || !mounted) return;
    if (_syncInFlight) {
      _syncRequested = true;
      return;
    }
    _syncInFlight = true;
    try {
      if (!await _hasNetworkConnection() ||
          !SupabaseConfig.isCurrentSession(session)) {
        return;
      }
      final ops = await TabbyLocalCache.loadPendingOps(
        userId: userId,
        strict: true,
      );
      if (ops.isEmpty) return;
      debugPrint(
        '[TabbyNotifier] Syncing ${ops.length} pending offline operation(s)...',
      );
      for (final op in ops) {
        if (!mounted ||
            !SupabaseConfig.isCurrentSession(session) ||
            SupabaseConfig.currentUserId != userId) {
          break;
        }
        if (!TabbyLocalCache.canAttemptPendingOp(op, DateTime.now())) continue;
        try {
          if (op['type'] == 'm2_command') {
            final rpc = op['m2_rpc'] as String;
            final command = Map<String, dynamic>.from(op['m2_command'] as Map);
            if (!M2CommandQueue.rpcs.contains(rpc) ||
                command['p_expected_actor'] != userId) {
              throw UnsupportedError('Invalid saved M2 command');
            }
            final result = await SupabaseTabbyRepository.instance
                .executeMoneyCommand(
                  operationId: op['operation_id'] as String,
                  rpc: rpc,
                  command: command,
                );
            if (!mounted || !SupabaseConfig.isCurrentSession(session)) return;
            await M2CommandQueue.saveResult(
              userId,
              op['operation_id'] as String,
              result,
            );
            if (!mounted || !SupabaseConfig.isCurrentSession(session)) return;
            await TabbyLocalCache.removePendingOp(op, userId: userId);
            continue;
          }
          if (op['type'] == 'append_payment_proof' ||
              op['type'] == 'append_receipt') {
            final target = op['target_entry_id'] as String;
            if (!SupabaseTabbyRepository.isValidUuid(target)) {
              if (ops.any(
                (pending) =>
                    pending['operation_id'] == op['depends_on_operation_id'],
              )) {
                continue;
              }
              throw UnsupportedError(
                'Payment proof needs an explicit server payment identity.',
              );
            }
            final path = await _finishContactProof(op, target, userId, session);
            if (!mounted || !SupabaseConfig.isCurrentSession(session)) return;
            final tabs = state.tabs
                .map(
                  (tab) => tab.copyWith(
                    entries: tab.entries
                        .map(
                          (e) => e.id == target
                              ? e.copyWith(
                                  receiptUrl: path,
                                  receiptHistory: e.receiptHistory
                                      .map(
                                        (ref) => ref == op['proof_path']
                                            ? path ?? ref
                                            : ref,
                                      )
                                      .toSet()
                                      .toList(),
                                )
                              : e,
                        )
                        .toList(),
                  ),
                )
                .toList();
            state = state.copyWith(tabs: tabs);
            await TabbyLocalCache.saveTabs(tabs, userId: userId, strict: true);
            await TabbyLocalCache.removePendingOp(op, userId: userId);
            continue;
          }
          if (op['local_entry_id'] == null) {
            throw UnsupportedError(
              'Legacy financial intent needs explicit identity reconciliation.',
            );
          }
          if (op['rpc_name'] != null && op['rpc_command'] is Map) {
            final command = Map<String, dynamic>.from(op['rpc_command'] as Map);
            final result = await SupabaseTabbyRepository.instance
                .executeMoneyCommand(
                  operationId: op['operation_id'] as String,
                  rpc: op['rpc_name'] as String,
                  command: command,
                );
            if (!SupabaseConfig.isCurrentSession(session)) return;
            if (op['type'] == 'settle_payment' &&
                op['rpc_name'] == 'record_received_payment_v1') {
              await _finishContactProof(op, result, userId, session);
            }
            await _commitMoneyResult(
              op,
              result,
              command['p_tab_id'] as String,
              userId,
              session,
            );
            continue;
          }
          final type = op['type'] as String?;
          if (type == 'add_expense') {
            if (op['is_group_tab'] == true && op['participants'] is! List) {
              throw UnsupportedError(
                'Legacy group expense needs explicit participant review.',
              );
            }
            final tabId = op['tab_id'] as String?;
            final counterpartId = op['counterpart_id'] as String? ?? '';
            final counterpartName = op['counterpart_name'] as String? ?? '';
            final totalAmountCentavos = (op['total_amount_centavos'] as num)
                .toInt();
            final myShare = (op['my_share_centavos'] as num).toInt();
            final counterpartShare = (op['counterpart_share_centavos'] as num)
                .toInt();
            final paidByMe = op['paid_by_me'] as bool? ?? true;
            final dueDateStr = op['due_date'] as String?;
            final dueDate = dueDateStr != null
                ? DateTime.tryParse(dueDateStr)
                : null;
            final receiptUrl = op['receipt_url'] as String?;
            final category = ExpenseCategory.values.firstWhere(
              (c) => c.name == op['category'],
              orElse: () => ExpenseCategory.other,
            );

            final isGroupTab = op['is_group_tab'] as bool? ?? false;
            final isConnectedFriend =
                op['is_connected_friend'] as bool? ?? false;
            String? realTabId = tabId;
            String resolvedCounterpartId = counterpartId;

            if (op['needs_tab_resolution'] == true ||
                realTabId == null ||
                !SupabaseTabbyRepository.isValidUuid(realTabId)) {
              if (isGroupTab) {
                throw StateError('Group tab has not synchronized yet.');
              }
              if (isConnectedFriend &&
                  SupabaseTabbyRepository.isValidUuid(counterpartId) &&
                  counterpartId != userId) {
                realTabId = await SupabaseConfig.getOrCreateBilateralTab(
                  userA: userId,
                  userB: counterpartId,
                );
              } else {
                final contactResult = await SupabaseTabbyRepository.instance
                    .getOrCreateContactTab(
                      ownerId: userId,
                      contactId: counterpartId,
                      contactName: counterpartName,
                    );
                realTabId = contactResult?['tab_id'];
                resolvedCounterpartId =
                    contactResult?['contact_id'] ?? counterpartId;
              }
            }

            if (realTabId != null &&
                SupabaseTabbyRepository.isValidUuid(realTabId)) {
              if (!SupabaseConfig.isCurrentSession(session)) return;
              final storedPayerId = op['paid_by_user_id'] as String?;
              final remotePayerId = paidByMe
                  ? userId
                  : (isGroupTab
                        ? storedPayerId ?? counterpartId
                        : resolvedCounterpartId);
              final uploadedReceiptUrl =
                  await ReceiptAttachmentService.uploadPendingReceipt(
                    receiptUrl,
                    entryKey: op['operation_id'] as String? ?? realTabId,
                    userId: userId,
                    encodedBytes: op['receipt_bytes'] as String?,
                  );
              final result = await SupabaseTabbyRepository.instance.logExpense(
                explicitShares: isGroupTab
                    ? (op['participants'] as List<dynamic>?)
                          ?.map(
                            (p) => ParticipantShare.fromMap(
                              Map<String, dynamic>.from(p as Map),
                            ),
                          )
                          .toList()
                    : null,
                tabId: realTabId,
                operationId: op['operation_id'] as String,
                title: op['title'] as String? ?? '',
                totalAmountCentavos: totalAmountCentavos,
                category: category,
                paidByUserId: remotePayerId,
                myShareCentavos: myShare,
                counterpartShareCentavos: counterpartShare,
                currentUserId: userId,
                counterpartId: resolvedCounterpartId,
                dueDate: dueDate,
                receiptUrl: uploadedReceiptUrl,
              );
              if (result == null) {
                throw StateError('Pending expense sync was not accepted.');
              }
              if (!SupabaseConfig.isCurrentSession(session)) return;
              await _commitMoneyResult(op, result, realTabId, userId, session);
            } else {
              throw StateError('Unable to resolve pending expense tab.');
            }
          } else if (type == 'settle_payment') {
            final tabId = op['tab_id'] as String?;
            final amountCentavos = (op['amount_centavos'] as num).toInt();
            final methodName = op['method'] as String?;
            final isPayingMe = op['is_paying_me'] as bool? ?? false;
            final counterpartId = op['counterpart_id'] as String? ?? '';
            final counterpartName =
                op['counterpart_name'] as String? ?? 'Friend';
            final note = op['note'] as String?;

            final method = PaymentMethod.values.firstWhere(
              (m) => m.name == methodName,
              orElse: () => PaymentMethod.cash,
            );

            String? realTabId = tabId;
            var resolvedCounterpartId = counterpartId;
            if (op['needs_tab_resolution'] == true ||
                realTabId == null ||
                !SupabaseTabbyRepository.isValidUuid(realTabId)) {
              if (op['is_contact'] != true &&
                  SupabaseTabbyRepository.isValidUuid(userId) &&
                  SupabaseTabbyRepository.isValidUuid(counterpartId) &&
                  userId != counterpartId) {
                realTabId = await SupabaseConfig.getOrCreateBilateralTab(
                  userA: userId,
                  userB: counterpartId,
                );
              } else if (SupabaseTabbyRepository.isValidUuid(userId)) {
                final contactResult = await SupabaseTabbyRepository.instance
                    .getOrCreateContactTab(
                      ownerId: userId,
                      contactId: counterpartId,
                      contactName: counterpartName,
                    );
                if (contactResult != null) {
                  realTabId = contactResult['tab_id'];
                  resolvedCounterpartId =
                      contactResult['contact_id'] ?? counterpartId;
                }
              }
            }

            if (realTabId != null &&
                SupabaseTabbyRepository.isValidUuid(realTabId)) {
              final proofPath = op['proof_path'] as String?;
              final paymentReference = op['payment_reference'] as String?;
              final uploadedProof = op['is_contact'] == true
                  ? null
                  : await ReceiptAttachmentService.uploadPendingReceipt(
                      proofPath,
                      entryKey: op['operation_id'] as String,
                      userId: userId,
                      encodedBytes: op['proof_bytes'] as String?,
                    );
              if (!SupabaseConfig.isCurrentSession(session)) return;
              final effectivePaidBy =
                  SupabaseTabbyRepository.isValidUuid(counterpartId)
                  ? (isPayingMe ? counterpartId : userId)
                  : userId;
              final effectiveReceivedBy =
                  SupabaseTabbyRepository.isValidUuid(counterpartId)
                  ? (isPayingMe ? userId : counterpartId)
                  : userId;

              if (op['is_contact'] == true) {
                if (method != PaymentMethod.cash) {
                  throw UnsupportedError(
                    'Contact settlements must be recorded as cash.',
                  );
                }
                final result = await SupabaseTabbyRepository.instance
                    .recordContactCash(
                      operationId: op['operation_id'] as String,
                      tabId: realTabId,
                      payer: PartyRef(
                        kind: isPayingMe ? PartyKind.contact : PartyKind.user,
                        id: isPayingMe ? resolvedCounterpartId : userId,
                      ),
                      recipient: PartyRef(
                        kind: isPayingMe ? PartyKind.user : PartyKind.contact,
                        id: isPayingMe ? userId : resolvedCounterpartId,
                      ),
                      amountCentavos: amountCentavos,
                      note: note,
                    );
                await _finishContactProof(op, result, userId, session);
                await _commitMoneyResult(
                  op,
                  result,
                  realTabId,
                  userId,
                  session,
                );
                continue;
              }
              final result = await SupabaseTabbyRepository.instance
                  .submitPayment(
                    proofPath: uploadedProof,
                    paymentReference: paymentReference,
                    tabId: realTabId,
                    amountCentavos: amountCentavos,
                    method: method,
                    submittedByUserId: effectivePaidBy,
                    recipientUserId: effectiveReceivedBy,
                    operationId: op['operation_id'] as String,
                    note: note,
                  );
              if (result == null) {
                throw StateError('Pending payment sync was not accepted.');
              }
              await _commitMoneyResult(op, result, realTabId, userId, session);
            } else {
              throw StateError('Unable to resolve pending payment tab.');
            }
          } else {
            throw StateError('Unsupported pending operation type: $type');
          }
        } catch (e) {
          if (!SupabaseConfig.isCurrentSession(session)) return;
          debugPrint('[TabbyNotifier] Failed to sync pending op: $e');
          final operationId = op['operation_id'] as String?;
          if (operationId != null) {
            await TabbyLocalCache.recordPendingFailure(
              operationId,
              userId: userId,
              now: DateTime.now(),
              permanent:
                  e is UnsupportedError ||
                  e is ArgumentError ||
                  (e is PostgrestException &&
                      (e.code == '22023' ||
                          e.code == '42501' ||
                          e.code?.startsWith('23') == true)) ||
                  (op['type'] != 'add_expense' &&
                      op['type'] != 'append_payment_proof' &&
                      op['type'] != 'append_receipt' &&
                      op['type'] != 'settle_payment' &&
                      op['type'] != 'm2_command'),
            );
          }
        }
      }
      // Refresh from server once all pending ops have been attempted.
      if (refreshAfter && mounted && SupabaseConfig.currentUserId == userId) {
        await _loadTabs(replayPending: false);
      }
    } finally {
      _syncInFlight = false;
      if (_syncRequested) {
        _syncRequested = false;
        if (mounted && SupabaseConfig.currentUserId != null) {
          unawaited(_syncPendingOps());
        }
      }
    }
  }

  @override
  void dispose() {
    _emotionTimer?.cancel();
    _authSub?.cancel();
    _connectivitySub?.cancel();
    _stopRealtimeSubscription();
    super.dispose();
  }
}

/// Current user profile state notifier
class CurrentUserNotifier extends StateNotifier<TabbyUser> {
  CurrentUserNotifier({
    TabbyUser? initialUser,
    this.saveProfile,
    bool Function() Function()? captureCurrent,
    bool autoLoad = true,
  }) : captureCurrent =
           captureCurrent ??
           (() {
             final stamp = SupabaseConfig.captureSession();
             return () => SupabaseConfig.isCurrentSession(stamp);
           }),
       super(initialUser ?? _resolveInitialUser()) {
    if (!autoLoad) return;
    loadFromSupabase();
    if (SupabaseConfig.isInitialized && SupabaseConfig.currentUserId != null) {
      _startRealtimeSubscription();
    }
    if (SupabaseConfig.isInitialized) {
      _authSub = SupabaseConfig.auth.onAuthStateChange.listen((data) {
        if (data.session != null && mounted) {
          if (data.event == AuthChangeEvent.signedIn) {
            _stopRealtimeSubscription();
            state = _resolveInitialUser();
          }
          _startRealtimeSubscription();
          loadFromSupabase();
        } else if (data.session == null && mounted) {
          _stopRealtimeSubscription();
          reset();
        }
      }, onError: (Object _, StackTrace __) {});
    }
  }

  StreamSubscription<AuthState>? _authSub;
  RealtimeChannel? _userRealtimeChannel;

  void _startRealtimeSubscription() {
    if (!SupabaseConfig.isInitialized) return;
    final userId = SupabaseConfig.currentUserId;
    if (userId == null) return;
    if (_userRealtimeChannel != null) return;

    try {
      final channel = SupabaseConfig.client.channel(
        'public:user_realtime_$userId',
      );
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: SupabaseConfig.tableUsers,
        callback: (payload) {
          debugPrint('[CurrentUserNotifier] Realtime user update received');
          if (mounted) {
            loadFromSupabase();
          }
        },
      );
      channel.subscribe();
      _userRealtimeChannel = channel;
    } catch (e) {
      debugPrint(
        '[CurrentUserNotifier] Failed to start user Realtime subscription: $e',
      );
    }
  }

  void _stopRealtimeSubscription() {
    if (_userRealtimeChannel != null && SupabaseConfig.isInitialized) {
      try {
        SupabaseConfig.client.removeChannel(_userRealtimeChannel!);
      } catch (_) {}
      _userRealtimeChannel = null;
    }
  }

  static const TabbyUser unauthenticatedUser = TabbyUser(
    id: '',
    displayName: '',
    email: '',
    phone: '',
  );

  static TabbyUser _resolveInitialUser() {
    if (SupabaseConfig.isInitialized) {
      if (SupabaseConfig.currentUser != null) {
        final user = SupabaseConfig.currentUser!;
        final meta = user.userMetadata ?? {};
        return TabbyUser(
          id: user.id,
          displayName:
              meta['display_name'] as String? ??
              (user.email?.split('@').first ?? 'User'),
          email: user.email ?? '',
          phone: (meta['phone'] ?? user.phone) as String? ?? '',
          avatarUrl: meta['avatar_url'] as String?,
          friendCode: meta['friend_code'] as String?,
        );
      }
      return unauthenticatedUser;
    }
    return MockTabbyRepository.currentUser;
  }

  Future<void> loadFromSupabase() async {
    if (!SupabaseConfig.isInitialized) return;
    final session = SupabaseConfig.captureSession();
    final authUser = SupabaseConfig.currentUser;
    if (authUser == null) return;
    final revision = _profileRevision;

    final profile = await SupabaseTabbyRepository.instance.fetchUserProfile(
      authUser.id,
    );
    if (!mounted || !SupabaseConfig.isCurrentSession(session)) return;
    if (revision != _profileRevision || _savingProfile) return;
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

      state = profile.copyWith(
        displayName: displayName,
        phone: phone,
        email: SupabaseConfig.currentUser?.email ?? '',
      );
    }
  }

  final Future<ProfileUpdateResult> Function(Map<String, String> changes)?
  saveProfile;
  final bool Function() Function() captureCurrent;
  bool _savingProfile = false;
  int _profileRevision = 0;

  Future<ProfileUpdateResult> updateProfile({
    String? displayName,
    String? phone,
    String? avatarUrl,
  }) async {
    if (_savingProfile) {
      return const ProfileUpdateResult(
        isSuccess: false,
        errorMessage: 'A profile save is already in progress.',
      );
    }
    final normalized = phone == null ? null : normalizePhilippineMobile(phone);
    if (phone != null && normalized == null) {
      return const ProfileUpdateResult(
        isSuccess: false,
        errorMessage: 'Enter a valid Philippine mobile number.',
      );
    }
    final name = displayName?.trim();
    if (name != null && (name.isEmpty || name.length > 80)) {
      return const ProfileUpdateResult(
        isSuccess: false,
        errorMessage: 'Use a display name between 1 and 80 characters.',
      );
    }
    final actor = state.id, current = captureCurrent();
    final changes = <String, String>{
      if (name != null) 'display_name': name,
      if (normalized != null) 'phone': normalized,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
    };
    _savingProfile = true;
    _profileRevision++;
    try {
      final result = saveProfile != null
          ? await saveProfile!(changes)
          : !SupabaseConfig.isInitialized
          ? ProfileUpdateResult.success
          : await SupabaseTabbyRepository.instance.updateUserProfile(
              userId: actor,
              displayName: name,
              phone: normalized,
              avatarUrl: avatarUrl,
            );
      if (!mounted || state.id != actor || !current()) {
        return ProfileUpdateResult.failure;
      }
      if (!result.isSuccess) return result;
      if (result.user != null && result.user!.id != actor) {
        return ProfileUpdateResult.failure;
      }
      _profileRevision++;
      state =
          result.user ??
          state.copyWith(
            displayName: name,
            phone: normalized,
            avatarUrl: avatarUrl,
          );
      return result;
    } catch (_) {
      return const ProfileUpdateResult(
        isSuccess: false,
        errorMessage: 'Profile could not be saved. Your edits are still here. Please retry.',
      );
    } finally {
      _savingProfile = false;
    }
  }

  Future<ProfileUpdateResult> completeProfile({
    required String displayName,
    required String phone,
    String? avatarUrl,
  }) => updateProfile(
    displayName: displayName,
    phone: phone,
    avatarUrl: avatarUrl,
  );

  void reset() {
    _stopRealtimeSubscription();
    state = SupabaseConfig.isInitialized
        ? unauthenticatedUser
        : MockTabbyRepository.currentUser;
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _stopRealtimeSubscription();
    super.dispose();
  }
}

/// Global provider for Current User profile
final currentUserProvider =
    StateNotifierProvider<CurrentUserNotifier, TabbyUser>((ref) {
      return CurrentUserNotifier();
    });

/// Global provider for Tabby Dashboard state & operations
final tabbyProvider = StateNotifierProvider<TabbyNotifier, TabbyDashboardState>(
  (ref) {
    return TabbyNotifier();
  },
);

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
    final tab = tabs.firstWhere(
      (t) => t.id == tabId || t.counterpart.id == tabId,
    );
    final cleanEntries = TabbyNotifier.deduplicateLedgerEntries(tab.entries);
    return tab.copyWith(entries: cleanEntries, itemCount: cleanEntries.length);
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
  final bool appearanceBusy;
  final String? appearanceError;
  final bool isLoaded;
  final String? loadError;
  final bool biometricsEnabled;
  final bool passcodeEnabled;
  final bool autoLockEnabled;
  final String? notificationError;
  final bool notificationPermissionGranted;
  final bool notificationsEnabled;
  final bool paymentAlertsEnabled;
  final bool reminderNudgesEnabled;
  final String currencyCode;
  final String languageCode;
  final bool motionEnabled;
  final bool darkModeEnabled;

  const UserSettings({
    this.appearanceBusy = false,
    this.appearanceError,
    this.isLoaded = true,
    this.loadError,
    this.biometricsEnabled = false,
    this.passcodeEnabled = false,
    this.autoLockEnabled = true,
    this.notificationError,
    this.notificationPermissionGranted = false,
    this.notificationsEnabled = false,
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
    bool? appearanceBusy,
    String? appearanceError,
    bool clearAppearanceError = false,
    bool? isLoaded,
    String? loadError,
    bool? biometricsEnabled,
    bool? passcodeEnabled,
    bool? autoLockEnabled,
    String? notificationError,
    bool? notificationPermissionGranted,
    bool? notificationsEnabled,
    bool? paymentAlertsEnabled,
    bool? reminderNudgesEnabled,
    String? currencyCode,
    String? languageCode,
    bool? motionEnabled,
    bool? darkModeEnabled,
  }) {
    return UserSettings(
      appearanceBusy: appearanceBusy ?? this.appearanceBusy,
      appearanceError: clearAppearanceError
          ? null
          : appearanceError ?? this.appearanceError,
      isLoaded: isLoaded ?? this.isLoaded,
      loadError: loadError,
      biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
      passcodeEnabled: passcodeEnabled ?? this.passcodeEnabled,
      autoLockEnabled: autoLockEnabled ?? this.autoLockEnabled,
      notificationError: notificationError,
      notificationPermissionGranted:
          notificationPermissionGranted ?? this.notificationPermissionGranted,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      paymentAlertsEnabled: paymentAlertsEnabled ?? this.paymentAlertsEnabled,
      reminderNudgesEnabled:
          reminderNudgesEnabled ?? this.reminderNudgesEnabled,
      currencyCode: 'PHP',
      languageCode: 'en',
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
    FlutterSecureStorage? storage,
    Future<bool> Function()? notificationPermission,
    this._notificationsChanged,
  }) : _auth = auth ?? LocalDeviceAuthService(),
       _storage = storage ?? const FlutterSecureStorage(),
       _pinProtection = pinProtection ?? PinProtectionService(),
       _userId = userId ?? 'offline',
       _notificationPermission =
           notificationPermission ??
           TabbyNotificationService.instance.requestPermission,
       super(const UserSettings(isLoaded: false)) {
    ready = _loadPersistedSettings();
  }

  final FlutterSecureStorage _storage;
  final DeviceAuthService _auth;
  final PinProtectionService _pinProtection;
  final String _userId;
  final Future<bool> Function() _notificationPermission;
  final Future<bool> Function()? _notificationsChanged;
  late final _notificationPreferences = NotificationPreferencesStore(
    storage: _storage,
  );
  Future<void>? _notificationWork;
  Future<void>? _appearanceWork;
  late final _appearance = AppearancePreferencesStore(storage: _storage);

  late Future<void> ready;
  int _settingsRevision = 0;
  String get scopeId => _userId;
  Future<void> reloadSecuritySettings() async {
    _settingsRevision++;
    state = state.copyWith(isLoaded: false);
    ready = _loadPersistedSettings();
    await ready;
  }

  String _key(String name) => 'tabby_${_userId}_$name';

  Future<String?> _read(String name) async {
    final scoped = await _storage.read(key: _key(name));
    if (scoped != null ||
        {
          'biometrics_enabled',
          'passcode_enabled',
          'auto_lock_enabled',
        }.contains(name)) {
      return scoped;
    }
    return _storage.read(key: 'tabby_$name');
  }

  Future<void> _loadPersistedSettings() async {
    final revision = _settingsRevision;
    try {
      final bioStr = await _read('biometrics_enabled');
      final passStr = await _read('passcode_enabled');
      final lockStr = await _read('auto_lock_enabled');
      NotificationPreferences notifications;
      String? notificationError;
      try {
        notifications = await _notificationPreferences.load(_userId);
      } catch (_) {
        notifications = const NotificationPreferences();
        notificationError =
            'Notification settings could not be read. Please try again.';
      }
      var appearance = const AppearancePreferences();
      String? appearanceError;
      try {
        appearance = await _appearance.load(_userId);
      } catch (_) {
        appearanceError = 'Appearance settings could not be read. Choose your preferences to save them again.';
      }

      if (!mounted || revision != _settingsRevision) return;
      final hasPin = await _pinProtection.hasPin(_userId);
      if (!mounted || revision != _settingsRevision) return;
      state = UserSettings(
        isLoaded: true,
        biometricsEnabled: bioStr == 'true',
        passcodeEnabled: passStr == 'true' || hasPin,
        autoLockEnabled: lockStr != null ? lockStr == 'true' : true,
        notificationsEnabled: notifications.enabled,
        paymentAlertsEnabled: notifications.payments,
        reminderNudgesEnabled: notifications.reminders,
        notificationError: notificationError,
        currencyCode: 'PHP',
        languageCode: 'en',
        motionEnabled: appearance.motion,
        darkModeEnabled: appearance.dark,
        appearanceError: appearanceError,
      );
      await _applyNotificationPreferences();
    } catch (e) {
      debugPrint(
        '[UserSettingsNotifier] Security settings read failed (${e.runtimeType}).',
      );
      if (mounted && revision == _settingsRevision) {
        state = state.copyWith(
          isLoaded: false,
          loadError: 'Security settings could not be read. Please try again.',
        );
      }
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
    final session = SupabaseConfig.captureSession();
    try {
      if (await _pinProtection.hasPin(_userId)) {
        if (!await _auth.authenticate(
          reason: 'Authenticate to change your Tabby PIN',
        )) {
          return false;
        }
      }
      if (!mounted || !SupabaseConfig.isCurrentSession(session)) return false;
      await _pinProtection.setPin(_userId, pin);
      if (!mounted || !SupabaseConfig.isCurrentSession(session)) return false;
      await update(passcodeEnabled: true);
      return true;
    } catch (error) {
      debugPrint('[UserSettingsNotifier] Error setting PIN: $error');
      return false;
    }
  }

  Future<bool> verifyPin(String pin) => _pinProtection.verifyPin(_userId, pin);

  /// Recovery changes only the local app PIN, after fresh platform identity
  /// verification (biometric or device credential), never a cached unlock.
  Future<bool> clearPin() async {
    final session = SupabaseConfig.captureSession();
    try {
      if (!await _auth.authenticate(
        reason: 'Authenticate to reset your Tabby PIN',
      )) {
        return false;
      }
      if (!mounted || !SupabaseConfig.isCurrentSession(session)) return false;
      await _pinProtection.clearPin(_userId);
      if (!mounted || !SupabaseConfig.isCurrentSession(session)) return false;
      await update(passcodeEnabled: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _applyNotificationPreferences({bool? permitted}) async {
    try {
      final granted = _notificationsChanged == null
          ? (permitted ?? false)
          : await _notificationsChanged();
      if (!mounted) return;
      state = state.copyWith(
        notificationPermissionGranted: granted,
        notificationError:
            state.notificationError ??
            (state.notificationsEnabled && !granted
                ? 'Notifications are blocked in device settings.'
                : null),
      );
    } catch (_) {
      if (mounted) {
        state = state.copyWith(
          notificationError:
              'Device alerts could not be updated. Please try again.',
        );
      }
    }
  }

  Future<bool> toggleNotifications(bool enable) =>
      setNotificationPreferences(enabled: enable);

  Future<bool> setNotificationPreferences({
    bool? enabled,
    bool? payments,
    bool? reminders,
  }) {
    final session = SupabaseConfig.captureSession();
    final prior = _notificationWork;
    late final Future<void> guard;
    Future<bool> execute() async {
      try {
        await Future<void>.value();
        if (prior != null) await prior;
        await ready;
        if (!mounted || !SupabaseConfig.isCurrentSession(session)) return false;
        ++_settingsRevision;
        var permitted = state.notificationPermissionGranted;
        if (enabled == true) {
          permitted = await _notificationPermission();
          if (!mounted || !SupabaseConfig.isCurrentSession(session)) {
            return false;
          }
          if (!permitted) {
            state = state.copyWith(
              notificationPermissionGranted: false,
              notificationError: 'Notifications are not allowed. You can enable them in device settings.',
            );
            return false;
          }
        }
        final preferences = NotificationPreferences(
          enabled: enabled ?? state.notificationsEnabled,
          payments: payments ?? state.paymentAlertsEnabled,
          reminders: reminders ?? state.reminderNudgesEnabled,
        );
        await _notificationPreferences.save(_userId, preferences);
        if (!mounted || !SupabaseConfig.isCurrentSession(session)) return false;
        state = state.copyWith(
          notificationsEnabled: preferences.enabled,
          paymentAlertsEnabled: preferences.payments,
          reminderNudgesEnabled: preferences.reminders,
          notificationPermissionGranted: permitted,
        );
        await _applyNotificationPreferences(permitted: permitted);
        return mounted &&
            SupabaseConfig.isCurrentSession(session) &&
            state.notificationError == null;
      } catch (_) {
        if (mounted && SupabaseConfig.isCurrentSession(session)) {
          state = state.copyWith(
            notificationError:
                'Notification settings could not be saved. Please try again.',
          );
        }
        return false;
      } finally {
        if (identical(_notificationWork, guard)) _notificationWork = null;
      }
    }

    final task = execute();
    guard = task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _notificationWork = guard;
    return task;
  }

  Future<bool> setAppearancePreferences({bool? motion, bool? dark}) {
    final session = SupabaseConfig.captureSession();
    final previous = _appearanceWork;
    bool active() =>
        mounted &&
        SupabaseConfig.isCurrentSession(session) &&
        (!SupabaseConfig.isInitialized ||
            SupabaseConfig.currentUserId == _userId);
    Future<bool> execute() async {
      await Future<void>.value();
      if (previous != null) await previous;
      await ready;
      if (!active() || !state.isLoaded) return false;
      final next = AppearancePreferences(
        motion: motion ?? state.motionEnabled,
        dark: dark ?? state.darkModeEnabled,
      );
      state = state.copyWith(appearanceBusy: true, clearAppearanceError: true);
      try {
        await _appearance.save(_userId, next);
        if (!active()) return false;
        state = state.copyWith(
          motionEnabled: next.motion,
          darkModeEnabled: next.dark,
          appearanceBusy: false,
        );
        return true;
      } catch (_) {
        if (active()) {
          state = state.copyWith(
            appearanceBusy: false,
            appearanceError: 'Appearance could not be saved. Your previous settings are kept. Retry.',
          );
        }
        return false;
      }
    }

    final result = execute();
    late final Future<void> barrier;
    barrier = result
        .then<void>((_) {}, onError: (Object _, StackTrace stack) {})
        .whenComplete(() {
          if (identical(_appearanceWork, barrier)) _appearanceWork = null;
        });
    _appearanceWork = barrier;
    return result;
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
    if ((currencyCode != null && currencyCode != 'PHP') ||
        (languageCode != null && languageCode != 'en')) {
      throw ArgumentError('M1 supports PHP and English only.');
    }
    if (motionEnabled != null || darkModeEnabled != null) {
      final saved = await setAppearancePreferences(
        motion: motionEnabled,
        dark: darkModeEnabled,
      );
      if (!saved) return;
    }
    if (biometricsEnabled == null &&
        passcodeEnabled == null &&
        autoLockEnabled == null &&
        notificationsEnabled == null &&
        paymentAlertsEnabled == null &&
        reminderNudgesEnabled == null) {
      return;
    }

    if (notificationsEnabled != null ||
        paymentAlertsEnabled != null ||
        reminderNudgesEnabled != null) {
      await setNotificationPreferences(
        enabled: notificationsEnabled,
        payments: paymentAlertsEnabled,
        reminders: reminderNudgesEnabled,
      );
    }
    _settingsRevision++;
    state = state.copyWith(
      isLoaded: true,
      notificationError: state.notificationError,
      biometricsEnabled: biometricsEnabled,
      passcodeEnabled: passcodeEnabled,
      autoLockEnabled: autoLockEnabled,
      currencyCode: currencyCode,
      languageCode: languageCode,
    );

    try {
      final values = <String, String?>{
        'biometrics_enabled': biometricsEnabled?.toString(),
        'passcode_enabled': passcodeEnabled?.toString(),
        'auto_lock_enabled': autoLockEnabled?.toString(),
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
      final userId = ref.watch(currentUserProvider.select((user) => user.id));
      void authChanged() => ref.invalidateSelf();
      SupabaseConfig.sessionRevision.addListener(authChanged);
      ref.onDispose(
        () => SupabaseConfig.sessionRevision.removeListener(authChanged),
      );
      final scope = SupabaseConfig.isInitialized
          ? SupabaseConfig.currentUserId ?? 'unauthenticated'
          : userId;
      return UserSettingsNotifier(
        userId: scope,
        notificationsChanged: () async {
          final service = TabbyNotificationService.instance;
          await service.setActiveAccount(
            SupabaseConfig.isInitialized ? SupabaseConfig.currentUserId : scope,
          );
          await service.preferencesChanged(scope);
          await ref.read(tabbyProvider.notifier).refreshDueReminders();
          return service.permissionGranted();
        },
      );
    });
