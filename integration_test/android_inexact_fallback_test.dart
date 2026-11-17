import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:tabby/core/services/notification_preferences.dart';
import 'package:tabby/core/services/tabby_notification_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android schedules inexact reminder when exact alarm access is denied',
    (tester) async {
      const account = 'emulator-acceptance-account';
      const prefs = NotificationPreferencesStore();
      await prefs.save(account, const NotificationPreferences(enabled: true));
      final service = TabbyNotificationService.instance;
      await service.initialize();
      await service.setActiveAccount(account);
      final android = FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final exact = await android?.canScheduleExactNotifications() ?? false;
      expect(
        exact,
        isFalse,
        reason: 'Exact alarm access is denied for this fallback run',
      );
      expect(await service.permissionGranted(), isTrue);
      final due = DateTime.now().add(const Duration(seconds: 70));
      await service.scheduleDueReminder(
        reminderId: 'emulator-inexact-fallback-20261104',
        friendName: 'Synthetic friend',
        description: 'Emulator inexact fallback',
        formattedAmount: 'PHP 1.01',
        dueDate: due,
        iOweThem: true,
        tabId: 'emulator-synthetic-tab',
      );
      debugPrint(
        'DEVICE_ACCEPTANCE_INEXACT exactAccess=false scheduled=true due=${due.toIso8601String()}',
      );
    },
  );
}
