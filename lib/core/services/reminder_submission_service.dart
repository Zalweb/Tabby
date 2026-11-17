import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

enum ReminderSendResult {
  accepted('Reminder accepted. Your friend can see it in Tabby.'),
  failed('Reminder was not accepted. Check your connection and try again.'),
  unavailable(
      'Reminders need a registered friend with an outstanding balance.'),
  sessionChanged('Your account changed. Please try again.');

  const ReminderSendResult(this.message);
  final String message;
}

/// Retains a stable operation ID across failed/lost responses and restarts.
/// Explicit retries send the original command; only server acknowledgment clears it.
class ReminderSubmissionService {
  ReminderSubmissionService(
      {required this.send, this.storage = const FlutterSecureStorage()});
  final Future<String?> Function(
      String operationId, Map<String, dynamic> command) send;
  final FlutterSecureStorage storage;
  final Map<String, Future<String?>> _inflight = {};

  Future<String?> submit(String actor, Map<String, dynamic> command,
      {required bool Function() current}) {
    final keys = command.keys.toList()..sort();
    final encoded = jsonEncode({for (final key in keys) key: command[key]});
    final digest = sha256.convert(utf8.encode(encoded));
    final key = 'tabby_${actor}_pending_reminder_$digest';
    return _inflight.putIfAbsent(key, () async {
      try {
        await Future<void>.value();
        if (!current()) return null;
        final raw = await storage.read(key: key);
        final operation = raw ?? const Uuid().v4();
        if (!current()) return null;
        if (raw == null) await storage.write(key: key, value: operation);
        if (!current()) return null;
        final result = await send(operation, command);
        if (!current() || result == null || result.isEmpty) return null;
        await storage.delete(key: key);
        return current() ? result : null;
      } finally {
        _inflight.remove(key);
      }
    });
  }
}
