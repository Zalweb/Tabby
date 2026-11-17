import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../config/supabase_config.dart';
import '../config/session_scope.dart';
import 'account_notification_controller.dart';
import 'notification_preferences.dart';
import 'background_reminder_service.dart';
import 'notification_tap_coordinator.dart';

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../router/app_router.dart';
import 'notification_schedule_policy.dart';
import 'reminder_notification_id.dart';

/// Singleton notification service.
/// Wraps flutter_local_notifications for on-device reminder and payment-alert delivery.
/// Coordinates local alarms with the account-bound Android background receiver.
class TabbyNotificationService {
  TabbyNotificationService._();
  static final TabbyNotificationService instance = TabbyNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _routingReady = false;
  Future<bool> Function(String actor, String tab)? _prepareTabForTap;
  Future<void>? _initializing;
  final _scheduledRechecks = <String, Future<void> Function()>{};
  String? _scheduleScope;
  static bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  final _preferences = const NotificationPreferencesStore();
  late final _taps = NotificationTapCoordinator(
    prepareTab: (actor, tab) async {
      final prepare = _prepareTabForTap;
      return prepare != null && await prepare(actor, tab);
    },
    canOpenTab: (actor, tab) async {
      if (!SupabaseConfig.isInitialized) return false;
      final row = await SupabaseConfig.client
          .from('tab_members')
          .select('id')
          .eq('tab_id', tab)
          .eq('user_id', actor)
          .limit(1);
      if (row.isEmpty) return false;
      final visible = await SupabaseConfig.client
          .from('tabs')
          .select('id,group_id')
          .eq('id', tab)
          .eq('status', 'active')
          .maybeSingle();
      if (visible == null) return false;
      if (visible['group_id'] != null) {
        final membership = await SupabaseConfig.client
            .from('group_members')
            .select('id')
            .eq('group_id', visible['group_id'])
            .eq('user_id', actor)
            .eq('status', 'active')
            .limit(1);
        return membership.isNotEmpty;
      }
      return true;
    },
    navigate: (route) {
      appRouter.push(route);
    },
  );
  Future<void> flushPendingTap() {
    if (!_routingReady) return Future.value();
    final stamp = SupabaseConfig.captureSession();
    return _taps.flush(
      actor: stamp.accountId,
      current: () => SupabaseConfig.isCurrentSession(stamp),
    );
  }

  void markRouterReady({
    required Future<bool> Function(String actor, String tab) prepareTab,
  }) {
    _prepareTabForTap = prepareTab;
    _routingReady = true;
    flushPendingTap();
  }

  bool get backgroundReady => BackgroundReminderService.instance.ready;
  late final _controller = AccountNotificationController(
    preferences: _preferences,
    permission: permissionGranted,
    cancel: (id) async {
      if (_initialized && supported) await _plugin.cancel(id: id);
    },
    cancelAll: () async {
      if (_initialized && supported) await _plugin.cancelAll();
    },
    pendingIds: () async => _initialized && supported
        ? (await _plugin.pendingNotificationRequests()).map((r) => r.id).toSet()
        : <int>{},
  );

  Future<void> setActiveAccount(String? account) async {
    final stamp = SupabaseConfig.captureSession();
    if (SupabaseConfig.isInitialized && stamp.accountId != account) {
      return;
    }
    final scope = '$account:${stamp.generation}';
    if (_scheduleScope != scope) _scheduledRechecks.clear();
    _scheduleScope = scope;
    final local = _controller.bind(
      account,
      session: '${stamp.accountId}:${stamp.generation}',
    );
    await Future.wait<void>([
      local,
      BackgroundReminderService.instance.bind(
        account,
        '${stamp.accountId}:${stamp.generation}',
      ),
    ]);
  }

  Future<void> logout(SessionStamp stamp) async {
    if (!SupabaseConfig.isCurrentSession(stamp)) return;
    // Invalidate native background display before any network revocation await.
    final background = BackgroundReminderService.instance;
    final local = _controller.bind(null, session: 'logout:${stamp.generation}');
    _scheduledRechecks.clear();
    await Future.wait<void>([
      local,
      background
          .bind(null, 'logout:${stamp.generation}')
          .then((_) => background.logout()),
    ]);
  }

