import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tabby/core/services/form_draft_store.dart';
import 'package:tabby/core/services/notification_preferences.dart';
import 'package:tabby/core/services/pin_protection_service.dart';
import 'package:tabby/core/services/tabby_notification_service.dart';

const coldLaunchCase =
    'native notification cold launch retains payload encrypted draft and PIN';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('TABBY_USB_TEST')) {
    throw StateError('Cold-launch fixtures require the isolated test package.');
  }
  testWidgets(coldLaunchCase, (tester) async {
    const account = 'native-cold-launch-owner';
    const tab = '00000000-0000-4000-8000-000000000016';
    const drafts = FormDraftStore();
    final service = TabbyNotificationService.instance;
    final launched = await tester.runAsync(() async {
      await service.initialize();
      final plugin = FlutterLocalNotificationsPlugin();
      final details = await plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp == true) {
        final payload =
            jsonDecode(details!.notificationResponse!.payload!) as Map;
        expect(payload['v'], 1);
        expect(payload['account'], account);
        expect(payload['route'], 'tab:$tab');
        expect(await drafts.read(account, 'cold-notification'), {
          'amountCentavos': 101,
          'operation': 'native-cold-operation',
        });
        expect(await PinProtectionService().verifyPin(account, '7391'), isTrue);
        await service.cancelAll();
        debugPrint(
          'NATIVE_COLD launchedFromNotification=true payloadValid=true encryptedDraft=true persistedPin=true',
        );
        return true;
      }
      await drafts.write(account, 'cold-notification', {
        'amountCentavos': 101,
        'operation': 'native-cold-operation',
      });
      await PinProtectionService().setPin(account, '7391');
      await const NotificationPreferencesStore().save(
        account,
        const NotificationPreferences(enabled: true),
      );
      await service.setActiveAccount(account);
      expect(await service.permissionGranted(), isTrue);
      final due = DateTime.now().add(const Duration(seconds: 45));
      await service.scheduleDueReminder(
        reminderId: 'cold-launch-${due.millisecondsSinceEpoch}',
        friendName: 'Cold launch fixture',
        description: 'Synthetic cold-launch acceptance',
        formattedAmount: 'PHP 1.01',
        dueDate: due,
        iOweThem: false,
        tabId: tab,
      );
      expect(
        (await plugin.pendingNotificationRequests()).any(
          (r) => r.body?.contains('Synthetic cold-launch acceptance') == true,
        ),
        isTrue,
      );
      debugPrint(
        'NATIVE_COLD seed=true dueEpoch=${due.millisecondsSinceEpoch}',
      );
      return false;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Text(
            launched == true
                ? 'Synthetic cold launch verified'
                : 'Synthetic alarm seeded',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
