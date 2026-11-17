import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Stable across process restarts/platforms; Dart hashCode is not a durable ID.
int reminderNotificationId(String reminderId) {
  var value = 0;
  for (final byte in sha256.convert(utf8.encode(reminderId)).bytes.take(4)) {
    value = (value << 8) | byte;
  }
  return value & 0x7fffffff;
}
