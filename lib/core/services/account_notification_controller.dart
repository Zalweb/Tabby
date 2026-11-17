import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'notification_preferences.dart';
import 'reminder_notification_id.dart';

/// One serialized owner for device writes, account transitions and durable IDs.
/// Ports are injected in tests; a successful port call is not delivery evidence.
class AccountNotificationController {
  AccountNotificationController({
    required this.preferences,
    required this.permission,
    required this.cancel,
    required this.cancelAll,
    required this.pendingIds,
    this.storage = const FlutterSecureStorage(),
    int Function(String)? initialId,
  }) : initialId = initialId ?? reminderNotificationId;
  final NotificationPreferencesStore preferences;
  final FlutterSecureStorage storage;
  final Future<bool> Function() permission;
  final Future<void> Function(int) cancel;
  final Future<void> Function() cancelAll;
  final Future<Set<int>> Function() pendingIds;
  final int Function(String) initialId;
  String? _account;
  Object? _session;
  int _generation = 0;
  Future<void>? _work;
  String? get account => _account;

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final prior = _work;
    late final Future<void> guard;
    Future<T> run() async {
      try {
        await Future<void>.value();
        if (prior != null) await prior;
        return await action();
      } finally {
        if (identical(_work, guard)) _work = null;
      }
    }

    final task = run();
    guard = task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _work = guard;
    return task;
  }

  Future<void> bind(String? account, {Object? session}) {
    if (_account == account && _session == session) return Future.value();
    _account = account;
    _session = session;
    ++_generation;
    // Queued after any in-flight show: logout/account change cancels that write too.
    return _enqueue(cancelAll);
  }

  bool _current(String account, int generation) =>
      _account == account && _generation == generation;
  String _key(String account) => 'tabby_${account}_notification_registry_v1';
  Future<Map<String, dynamic>> _registry(String account) async {
    final raw = await storage.read(key: _key(account));
    return raw == null ? {} : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<void> _save(String account, Map<String, dynamic> records) =>
      storage.write(key: _key(account), value: jsonEncode(records));

  Future<bool> notify({
    required String key,
    required NotificationKind kind,
    required String signature,
    required bool scheduled,
    String? deliveryPolicy,
    required Future<void> Function(int id, String account) send,
  }) {
    final actor = _account, generation = _generation;
    if (actor == null || actor.isEmpty) return Future.value(false);
    return _enqueue(() async {
      if (!_current(actor, generation)) return false;
      final preference = await preferences.load(actor);
      if (!preference.allows(kind) ||
          !await permission() ||
          !_current(actor, generation)) {
        return false;
      }
      final records = await _registry(actor);
      final old = records[key] is Map
          ? Map<String, dynamic>.from(records[key] as Map)
          : null;
      final digest = sha256
          .convert(
            utf8.encode(
              deliveryPolicy == null
                  ? signature
                  : jsonEncode([signature, deliveryPolicy]),
            ),
          )
          .toString();
      final used = records.values
          .whereType<Map>()
          .map((r) => r['id'] as int)
          .toSet();
      var id = old?['id'] as int? ?? (initialId(key) & 0x7fffffff);
      if (old == null) {
        while (used.contains(id)) {
          id = (id + 1) & 0x7fffffff;
        }
      }
      if (old?['signature'] == digest &&
          (!scheduled || (await pendingIds()).contains(id))) {
        return false;
      }
      if (!_current(actor, generation)) return false;
      await send(id, actor);
      if (!_current(actor, generation)) return false;
      records[key] = {'id': id, 'kind': kind.name, 'signature': digest};
      await _save(actor, records);
      return true;
    });
  }

  Future<void> cancelKey(String key, {Set<int> legacyIds = const {}}) {
    final actor = _account, generation = _generation;
    if (actor == null) return Future.value();
    return _enqueue(() async {
      if (!_current(actor, generation)) return;
      final records = await _registry(actor);
      final record = records[key] is Map
          ? Map<String, dynamic>.from(records[key] as Map)
          : null;
      if (record != null) await cancel(record['id'] as int);
      for (final id in legacyIds) {
        if (!_current(actor, generation)) return;
        final reservedElsewhere = records.entries.any(
          (entry) =>
              entry.key != key && entry.value is Map && entry.value['id'] == id,
        );
        if (id != record?['id'] && !reservedElsewhere) await cancel(id);
      }
      if (!_current(actor, generation)) return;
      if (record == null) return;
      record['signature'] = null;
      records[key] = record;
      await _save(actor, records);
    });
  }

  Future<void> preferencesChanged(String actor) {
    final generation = _generation;
    return _enqueue(() async {
      if (!_current(actor, generation)) return;
      NotificationPreferences preference;
      try {
        preference = await preferences.load(actor);
      } catch (_) {
        if (_current(actor, generation)) await cancelAll();
        rethrow;
      }
      if (!_current(actor, generation)) return;
      final records = await _registry(actor);
      if (!_current(actor, generation)) return;
      if (!preference.enabled) await cancelAll();
      for (final entry in records.entries) {
        if (!_current(actor, generation)) return;
        final record = Map<String, dynamic>.from(entry.value as Map);
        if (!preference.allows(
          NotificationKind.values.byName(record['kind'] as String),
        )) {
          if (preference.enabled) await cancel(record['id'] as int);
          record['signature'] = null;
          records[entry.key] = record;
        }
      }
      if (_current(actor, generation)) await _save(actor, records);
    });
  }
}
