import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tabby/core/services/notification_preferences.dart';
import 'package:tabby/core/services/tabby_notification_service.dart';

// Native OS notifications and encrypted preferences, synthetic local accounts.
// The plugin queries this application's NotificationManager, not other apps.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('TABBY_USB_TEST')) {
    throw StateError('Notification acceptance requires the isolated package.');
  }
  final service = TabbyNotificationService.instance;
  final plugin = FlutterLocalNotificationsPlugin();
  const preferences = NotificationPreferencesStore();
  final account =
      'native-notification-${DateTime.now().microsecondsSinceEpoch}';

  Future<void> bind(String owner) async {
    await preferences.save(owner, const NotificationPreferences(enabled: true));
    await service.setActiveAccount(owner);
  }

  Future<List<ActiveNotification>> active() => plugin.getActiveNotifications();

  Future<void> waitFor(
    Future<bool> Function() condition, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final timer = Stopwatch()..start();
    while (!await condition()) {
      if (timer.elapsed >= timeout) {
        fail(
          'Native notification condition timed out after ${timeout.inSeconds}s',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  setUpAll(() async {
    await service.initialize();
    expect(await service.permissionGranted(), isTrue);
  });
  setUp(() => bind(account));
  tearDown(() async {
    await service.cancelAll();
    await service.setActiveAccount(null);
  });

  testWidgets(
    'native immediate alert is active and account switch removes it',
    (tester) async {
      await tester.runAsync(() async {
        await service.showTabReminderAlert(
          eventId: 'immediate-account',
          title: 'Synthetic local acceptance',
          body: 'Test notification only',
          tabId: 'synthetic-tab',
        );
        await waitFor(
          () async => (await active()).any(
            (n) => n.title == 'Synthetic local acceptance',
          ),
        );
        final posted = (await active()).singleWhere(
          (n) => n.title == 'Synthetic local acceptance',
        );
        expect(posted.channelId, 'tabby_reminders');
        expect(posted.body, 'Test notification only');
        await bind('$account-next');
        await waitFor(() async => (await active()).isEmpty);
        debugPrint('NATIVE_DELIVERY immediate=true accountSwitchRemoval=true');
      });
    },
  );

  testWidgets(
    'native preferences suppress disabled alerts and remove active ones',
    (tester) async {
      await tester.runAsync(() async {
        await service.showTabReminderAlert(
          eventId: 'preference-active',
          title: 'Synthetic preference acceptance',
          body: 'Test notification only',
        );
        await waitFor(() async => (await active()).isNotEmpty);
        await preferences.save(account, const NotificationPreferences());
        await service.preferencesChanged(account);
        await waitFor(() async => (await active()).isEmpty);
        await service.showTabReminderAlert(
          eventId: 'preference-disabled',
          title: 'Disabled synthetic notification',
          body: 'This must not appear',
        );
        expect(await active(), isEmpty);
        debugPrint(
          'NATIVE_DELIVERY disabledSuppressed=true activeRemoved=true',
        );
      });
    },
  );

  testWidgets(
    'native scheduled reminder becomes active and cancellation removes it',
    (tester) async {
      await tester.runAsync(() async {
        const reminder = 'physical-delivery-reminder';
        final android = plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        final exact = await android!.canScheduleExactNotifications();
        final due = DateTime.now().add(const Duration(seconds: 5));
        await service.scheduleDueReminder(
          reminderId: reminder,
          friendName: 'Synthetic friend',
          description: 'Synthetic scheduled acceptance',
          formattedAmount: 'PHP 1.01',
          dueDate: due,
          iOweThem: true,
          tabId: 'synthetic-tab',
        );
        final scheduled = (await plugin.pendingNotificationRequests())
            .singleWhere(
              (n) => n.body?.contains('Synthetic scheduled acceptance') == true,
            );
        final payload = jsonDecode(scheduled.payload!) as Map<String, dynamic>;
        expect(payload['account'], account);
        expect(payload['route'], 'tab:synthetic-tab');
        final watch = Stopwatch()..start();
        debugPrint('NATIVE_DELIVERY scheduled=true exactAllowed=$exact');
        await waitFor(
          () async => (await active()).any((n) => n.id == scheduled.id),
          timeout: const Duration(seconds: 150),
        );
        final delivered = (await active()).singleWhere(
          (n) => n.id == scheduled.id,
        );
        expect(delivered.title, 'Payment due today');
        expect(delivered.body, contains('Synthetic scheduled acceptance'));
        expect(delivered.channelId, 'tabby_reminders');
        expect(
          (await plugin.pendingNotificationRequests()).any(
            (n) => n.id == scheduled.id,
          ),
          isFalse,
        );
        await service.cancelReminder(reminder);
        await waitFor(
          () async => (await active()).every((n) => n.id != scheduled.id),
        );
        debugPrint(
          'NATIVE_DELIVERY scheduledDelivered=true elapsedMs=${watch.elapsedMilliseconds} cancelled=true',
        );
      });
    },
  );
}