  Future<void> preferencesChanged(String account) async {
    Future<void> updateBackground() async {
      try {
        await BackgroundReminderService.instance.synchronize(
          permission: await permissionGranted(),
        );
      } catch (_) {
        await BackgroundReminderService.instance.synchronize(permission: false);
        rethrow;
      }
    }

    await Future.wait<void>([
      _controller.preferencesChanged(account),
      updateBackground(),
    ]);
  }

  Future<bool> permissionGranted() async {
    if (!_initialized || !supported) return false;
    if (Platform.isAndroid) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.areNotificationsEnabled() ??
          false;
    }
    return (await _plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.checkPermissions())
            ?.isEnabled ??
        false;
  }

  String _payload(String account, String? route) =>
      jsonEncode({'v': 1, 'account': account, 'route': route});

  // ─── Notification Channel IDs ────────────────────────────────────────────

  static const String _channelIdReminders = 'tabby_reminders';
  static const String _channelIdPayments = 'tabby_payments';
  static const String _channelIdNudges = 'tabby_nudges';

  // ─── Initialization ──────────────────────────────────────────────────────

  /// Must be called once from main() before runApp().
  Future<void> initialize() {
    if (_initialized) return Future.value();
    return _initializing ??= _initializeOnce().whenComplete(
      () => _initializing = null,
    );
  }

  Future<void> _initializeOnce() async {
    if (!supported) {
      _initialized = true;
      return;
    }

    // Timezone data required for scheduled notifications
    tz.initializeTimeZones();
    // Default to Philippine Standard Time (Asia/Manila, UTC+8)
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Manila'));
    } catch (_) {
      // Fallback to UTC if timezone data is unavailable
    }

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: false, // Request explicitly on first enable
          requestBadgePermission: false,
          requestSoundPermission: false,
        );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
    final background = BackgroundReminderService.instance;
    background.onTap = (tap) {
      _taps.receive(tap);
      flushPendingTap();
    };
    background.onResume = () async {
      await background.synchronize(permission: await permissionGranted());
      // Android can cancel alarms on special-access revocation while the plugin
      // still reports its persisted request. Recheck the delivery policy too.
      for (final recheck in _scheduledRechecks.values.toList()) {
        await recheck();
      }
      await flushPendingTap();
    };
    await background.initialize();
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true &&
        launch?.notificationResponse != null) {
      _queueNotificationTap(launch!.notificationResponse!);
    }

    // Create Android notification channels
    if (!kIsWeb && Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelIdReminders,
              'Debt Reminders',
              description: 'Upcoming and overdue tab reminders',
              importance: Importance.high,
              playSound: true,
            ),
          );

      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelIdPayments,
              'Payment Alerts',
              description: 'When friends confirm or record payments',
              importance: Importance.defaultImportance,
              playSound: true,
            ),
          );

      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelIdNudges,
              'Gentle Nudges',
              description: 'Friendly reminders sent to you by friends',
              importance: Importance.defaultImportance,
              playSound: false,
            ),
          );
    }

    // Remove legacy/unscoped alarms before restoring the active account's
    // obligation-derived schedule. This also runs after an initialization retry.
    await _plugin.cancelAll();
    _initialized = true;
    debugPrint('[TabbyNotificationService] Initialized.');
  }

  // ─── Permission Request ───────────────────────────────────────────────────

  /// Requests platform notification permission.
  /// Returns true if the user granted permission.
  Future<bool> requestPermission() async {
    if (!supported) return false;
    await initialize();

    if (Platform.isAndroid) {
      final plugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await plugin?.requestNotificationsPermission() ?? false;
      // Only ask for alarm access during an explicit notification opt-in.
      // Denial still allows inexact reminders; it does not revoke notifications.
      if (granted && plugin != null) {
        try {
          if (await plugin.canScheduleExactNotifications() != true) {
            await plugin.requestExactAlarmsPermission();
          }
        } on PlatformException {
          // Scheduling checks access again and uses an inexact fallback.
        }
      }
      debugPrint(
        '[TabbyNotificationService] Android permission granted: $granted',
      );
      return granted;
    }

    if (Platform.isIOS) {
      final plugin = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final granted =
          await plugin?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
      debugPrint('[TabbyNotificationService] iOS permission granted: $granted');
      return granted;
    }

    return false;
  }

  // ─── Immediate Notifications ──────────────────────────────────────────────

  /// Shows an immediate notification when the user taps "Remind" on a tab.
  /// Represents a friendly nudge going out to the friend (local UX confirmation).
  Future<void> showNudgeSent({
    String? eventId,
    required String friendName,
    required String tabDescription,
  }) async {
    if (!_initialized) return;
    await _show(
      eventId: eventId,
      title: 'Reminder sent',
      body: 'Friendly nudge sent to $friendName for "$tabDescription".',
      channelId: _channelIdNudges,
      channelName: 'Gentle Nudges',
    );
  }

  /// Shows a local notification when a friend nudges the current user.
  Future<void> showReminderReceived({
    String? eventId,
    required String friendName,
    required String description,
    required String formattedAmount,
    required String tabId,
  }) async {
    if (!_initialized) return;
    await _show(
      eventId: eventId,
      title: '$friendName sent you a reminder',
      body: 'You owe $formattedAmount for "$description". Tap to settle up.',
      channelId: _channelIdNudges,
      channelName: 'Gentle Nudges',
      payload: 'tab:$tabId',
    );
  }

  /// Shows an immediate payment-confirmed notification.
  Future<void> showPaymentConfirmed({
    String? eventId,
    required String friendName,
    required String formattedAmount,
    required String tabId,
  }) async {
    if (!_initialized) return;
    await _show(
      eventId: eventId,
      title: 'Payment confirmed',
      body: '$friendName confirmed your $formattedAmount payment. Tab updated.',
      channelId: _channelIdPayments,
      channelName: 'Payment Alerts',
      payload: 'tab:$tabId',
    );
  }

  /// Shows an immediate alert when the user receives a friendly tab reminder/nudge from a friend.
  Future<void> showTabReminderAlert({
    String? eventId,
    required String title,
    required String body,
    String? tabId,
  }) async {
    if (!_initialized) return;
    await _show(
      eventId: eventId,
      title: title,
      body: body,
      channelId: _channelIdReminders,
      channelName: 'Debt Reminders',
      payload: tabId != null ? 'tab:$tabId' : null,
    );
  }

  /// Shows an immediate notification for incoming friend requests or accepted requests.
  Future<void> showFriendRequestAlert({
    String? eventId,
    required String title,
    required String body,
    String? tabId,
  }) async {
    if (!_initialized) return;
    await _show(
      eventId: eventId,
      title: title,
      body: body,
      channelId: _channelIdNudges,
      channelName: 'Friend Requests',
      payload: tabId != null ? 'tab:$tabId' : 'connections',
    );
  }

  /// Shows an immediate notification when a new tab is created with the user.
  Future<void> showNewTabCreated({
    String? eventId,
    required String title,
    required String body,
    String? tabId,
  }) async {
    if (!_initialized) return;
    await _show(
      eventId: eventId,
      title: title,
      body: body,
      channelId: _channelIdReminders,
      channelName: 'Tab Updates',
      payload: tabId != null ? 'tab:$tabId' : null,
    );
  }

  /// Shows an immediate notification when an expense is added to a tab.
  Future<void> showExpenseAdded({
    String? eventId,
    required String title,
    required String body,
    String? tabId,
  }) async {
    if (!_initialized) return;
    await _show(
      eventId: eventId,
      title: title,
      body: body,
      channelId: _channelIdReminders,
      channelName: 'Tab Updates',
      payload: tabId != null ? 'tab:$tabId' : null,
    );
  }

  /// Shows an immediate payment alert notification.
  Future<void> showPaymentAlert({
    String? eventId,
    required String title,
    required String body,
    String? tabId,
  }) async {
    if (!_initialized) return;
    await _show(
      eventId: eventId,
      title: title,
      body: body,
      channelId: _channelIdPayments,
      channelName: 'Payment Alerts',
      payload: tabId != null ? 'tab:$tabId' : null,
    );
  }

  // ─── Scheduled Reminders ─────────────────────────────────────────────────

  /// Schedules a local notification at the reminder's due date.
  /// [reminderId] is used as the notification ID for cancellation.
  Future<void> scheduleDueReminder({
    required String reminderId,
    required String friendName,
    required String description,
    required String formattedAmount,
    required DateTime dueDate,
    required bool iOweThem, // true = I owe; false = they owe me
    required String tabId,
  }) async {
    if (!_initialized) return;

    final scheduledDate = tz.TZDateTime.from(dueDate, tz.local);
    if (scheduledDate.isBefore(tz.TZDateTime.now(tz.local))) {
      _scheduledRechecks.remove(reminderId);
      // Already past — show immediately
      await _show(
        eventId: 'due:$reminderId',
        title: iOweThem
            ? 'Payment overdue'
            : '$friendName has an overdue balance',
        body: iOweThem
            ? 'Your $formattedAmount for "$description" is past due.'
            : '$friendName still owes you $formattedAmount for "$description".',
        channelId: _channelIdReminders,
        channelName: 'Debt Reminders',
        payload: 'tab:$tabId',
      );
      return;
    }

    final title = iOweThem
        ? 'Payment due today'
        : 'Reminder: $friendName owes you';
    final body = iOweThem
        ? '$formattedAmount for "$description" is due today. Tap to settle up.'
        : '$friendName owes you $formattedAmount for "$description". Due today.';

    final actor = _controller.account;
    final session = SupabaseConfig.captureSession();
    _scheduledRechecks[reminderId] = () async {
      if (_controller.account != actor ||
          !SupabaseConfig.isCurrentSession(session)) {
        return;
      }
      await scheduleDueReminder(
        reminderId: reminderId,
        friendName: friendName,
        description: description,
        formattedAmount: formattedAmount,
        dueDate: dueDate,
        iOweThem: iOweThem,
        tabId: tabId,
      );
    };
    Future<bool> canScheduleExact() async =>
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.canScheduleExactNotifications() ??
        false;
    final exact = await NotificationSchedulePolicy.exactAllowed(
      isAndroid: !kIsWeb && Platform.isAndroid,
      canScheduleExact: canScheduleExact,
    );

    await _controller.notify(
      key: 'due:$reminderId',
      kind: NotificationKind.reminder,
      signature: jsonEncode([title, body, dueDate.toIso8601String(), tabId]),
      scheduled: true,
      deliveryPolicy: exact ? 'exact' : 'inexact',
      send: (notifId, account) => NotificationSchedulePolicy.schedule(
        isAndroid: !kIsWeb && Platform.isAndroid,
        canScheduleExact: canScheduleExact,
        send: (mode) => _plugin.zonedSchedule(
          id: notifId,
          title: title,
          body: body,
          scheduledDate: scheduledDate,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelIdReminders,
              'Debt Reminders',
              channelDescription: 'Upcoming and overdue tab reminders',
              importance: Importance.high,
              priority: Priority.high,
              playSound: true,
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
          androidScheduleMode: mode,
          payload: _payload(account, 'tab:$tabId'),
        ),
      ),
    );
  }

  /// Cancels a previously scheduled reminder by its ID.
  Future<void> cancelReminder(String reminderId) async {
    _scheduledRechecks.remove(reminderId);
    if (!_initialized) return;
    await _controller.cancelKey(
      'due:$reminderId',
      legacyIds: {
        reminderNotificationId(reminderId),
        reminderId.hashCode & 0x7fffffff,
      },
    );
  }

  /// Cancels all pending scheduled notifications.
  Future<void> cancelAll() async {
    if (!_initialized) return;
    await _plugin.cancelAll();
  }

  // ─── Internal Helpers ─────────────────────────────────────────────────────

  Future<void> _show({
    String? eventId,
    NotificationKind? kind,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
    String? payload,
  }) async {
    try {
      await _controller.notify(
        key: eventId ?? 'local:${const Uuid().v4()}',
        kind:
            kind ??
            (channelId == _channelIdPayments
                ? NotificationKind.payment
                : NotificationKind.reminder),
        signature: jsonEncode([title, body, payload]),
        scheduled: false,
        send: (id, account) => _plugin.show(
          id: id,
          title: title,
          body: body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              channelId,
              channelName,
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
              playSound: true,
            ),
            iOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: false,
              presentSound: true,
            ),
          ),
          payload: _payload(account, payload),
        ),
      );
    } catch (error) {
      debugPrint(
        '[TabbyNotificationService] Notification skipped (${error.runtimeType}).',
      );
    }
  }

  void _queueNotificationTap(NotificationResponse response) {
    try {
      final data = Map<String, dynamic>.from(
        jsonDecode(response.payload ?? '') as Map,
      );
      if (data['v'] == 1 && data['account'] is String) _taps.receive(data);
    } catch (_) {
      return;
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    _queueNotificationTap(response);
    flushPendingTap();
  }
}
