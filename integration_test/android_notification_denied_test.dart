import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tabby/core/services/notification_preferences.dart';
import 'package:tabby/core/services/tabby_notification_service.dart';

// The runner revokes only this isolated package's runtime permission, and
// restores it in finally. Native preferences and notification ports stay real.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('TABBY_USB_TEST')) {
    throw StateError('Denied-permission tests require the isolated package.');
  }
  testWidgets(
    'native denied permission suppresses immediate and scheduled alerts',
    (tester) async {
      await tester.runAsync(() async {
        final service = TabbyNotificationService.instance;
        final plugin = FlutterLocalNotificationsPlugin();
        const account = 'native-denied-notification-account';
        await service.initialize();
        await const NotificationPreferencesStore().save(
          account,
          const NotificationPreferences(enabled: true),
        );
        await service.setActiveAccount(account);
        try {
          expect(await service.permissionGranted(), isFalse);
          await service.showTabReminderAlert(
            eventId: 'denied-immediate',
            title: 'Denied synthetic alert',
            body: 'This must not appear',
          );
          await service.scheduleDueReminder(
            reminderId: 'denied-scheduled',
            friendName: 'Synthetic friend',
            description: 'This must not be scheduled',
            formattedAmount: 'PHP 1.01',
            dueDate: DateTime.now().add(const Duration(seconds: 10)),
            iOweThem: true,
            tabId: 'synthetic-tab',
          );
          expect(await plugin.getActiveNotifications(), isEmpty);
          expect(await plugin.pendingNotificationRequests(), isEmpty);
          debugPrint(
            'NATIVE_DELIVERY permissionDenied=true immediateSuppressed=true scheduledSuppressed=true',
          );
        } finally {
          await service.cancelAll();
          await service.setActiveAccount(null);
        }
      });
    },
  );
}
