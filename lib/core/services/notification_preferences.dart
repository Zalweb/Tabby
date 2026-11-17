import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum NotificationKind { reminder, payment, system }

class NotificationPreferences {
  const NotificationPreferences(
      {this.enabled = false, this.payments = true, this.reminders = true});
  final bool enabled;
  final bool payments;
  final bool reminders;
  bool allows(NotificationKind kind) =>
      enabled &&
      switch (kind) {
        NotificationKind.payment => payments,
        NotificationKind.reminder => reminders,
        NotificationKind.system => true,
      };
  Map<String, dynamic> toMap() =>
      {'enabled': enabled, 'payments': payments, 'reminders': reminders};
  factory NotificationPreferences.fromMap(Map<String, dynamic> map) {
    if (['enabled', 'payments', 'reminders'].any((key) => map[key] is! bool)) {
      throw const FormatException('Invalid notification preferences.');
    }
    return NotificationPreferences(
        enabled: map['enabled'] as bool,
        payments: map['payments'] as bool,
        reminders: map['reminders'] as bool);
  }
}

class NotificationPreferencesStore {
  const NotificationPreferencesStore(
      {this.storage = const FlutterSecureStorage()});
  final FlutterSecureStorage storage;
  Future<NotificationPreferences> load(String account) async {
    final raw =
        await storage.read(key: 'tabby_${account}_notification_preferences_v1');
    if (raw != null) {
      return NotificationPreferences.fromMap(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
    }
    // Only the same account's legacy keys are compatible. Never inherit global keys.
    final enabled =
        await storage.read(key: 'tabby_${account}_notifications_enabled');
    final payments =
        await storage.read(key: 'tabby_${account}_payment_alerts_enabled');
    final reminders =
        await storage.read(key: 'tabby_${account}_reminder_nudges_enabled');
    return NotificationPreferences(
        enabled: enabled == 'true',
        payments: payments != 'false',
        reminders: reminders != 'false');
  }

  Future<void> save(String account, NotificationPreferences preferences) =>
      storage.write(
          key: 'tabby_${account}_notification_preferences_v1',
          value: jsonEncode(preferences.toMap()));
}
