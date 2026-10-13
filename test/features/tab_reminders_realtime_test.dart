import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tabby/core/config/supabase_config.dart';
import 'package:tabby/core/services/tabby_notification_service.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/application/tabby_state.dart';
import 'package:tabby/features/tabs/data/mock_tabby_repository.dart';
import 'package:tabby/features/tabs/domain/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Realtime Tab Reminders & Debtor Notifications', () {
    test('TabbyNotificationService initializes and defines showTabReminderAlert', () async {
      final service = TabbyNotificationService.instance;
      expect(service, isNotNull);
      // Verify calling showTabReminderAlert without initialization does not throw
      await expectLater(
        service.showTabReminderAlert(
          title: 'Juan sent you a friendly reminder',
          body: 'You have a pending balance of ₱500.00. Tap to settle up.',
          tabId: 'test-tab-123',
        ),
        completes,
      );
    });

    test('AppNotification models tab_reminder notification type properly', () {
      final notif = AppNotification(
        id: 'notif-reminder-1',
        recipientUserId: 'user-debtor-1',
        type: 'tab_reminder',
        relatedTabId: 'tab-101',
        title: 'Friendly reminder from Maria',
        body: 'You have a pending balance of ₱250.00 for Lunch. Tap to settle up.',
        isRead: false,
        createdAt: DateTime.now(),
      );

      expect(notif.type, 'tab_reminder');
      expect(notif.recipientUserId, 'user-debtor-1');
      expect(notif.relatedTabId, 'tab-101');
      expect(notif.isRead, isFalse);
    });

    test('UpcomingReminder correctly distinguishes whether user owes or is owed', () {
      final iOwe = UpcomingReminder(
        id: 'rem-1',
        tabId: 'tab-1',
        friendName: 'Juan',
        description: 'Dinner',
        amountCentavos: 35000,
        dueDate: DateTime.now().add(const Duration(days: 2)),
        isIWhoOwe: true,
      );

      final theyOwe = UpcomingReminder(
        id: 'rem-2',
        tabId: 'tab-2',
        friendName: 'Maria',
        description: 'Groceries',
        amountCentavos: 50000,
        dueDate: DateTime.now().add(const Duration(days: 1)),
        isIWhoOwe: false,
      );

      expect(iOwe.isIWhoOwe, isTrue);
      expect(theyOwe.isIWhoOwe, isFalse);
    });

    test('TabbyNotifier sendGentleNudge logs activity and sets mascot emotion', () async {
      final notifier = TabbyNotifier(loadInitialData: false);
      addTearDown(notifier.dispose);
      notifier.state = TabbyDashboardState(
        tabs: MockTabbyRepository.getInitialTabs(),
        activities: MockTabbyRepository.getInitialActivities(),
        reminders: MockTabbyRepository.getInitialReminders(),
      );

      await notifier.sendGentleNudge(
        tabId: 'tab-juan',
        friendName: 'Juan',
        amountCentavos: 50000,
        description: 'Dinner',
      );

      expect(notifier.state.emotionOverride, MascotEmotion.gentleNudge);
      expect(
        notifier.state.activities.first.description,
        contains('sent friendly reminder to Juan'),
      );
      expect(notifier.state.activities.first.amountCentavos, 50000);
      expect(notifier.state.activities.first.iconData, Icons.send_rounded);
    });

    test('TabbyNotifier settleTab cancels and filters resolved reminders', () async {
      final notifier = TabbyNotifier(loadInitialData: false);
      addTearDown(notifier.dispose);

      await notifier.addExpense(
        counterpartId: 'friend-juan',
        counterpartName: 'Juan',
        title: 'Lunch',
        totalAmountCentavos: 50000,
        category: ExpenseCategory.food,
        paidByMe: true,
        isEqualSplit: false,
      );

      final testTab = notifier.state.tabs.first;

      notifier.state = notifier.state.copyWith(
        reminders: [
          UpcomingReminder(
            id: 'rem-settle-test',
            tabId: testTab.id,
            friendName: testTab.counterpart.displayName,
            description: 'Lunch',
            amountCentavos: testTab.netBalanceCentavos.abs(),
            dueDate: DateTime.now().add(const Duration(days: 3)),
            isIWhoOwe: false,
          ),
        ],
      );

      expect(notifier.state.reminders.length, 1);

      // Settle the tab completely
      await notifier.settleTab(
        tabId: testTab.id,
        amountCentavos: testTab.netBalanceCentavos.abs(),
        method: PaymentMethod.gcash,
        isPayingMe: true,
      );

      // Reminder for this settled tab should be removed
      expect(
        notifier.state.reminders.where((r) => r.tabId == testTab.id).isEmpty,
        isTrue,
      );
      expect(notifier.state.emotionOverride, MascotEmotion.celebrating);
    });

    test('Realtime notification payload on notifications table inserts tab_reminder into debtor state', () async {
      FlutterSecureStorage.setMockInitialValues({});
      const debtorId = 'user-debtor-test-456';
      SupabaseConfig.debugUserIdOverride = debtorId;
      addTearDown(() => SupabaseConfig.debugUserIdOverride = null);

      final notifier = TabbyNotifier(loadInitialData: false);
      addTearDown(notifier.dispose);
      notifier.state = TabbyDashboardState(
        tabs: MockTabbyRepository.getInitialTabs(),
        activities: MockTabbyRepository.getInitialActivities(),
        reminders: MockTabbyRepository.getInitialReminders(),
      );

      expect(notifier.state.notifications.isEmpty, isTrue);

      final payload = PostgresChangePayload(
        eventType: PostgresChangeEvent.insert,
        newRecord: {
          'id': 'notif-realtime-reminder-1',
          'recipient_user_id': debtorId,
          'notification_type': 'tab_reminder',
          'title': 'Mateo sent you a friendly reminder',
          'body': 'You have a pending balance of ₱500.00 for Dinner. Tap to settle up.',
          'related_tab_id': 'tab-123',
          'created_at': DateTime.now().toIso8601String(),
        },
        oldRecord: {},
        schema: 'public',
        table: 'notifications',
        commitTimestamp: DateTime.now(),
        errors: [],
      );

      notifier.handleRealtimePayloadForTesting(payload);

      expect(notifier.state.notifications.length, 1);
      final receivedNotif = notifier.state.notifications.first;
      expect(receivedNotif.id, 'notif-realtime-reminder-1');
      expect(receivedNotif.type, 'tab_reminder');
      expect(receivedNotif.title, 'Mateo sent you a friendly reminder');
      expect(receivedNotif.body, contains('₱500.00'));
      expect(receivedNotif.relatedTabId, 'tab-123');
      expect(receivedNotif.isRead, isFalse);
      expect(notifier.state.unreadNotificationCount, 1);

      // Debtor marks notification as read
      await notifier.markNotificationAsRead('notif-realtime-reminder-1');
      expect(notifier.state.notifications.first.isRead, isTrue);
      expect(notifier.state.unreadNotificationCount, 0);
    });

    test('Realtime debtor notification from Postgres trigger handles expense_added payload', () async {
      FlutterSecureStorage.setMockInitialValues({});
      const debtorId = 'user-debtor-test-789';
      SupabaseConfig.debugUserIdOverride = debtorId;
      addTearDown(() => SupabaseConfig.debugUserIdOverride = null);

      final notifier = TabbyNotifier(loadInitialData: false);
      addTearDown(notifier.dispose);
      notifier.state = TabbyDashboardState(
        tabs: MockTabbyRepository.getInitialTabs(),
        activities: MockTabbyRepository.getInitialActivities(),
        reminders: MockTabbyRepository.getInitialReminders(),
      );

      final payload = PostgresChangePayload(
        eventType: PostgresChangeEvent.insert,
        newRecord: {
          'id': 'notif-expense-added-1',
          'recipient_user_id': debtorId,
          'notification_type': 'expense_added',
          'title': 'New Expense: Team Lunch',
          'body': 'Juan paid ₱1,000.00. Your share is ₱500.00.',
          'related_tab_id': 'tab-expense-789',
          'created_at': DateTime.now().toIso8601String(),
        },
        oldRecord: {},
        schema: 'public',
        table: 'notifications',
        commitTimestamp: DateTime.now(),
        errors: [],
      );

      notifier.handleRealtimePayloadForTesting(payload);

      expect(notifier.state.notifications.length, 1);
      final notif = notifier.state.notifications.first;
      expect(notif.type, 'expense_added');
      expect(notif.title, 'New Expense: Team Lunch');
      expect(notif.body, contains('Your share is ₱500.00'));
      expect(notif.isRead, isFalse);
    });
  });
}
