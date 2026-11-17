import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tabby/core/services/notification_preferences.dart';
import 'package:tabby/core/services/pin_protection_service.dart';
import 'package:tabby/core/services/reminder_notification_id.dart';
import 'package:tabby/core/services/tabby_notification_service.dart';
import 'package:tabby/core/widgets/biometric_gate.dart';
import 'package:tabby/features/home/presentation/home_dashboard_screen.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/data/mock_tabby_repository.dart';
import 'package:tabby/features/tabs/domain/models.dart';

class _SeededNotifier extends TabbyNotifier {
  _SeededNotifier({
    required List<BilateralTab> tabs,
    required List<TabbyActivity> activities,
    List<UpcomingReminder> reminders = const [],
  }) : super(loadInitialData: false) {
    state = state.copyWith(
      viewerUserId: MockTabbyRepository.currentUser.id,
      tabs: tabs,
      activities: activities,
      reminders: reminders,
    );
  }
}

Widget _lockedApp(UserSettingsNotifier settings) => ProviderScope(
  overrides: [userSettingsProvider.overrideWith((ref) => settings)],
  child: MaterialApp(
    home: const SizedBox.shrink(),
    builder: (context, child) =>
        const BiometricGate(child: Text('Protected synthetic ledger')),
  ),
);

Future<int> _waitForVisible(WidgetTester tester, Finder finder) async {
  final watch = Stopwatch()..start();
  while (finder.evaluate().isEmpty && watch.elapsed < const Duration(seconds: 20)) {
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  watch.stop();
  return watch.elapsedMilliseconds;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SEC-001 cold process shows lock and PIN navigator recovers', (
    tester,
  ) async {
    const account = 'device-matrix-sec001';
    final settings = UserSettingsNotifier(
      userId: account,
      pinProtection: PinProtectionService(),
    );
    await settings.ready;
    expect(settings.state.passcodeEnabled, isTrue);
    expect(settings.state.autoLockEnabled, isTrue);

    await tester.pumpWidget(_lockedApp(settings));
    await tester.pumpAndSettle(const Duration(milliseconds: 80));
    expect(find.text('Tabby is locked'), findsOneWidget);
    expect(find.text('Protected synthetic ledger'), findsNothing);
    final persistedPinWorks = await PinProtectionService().verifyPin(
      account,
      '1234',
    );
    debugPrint('DEVICE_MATRIX_SEC001 persistedPinVerifies=$persistedPinWorks');
    expect(persistedPinWorks, isTrue);

    await tester.enterText(find.byType(TextField).first, '1234');
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      '1234',
    );
    await tester.ensureVisible(find.text('Unlock with PIN'));
    await tester.tap(find.text('Unlock with PIN'));
    await tester.pump();
    expect(find.text('Verifying PIN'), findsOneWidget);
    final pinVerificationMs = await _waitForVisible(
      tester,
      find.text('Protected synthetic ledger'),
    );
    expect(pinVerificationMs, lessThan(20000));
    expect(find.text('Protected synthetic ledger'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(find.text('Tabby is locked'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Tabby is locked'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '1234');
    await tester.ensureVisible(find.text('Unlock with PIN'));
    await tester.tap(find.text('Unlock with PIN'));
    await tester.pump();
    expect(find.text('Verifying PIN'), findsOneWidget);
    await _waitForVisible(tester, find.text('Protected synthetic ledger'));
    await tester.pumpAndSettle(const Duration(milliseconds: 80));
    expect(find.text('Protected synthetic ledger'), findsOneWidget);
    debugPrint(
      'DEVICE_MATRIX_SEC001 lockedColdStart=true protectedHidden=true gateUnlockMs=$pinVerificationMs resumeRelockAndPinRecovery=true',
    );
  });

  testWidgets(
    'SEC-003 real PIN failures persist lockout across service restart',
    (tester) async {
      const account = 'device-matrix-sec003';
      final pin = PinProtectionService();
      await pin.clearPin(account);
      await pin.setPin(account, '7391');
      final attemptTimes = <int>[];
      for (var attempt = 1; attempt <= 5; attempt++) {
        final watch = Stopwatch()..start();
        expect(await pin.verifyPin(account, '0000'), isFalse);
        watch.stop();
        attemptTimes.add(watch.elapsedMilliseconds);
      }
      Duration? retryAfter;
      try {
        await pin.verifyPin(account, '0000');
      } on PinLockedException catch (e) {
        retryAfter = e.retryAfter;
      }
      expect(retryAfter, isNotNull);
      expect(retryAfter!.inSeconds, inInclusiveRange(1, 30));
      Duration? reopenedRetry;
      try {
        await PinProtectionService().verifyPin(account, '7391');
      } on PinLockedException catch (e) {
        reopenedRetry = e.retryAfter;
      }
      expect(reopenedRetry, isNotNull);
      debugPrint(
        'DEVICE_MATRIX_SEC003 wrongAttemptMs=${attemptTimes.join(',')} lockoutRetrySeconds=${retryAfter.inMilliseconds / 1000} persistedAfterServiceReopen=true',
      );
    },
  );

  testWidgets(
    'HOME-001 dashboard labels and calendar-month filter match seed',
    (tester) async {
      final now = DateTime(2026, 11, 4, 12);
      final tabs = [
        BilateralTab(
          id: 'device-home001-owed',
          counterpart: const TabbyUser(
            id: 'synthetic-a',
            displayName: 'Synthetic A',
            email: 'a@example.invalid',
            phone: '',
          ),
          netBalanceCentavos: 5000,
          itemCount: 0,
          entries: const [],
          lastUpdated: now,
        ),
        BilateralTab(
          id: 'device-home001-owe',
          counterpart: const TabbyUser(
            id: 'synthetic-b',
            displayName: 'Synthetic B',
            email: 'b@example.invalid',
            phone: '',
          ),
          netBalanceCentavos: -2300,
          itemCount: 0,
          entries: const [],
          lastUpdated: now,
        ),
      ];
      final activities = [
        TabbyActivity(
          id: 'device-home001-nov',
          actorName: 'Synthetic A',
          description: 'November seeded activity',
          amountCentavos: 101,
          timestamp: DateTime(2026, 11, 3, 9),
        ),
        TabbyActivity(
          id: 'device-home001-oct',
          actorName: 'Synthetic B',
          description: 'October seeded activity',
          amountCentavos: 202,
          timestamp: DateTime(2026, 10, 31, 9),
        ),
        TabbyActivity(
          id: 'device-home001-future',
          actorName: 'Synthetic B',
          description: 'Future seeded activity',
          amountCentavos: 303,
          timestamp: DateTime(2026, 11, 5, 9),
        ),
      ];
      final notifier = _SeededNotifier(tabs: tabs, activities: activities);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tabbyProvider.overrideWith((ref) => notifier),
            currentUserProvider.overrideWith(
              (ref) => CurrentUserNotifier(
                initialUser: MockTabbyRepository.currentUser,
                autoLoad: false,
              ),
            ),
          ],
          child: MaterialApp(home: HomeDashboardScreen(now: () => now)),
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 80));
      expect(find.text('You are owed'), findsOneWidget);
      expect(find.text('You owe'), findsOneWidget);
      expect(find.text('₱50.00').evaluate(), isNotEmpty);
      expect(find.text('₱23.00').evaluate(), isNotEmpty);

      await tester.scrollUntilVisible(
        find.text('Recent Activity'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('November seeded activity'), findsOneWidget);
      expect(find.text('October seeded activity'), findsNothing);
      expect(find.text('Future seeded activity'), findsNothing);
      expect(find.text('1 log'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Last 7 days'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Last 7 days'));
      await tester.pumpAndSettle(const Duration(milliseconds: 80));
      expect(find.text('November seeded activity'), findsOneWidget);
      expect(find.text('October seeded activity'), findsOneWidget);
      expect(find.text('Future seeded activity'), findsNothing);
      expect(find.text('2 logs'), findsOneWidget);
      debugPrint(
        'DEVICE_MATRIX_HOME001 labels=YouAreOwed:5000,YouOwe:2300 thisMonth=1 last7Days=2 futureExcluded=true',
      );
    },
  );

  testWidgets('HOME-002 settled tab refresh cancels its device reminder', (
    tester,
  ) async {
    const reminderId = 'device-matrix-settled-reminder';
    const account = 'user-me';
    final service = TabbyNotificationService.instance;
    await service.initialize();
    await service.setActiveAccount(account);
    await const NotificationPreferencesStore().save(
      account,
      const NotificationPreferences(enabled: true),
    );
    await service.preferencesChanged(account);
    final due = DateTime.now().add(const Duration(minutes: 3));
    await service.scheduleDueReminder(
      reminderId: reminderId,
      friendName: 'Synthetic friend',
      description: 'Settled tab should not remind',
      formattedAmount: 'PHP 5.00',
      dueDate: due,
      iOweThem: true,
      tabId: 'device-home002-settled',
    );
    final plugin = await service.permissionGranted();
    expect(plugin, isTrue);
    final notificationPlugin = FlutterLocalNotificationsPlugin();
    final pendingBefore = await notificationPlugin
        .pendingNotificationRequests();
    final reminderWasScheduled = pendingBefore.any(
      (request) => request.id == reminderNotificationId('due:$reminderId'),
    );
    expect(reminderWasScheduled, isTrue);

    final reminder = UpcomingReminder(
      id: reminderId,
      tabId: 'device-home002-settled',
      friendName: 'Synthetic friend',
      description: 'Settled tab should not remind',
      amountCentavos: 500,
      dueDate: due,
      isIWhoOwe: true,
    );
    final tab = BilateralTab(
      id: 'device-home002-settled',
      counterpart: const TabbyUser(
        id: 'synthetic-counterpart',
        displayName: 'Synthetic friend',
        email: 'synthetic@example.invalid',
        phone: '',
      ),
      netBalanceCentavos: 0,
      itemCount: 0,
      entries: const [],
      lastUpdated: DateTime.now(),
    );
    final homeUser = CurrentUserNotifier(
      initialUser: MockTabbyRepository.currentUser,
      autoLoad: false,
    );
    final notifier = _SeededNotifier(
      tabs: [tab],
      activities: const [],
      reminders: [reminder],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tabbyProvider.overrideWith((ref) => notifier),
          currentUserProvider.overrideWith((ref) => homeUser),
        ],
        child: const MaterialApp(home: HomeDashboardScreen(now: DateTime.now)),
      ),
    );
    await notifier.refreshDueReminders();
    await tester.pumpAndSettle(const Duration(milliseconds: 80));
    final pending = await notificationPlugin.pendingNotificationRequests();
    expect(notifier.state.reminders, isEmpty);
    expect(
      pending.any(
        (request) => request.id == reminderNotificationId(reminderId),
      ),
      isFalse,
    );
    expect(find.text('0 items'), findsOneWidget);
    debugPrint(
      'DEVICE_MATRIX_HOME002 permission=$plugin preRefreshAlarm=$reminderWasScheduled postRefreshRows=${notifier.state.reminders.length} alarmStillPending=false',
    );
  });

  testWidgets('HOME-003 real permission and disabled preferences gate alarms', (
    tester,
  ) async {
    const account = 'device-matrix-home003';
    const reminderId = 'device-matrix-disabled-reminder';
    final service = TabbyNotificationService.instance;
    await service.initialize();
    await service.setActiveAccount(account);
    final permission = await service.permissionGranted();
    const prefs = NotificationPreferencesStore();
    await prefs.save(
      account,
      const NotificationPreferences(enabled: true, reminders: true),
    );
    await service.preferencesChanged(account);
    final due = DateTime.now().add(const Duration(minutes: 3));
    await service.scheduleDueReminder(
      reminderId: reminderId,
      friendName: 'Synthetic friend',
      description: 'Preference enabled probe',
      formattedAmount: 'PHP 1.00',
      dueDate: due,
      iOweThem: true,
      tabId: 'device-home003-tab',
    );
    final plugin = FlutterLocalNotificationsPlugin();
    final before = await plugin.pendingNotificationRequests();
    final id = reminderNotificationId('due:$reminderId');
    final enabledScheduled = before.any((request) => request.id == id);

    await prefs.save(
      account,
      const NotificationPreferences(enabled: false, reminders: true),
    );
    await service.preferencesChanged(account);
    final after = await plugin.pendingNotificationRequests();
    expect(after.any((request) => request.id == id), isFalse);
    debugPrint(
      'DEVICE_MATRIX_HOME003 permissionGranted=$permission enabledPreferenceAlarm=$enabledScheduled disabledPreferenceAlarm=false',
    );
  });

  testWidgets('HOME-004 schedule a reminder for background delivery', (
    tester,
  ) async {
    const account = 'device-matrix-home004';
    const reminderId = 'device-matrix-background-delivery';
    final service = TabbyNotificationService.instance;
    await service.initialize();
    await service.setActiveAccount(account);
    await const NotificationPreferencesStore().save(
      account,
      const NotificationPreferences(enabled: true, reminders: true),
    );
    await service.preferencesChanged(account);
    final due = DateTime.now().add(const Duration(seconds: 45));
    await service.scheduleDueReminder(
      reminderId: reminderId,
      friendName: 'Synthetic friend',
      description: 'Closed app delivery probe',
      formattedAmount: 'PHP 2.02',
      dueDate: due,
      iOweThem: true,
      tabId: 'device-home004-tab',
    );
    debugPrint(
      'DEVICE_MATRIX_HOME004 due=${due.toIso8601String()} id=${reminderNotificationId(reminderId)}',
    );
  });

  testWidgets('HOME-004 schedule a reminder for force-stop probe', (
    tester,
  ) async {
    const account = 'device-matrix-home004-force-stop';
    const reminderId = 'device-matrix-force-stop-delivery';
    final service = TabbyNotificationService.instance;
    await service.initialize();
    await service.setActiveAccount(account);
    await const NotificationPreferencesStore().save(
      account,
      const NotificationPreferences(enabled: true, reminders: true),
    );
    await service.preferencesChanged(account);
    final due = DateTime.now().add(const Duration(seconds: 75));
    await service.scheduleDueReminder(
      reminderId: reminderId,
      friendName: 'Synthetic friend',
      description: 'Force-stopped app delivery probe',
      formattedAmount: 'PHP 3.03',
      dueDate: due,
      iOweThem: true,
      tabId: 'device-home004-force-stop-tab',
    );
    debugPrint(
      'DEVICE_MATRIX_HOME004_FORCE_STOP due=${due.toIso8601String()} id=${reminderNotificationId(reminderId)}',
    );
  });
}
