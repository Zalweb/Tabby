import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Checks current special access at scheduling time and handles revocation races.
class NotificationSchedulePolicy {
  static Future<bool> exactAllowed({
    required bool isAndroid,
    required Future<bool> Function() canScheduleExact,
  }) async {
    if (!isAndroid) return true;
    try {
      return await canScheduleExact();
    } on PlatformException {
      return false;
    }
  }

  static Future<void> schedule({
    required bool isAndroid,
    required Future<bool> Function() canScheduleExact,
    required Future<void> Function(AndroidScheduleMode mode) send,
  }) async {
    final exact = await exactAllowed(
      isAndroid: isAndroid,
      canScheduleExact: canScheduleExact,
    );
    final mode = exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
    try {
      await send(mode);
    } on PlatformException catch (error) {
      if (!isAndroid || !exact || error.code != 'exact_alarms_not_permitted') {
        rethrow;
      }
      await send(AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }
}
