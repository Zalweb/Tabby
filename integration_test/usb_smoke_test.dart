import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tabby/core/services/form_draft_store.dart';
import 'package:tabby/core/services/notification_preferences.dart';
import 'package:tabby/core/services/pin_protection_service.dart';
import 'package:tabby/core/services/reminder_notification_id.dart';
import 'package:tabby/core/services/tabby_notification_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    expect(const bool.fromEnvironment('TABBY_USB_TEST'), isTrue);
  });
  testWidgets(
    'encrypted draft survives actual process restart and isolates owner',
    (tester) async {
      const store = FormDraftStore();
      expect(await store.read('usb-smoke', 'payment:fixture'), {
        'amount': '12.34',
        'operation': 'usb-smoke-stable-operation',
      });
      expect(await store.read('usb-other-owner', 'payment:fixture'), isNull);
    },
  );
  testWidgets('native stored PIN survives restart and rejects a wrong PIN', (
    tester,
  ) async {
    final pin = PinProtectionService();
    expect(await pin.hasPin('usb-smoke'), isTrue);
    expect(await pin.verifyPin('usb-smoke', '0000'), isFalse);
    expect(await pin.verifyPin('usb-smoke', '7391'), isTrue);
  });
  testWidgets('Android permission and preference changes gate pending alarms', (
    tester,
  ) async {
    const account = 'usb-notifications';
    const reminder = 'usb-smoke-pending';
    final service = TabbyNotificationService.instance;
    await service.initialize();
    await service.setActiveAccount(account);
    expect(await service.permissionGranted(), isTrue);
    const prefs = NotificationPreferencesStore();
    await prefs.save(account, const NotificationPreferences(enabled: true));
    await service.preferencesChanged(account);
    await service.scheduleDueReminder(
      reminderId: reminder,
      friendName: 'Synthetic friend',
      description: 'USB smoke scheduling fixture',
      formattedAmount: 'PHP 1.01',
      dueDate: DateTime.now().add(const Duration(hours: 1)),
      iOweThem: true,
      tabId: 'usb-synthetic-tab',
    );
    final plugin = FlutterLocalNotificationsPlugin();
    final id = reminderNotificationId('due:$reminder');
    expect(
      (await plugin.pendingNotificationRequests()).any((r) => r.id == id),
      isTrue,
    );
    await prefs.save(account, const NotificationPreferences(enabled: false));
    await service.preferencesChanged(account);
    expect(
      (await plugin.pendingNotificationRequests()).any((r) => r.id == id),
      isFalse,
    );
  });
  testWidgets('tablet renders and accepts touch input', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => pressed = true,
              child: const Text('USB tablet check'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('USB tablet check'));
    await tester.pump();
    expect(pressed, isTrue);
    expect(tester.takeException(), isNull);
  });
}
