import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../features/classroom/domain/classroom_models.dart';

/// Singleton notification service.
/// Wraps flutter_local_notifications for on-device reminder and payment-alert delivery.
/// No Firebase / FCM required — works fully with sideloaded APK.
class TabbyNotificationService {
  TabbyNotificationService._();
  static final TabbyNotificationService instance = TabbyNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // ─── Notification Channel IDs ────────────────────────────────────────────

  static const String _channelIdReminders = 'tabby_reminders';
  static const String _channelIdPayments = 'tabby_payments';
  static const String _channelIdNudges = 'tabby_nudges';
  static const String _channelIdClassroom = 'tabby_classroom';

  // ─── Initialization ──────────────────────────────────────────────────────

  /// Must be called once from main() before runApp().
  Future<void> initialize() async {
    if (_initialized) return;

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

    // Create Android notification channels
    if (!kIsWeb && Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            _channelIdReminders,
            'Debt Reminders',
            description: 'Upcoming and overdue tab reminders',
            importance: Importance.high,
            playSound: true,
          ));

      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            _channelIdPayments,
            'Payment Alerts',
            description: 'When friends confirm or record payments',
            importance: Importance.defaultImportance,
            playSound: true,
          ));

      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            _channelIdNudges,
            'Gentle Nudges',
            description: 'Friendly reminders sent to you by friends',
            importance: Importance.defaultImportance,
            playSound: false,
          ));

      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            _channelIdClassroom,
            'Assignment Reminders',
            description: 'Due date alarms for Google Classroom assignments',
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ));
    }

    _initialized = true;
    debugPrint('[TabbyNotificationService] Initialized.');
  }

  // ─── Permission Request ───────────────────────────────────────────────────

  /// Requests platform notification permission.
  /// Returns true if the user granted permission.
  Future<bool> requestPermission() async {
    if (kIsWeb) return false;

    if (Platform.isAndroid) {
      final plugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await plugin?.requestNotificationsPermission() ?? false;
      debugPrint(
          '[TabbyNotificationService] Android permission granted: $granted');
      return granted;
    }

    if (Platform.isIOS) {
      final plugin = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final granted = await plugin?.requestPermissions(
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
    required String friendName,
    required String tabDescription,
  }) async {
    if (!_initialized) return;
    await _show(
      id: friendName.hashCode & 0x7FFFFFFF,
      title: 'Reminder sent',
      body: 'Friendly nudge sent to $friendName for "$tabDescription".',
      channelId: _channelIdNudges,
      channelName: 'Gentle Nudges',
    );
  }

  /// Shows a local notification when a friend nudges the current user.
  Future<void> showReminderReceived({
    required String friendName,
    required String description,
    required String formattedAmount,
    required String tabId,
  }) async {
    if (!_initialized) return;
    await _show(
      id: ('nudge_$tabId').hashCode & 0x7FFFFFFF,
      title: '$friendName sent you a reminder',
      body: 'You owe $formattedAmount for "$description". Tap to settle up.',
      channelId: _channelIdNudges,
      channelName: 'Gentle Nudges',
      payload: 'tab:$tabId',
    );
  }

  /// Shows an immediate payment-confirmed notification.
  Future<void> showPaymentConfirmed({
    required String friendName,
    required String formattedAmount,
    required String tabId,
  }) async {
    if (!_initialized) return;
    await _show(
      id: ('pay_$tabId').hashCode & 0x7FFFFFFF,
      title: 'Payment confirmed',
      body: '$friendName confirmed your $formattedAmount payment. Tab updated.',
      channelId: _channelIdPayments,
      channelName: 'Payment Alerts',
      payload: 'tab:$tabId',
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
      // Already past — show immediately
      await _show(
        id: reminderId.hashCode & 0x7FFFFFFF,
        title:
            iOweThem ? 'Payment overdue' : '$friendName has an overdue balance',
        body: iOweThem
            ? 'Your $formattedAmount for "$description" is past due.'
            : '$friendName still owes you $formattedAmount for "$description".',
        channelId: _channelIdReminders,
        channelName: 'Debt Reminders',
        payload: 'tab:$tabId',
      );
      return;
    }

    final int notifId = reminderId.hashCode & 0x7FFFFFFF;
    final title =
        iOweThem ? 'Payment due today' : 'Reminder: $friendName owes you';
    final body = iOweThem
        ? '$formattedAmount for "$description" is due today. Tap to settle up.'
        : '$friendName owes you $formattedAmount for "$description". Due today.';

    await _plugin.zonedSchedule(
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
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'tab:$tabId',
    );

    debugPrint(
        '[TabbyNotificationService] Scheduled reminder $notifId at $scheduledDate');
  }

  /// Cancels a previously scheduled reminder by its ID.
  Future<void> cancelReminder(String reminderId) async {
    await _plugin.cancel(id: reminderId.hashCode & 0x7FFFFFFF);
  }

  /// Cancels all pending scheduled notifications.
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  /// Schedules the enabled 60-, 30-, and 10-minute reminders for a task.
  Future<void> scheduleTaskAlarms({
    required ClassroomTask task,
    required bool alarm60mEnabled,
    required bool alarm30mEnabled,
    required bool alarm10mEnabled,
  }) async {
    if (!_initialized || !task.hasDueDate) return;

    final dueAt = task.dueAt!;
    final alarms = <int, bool>{
      60: alarm60mEnabled,
      30: alarm30mEnabled,
      10: alarm10mEnabled,
    };
    for (final entry in alarms.entries) {
      final offsetMinutes = entry.key;
      if (!entry.value) {
        await _plugin.cancel(
            id: _taskAlarmId(task.googleTaskId, offsetMinutes));
        continue;
      }

      final scheduledAt = dueAt.subtract(Duration(minutes: offsetMinutes));
      if (scheduledAt.isBefore(DateTime.now())) {
        await _plugin.cancel(
            id: _taskAlarmId(task.googleTaskId, offsetMinutes));
        continue;
      }

      await _plugin.zonedSchedule(
        id: _taskAlarmId(task.googleTaskId, offsetMinutes),
        title: _taskAlarmTitleExact(offsetMinutes),
        body: _taskAlarmBodyExact(task, offsetMinutes),
        scheduledDate: tz.TZDateTime.from(scheduledAt, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelIdClassroom,
            'Assignment Reminders',
            channelDescription:
                'Due date alarms for Google Classroom assignments',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'classroom:${task.googleTaskId}',
      );
    }
  }

  /// Cancels all alarms associated with one Classroom task.
  Future<void> cancelTaskAlarms(String googleTaskId) async {
    for (final offsetMinutes in [60, 30, 10]) {
      await _plugin.cancel(id: _taskAlarmId(googleTaskId, offsetMinutes));
    }
  }

  /// Restores Classroom alarms after app startup or a settings change.
  Future<void> reregisterAllTaskAlarms({
    required List<ClassroomTask> tasks,
    required ClassroomConnection connection,
  }) async {
    if (!_initialized || !connection.isActive) return;
    for (final task in tasks) {
      await scheduleTaskAlarms(
        task: task,
        alarm60mEnabled: connection.alarm60mEnabled,
        alarm30mEnabled: connection.alarm30mEnabled,
        alarm10mEnabled: connection.alarm10mEnabled,
      );
    }
  }

  /// Shows an immediate local notification for a newly synced assignment.
  Future<void> showNewTaskDetected({
    required String taskTitle,
    required String courseName,
    required DateTime? dueAt,
    required String googleTaskId,
  }) async {
    if (!_initialized) return;
    final dueText =
        dueAt == null ? 'No due date' : 'Due at ${_formatTime(dueAt)}';
    await _show(
      id: ('classroom_new_$googleTaskId').hashCode & 0x7FFFFFFF,
      title: 'New Classroom assignment',
      body: '$taskTitle — $courseName · $dueText',
      channelId: _channelIdClassroom,
      channelName: 'Assignment Reminders',
      payload: 'classroom:$googleTaskId',
    );
  }

  @visibleForTesting
  static int taskAlarmIdForTesting(String googleTaskId, int offsetMinutes) {
    return _taskAlarmId(googleTaskId, offsetMinutes);
  }

  static int _taskAlarmId(String googleTaskId, int offsetMinutes) =>
      ('classroom_${googleTaskId}_${offsetMinutes}m').hashCode & 0x7FFFFFFF;

  // Kept for compatibility with existing notification copy integrations.
  // ignore: unused_element
  static String _taskAlarmTitle(int offsetMinutes) {
    switch (offsetMinutes) {
      case 60:
        return 'Assignment due in 1 hour';
      case 30:
        return '30 minutes left';
      default:
        return '10 minutes — submit now';
    }
  }

  static String _taskAlarmTitleExact(int offsetMinutes) {
    switch (offsetMinutes) {
      case 60:
        return 'Assignment due in 1 hour';
      case 30:
        return '30 minutes left';
      default:
        return '10 minutes \u2014 submit now';
    }
  }

  // Kept for compatibility with existing notification copy integrations.
  // ignore: unused_element
  static String _taskAlarmBody(ClassroomTask task, int offsetMinutes) {
    final dueText = _formatTime(task.dueAt!);
    switch (offsetMinutes) {
      case 60:
        return '${task.title} — ${task.courseName} · Due at $dueText';
      case 30:
        return '${task.title} — ${task.courseName} · Due at $dueText. Submit soon.';
      default:
        return '${task.title} — ${task.courseName} · Due at $dueText. Last chance!';
    }
  }

  static String _taskAlarmBodyExact(ClassroomTask task, int offsetMinutes) {
    switch (offsetMinutes) {
      case 60:
        return '${task.title} \u2014 ${task.courseName} \u00b7 Due at ${_formatTime(task.dueAt!)}';
      case 30:
        return '${task.title} \u2014 ${task.courseName} \u00b7 Submit soon.';
      default:
        return '${task.title} \u2014 ${task.courseName} \u00b7 Last chance!';
    }
  }

  static String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  // ─── Internal Helpers ─────────────────────────────────────────────────────

  Future<void> _show({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
    String? payload,
  }) async {
    await _plugin.show(
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
      payload: payload,
    );
  }

  void _onNotificationTapped(NotificationResponse response) {
    // payload format: 'tab:<tabId>' or 'nudge' etc.
    final payload = response.payload;
    if (payload == null) return;
    debugPrint('[TabbyNotificationService] Notification tapped: $payload');
    // Navigation is handled by the NotificationRouteListener widget in app_router
  }
}
