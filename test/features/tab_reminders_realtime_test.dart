import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  });
}
