import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'ledger_cache_storage.dart';

import 'package:uuid/uuid.dart';

import '../../../core/config/supabase_config.dart';
import '../domain/models.dart';
import '../domain/activity_reconciliation.dart';
import 'mock_tabby_repository.dart';

/// Local offline cache manager for Tabby.
///
/// Persists tabs, activities, and reminders locally to prevent blank screens
/// or data loss when offline or during slow network handshakes.
class TabbyLocalCache {
  // Widget tests run a fake clock; native codec/storage benchmarks retain real
  // worker isolates. This hook is never enabled by the application.
  @visibleForTesting
  static bool debugInlineCodec = false;
  static const _storage = LedgerCacheStorage();
  static const _legacyKeyTabs = 'tabby_cached_tabs';
  static const _legacyKeyActivities = 'tabby_cached_activities';
  static const _legacyKeyReminders = 'tabby_cached_reminders';

  static String _scope([String? userId]) {
    final explicitUserId = userId?.trim();
    if (explicitUserId != null && explicitUserId.isNotEmpty) {
      return explicitUserId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    }

    if (SupabaseConfig.isInitialized) {
      final currentUserId = SupabaseConfig.currentUserId;
      if (currentUserId != null && currentUserId.isNotEmpty) {
        return currentUserId;
      }
      return 'unauthenticated';
    }

    return 'offline';
  }

  static String _key(String layer, [String? userId]) =>
      'tabby_cached_${layer}_${_scope(userId)}';

  /// Saves tabs to local secure cache, enforcing deduplication before persistence.
  static Future<void> saveTabs(
    List<BilateralTab> tabs, {
    String? userId,
    bool strict = false,
  }) async {
    try {
      final deduped = MockTabbyRepository.deduplicateTabs(
        tabs,
        currentUserId: userId,
      );
      final jsonList = deduped.map((t) => t.toMap()).toList();
      final jsonStr = debugInlineCodec
          ? jsonEncode(jsonList)
          : await compute(jsonEncode, jsonList);
      await _storage.write(key: _key('tabs', userId), value: jsonStr);
    } catch (e) {
      debugPrint('[TabbyLocalCache] saveTabs warning: $e');
      if (strict) rethrow;
    }
  }

  /// Loads cached tabs from local secure cache.
  /// Returns `null` if no cache exists or on read failure.
  static Future<List<BilateralTab>?> loadTabs({String? userId}) async {
    try {
      final raw = await _storage.read(key: _key('tabs', userId));
      if (raw == null || raw.isEmpty) return null;
      final parsed = debugInlineCodec
          ? _decodeCachedTabs(raw)
          : await compute(_decodeCachedTabs, raw);
      return MockTabbyRepository.deduplicateTabs(parsed, currentUserId: userId);
    } catch (e) {
      debugPrint('[TabbyLocalCache] loadTabs warning: $e');
      return null;
    }
  }

  /// Saves activities to local secure cache
  static Future<void> saveActivities(
    List<TabbyActivity> activities, {
    String? userId,
    bool strict = false,
  }) async {
    try {
      final deduped = await resolveActivityMappings(activities, userId: userId);
      final jsonList = deduped.map((a) => a.toMap()).toList();
      final jsonStr = jsonEncode(jsonList);
      await _storage.write(key: _key('activities', userId), value: jsonStr);
    } catch (e) {
      debugPrint('[TabbyLocalCache] saveActivities warning: $e');
      if (strict) rethrow;
    }
  }

  /// Loads cached activities from local secure cache.
  static Future<List<TabbyActivity>?> loadActivities({String? userId}) async {
    try {
      final raw = await _storage.read(key: _key('activities', userId));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw) as List<dynamic>;
      final list = decoded
          .map((item) => TabbyActivity.fromMap(item as Map<String, dynamic>))
          .toList();
      return await resolveActivityMappings(list, userId: userId);
    } catch (e) {
      debugPrint('[TabbyLocalCache] loadActivities warning: $e');
      return null;
    }
  }

  /// Saves reminders to local secure cache
  static Future<void> saveReminders(
    List<UpcomingReminder> reminders, {
    String? userId,
  }) async {
    try {
      final jsonList = reminders.map((r) => r.toMap()).toList();
      final jsonStr = jsonEncode(jsonList);
      await _storage.write(key: _key('reminders', userId), value: jsonStr);
    } catch (e) {
      debugPrint('[TabbyLocalCache] saveReminders warning: $e');
    }
  }

  /// Loads cached reminders from local secure cache.
  static Future<List<UpcomingReminder>?> loadReminders({String? userId}) async {
    try {
      final raw = await _storage.read(key: _key('reminders', userId));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => UpcomingReminder.fromMap(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[TabbyLocalCache] loadReminders warning: $e');
      return null;
    }
  }

  /// Saves notifications to local secure cache
  static Future<void> saveNotifications(
    List<AppNotification> notifications, {
    String? userId,
  }) async {
    try {
      final jsonList = notifications.map((n) => n.toMap()).toList();
      final jsonStr = jsonEncode(jsonList);
      await _storage.write(key: _key('notifications', userId), value: jsonStr);
    } catch (e) {
      debugPrint('[TabbyLocalCache] saveNotifications warning: $e');
    }
  }

  /// Loads cached notifications from local secure cache.
  static Future<List<AppNotification>?> loadNotifications({
    String? userId,
  }) async {
    try {
      final raw = await _storage.read(key: _key('notifications', userId));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => AppNotification.fromMap(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[TabbyLocalCache] loadNotifications warning: $e');
      return null;
    }
  }

  /// Clears all local cache (e.g., on logout)
  static Future<void> clearCache({String? userId}) async {
    try {
      await _storage.removeValue(key: _key('tabs', userId));
      await _storage.removeValue(key: _key('activities', userId));
      await _storage.removeValue(key: _key('reminders', userId));
      await _storage.removeValue(key: _key('notifications', userId));

      // Unsynced financial writes remain scoped to their owner after logout.
      // Remove cache written by versions before account scoping was added.
      await _storage.removeValue(key: _legacyKeyTabs);
      await _storage.removeValue(key: _legacyKeyActivities);
      await _storage.removeValue(key: _legacyKeyReminders);
    } catch (e) {
      debugPrint('[TabbyLocalCache] clearCache warning: $e');
    }
  }

  static Future<void>? _pendingOpWrite;

  static Future<void> _updatePendingOps(
    void Function(List<Map<String, dynamic>>) update, {
    required String scope,
  }) {
    final previous = _pendingOpWrite;
    late final Future<void> guard;
    Future<void> execute() async {
      try {
        if (previous != null) await previous;
        final ops = await _loadPendingOps(scope: scope, strict: true);
        for (final op in ops) {
          op['operation_id'] ??= const Uuid().v4();
        }
        update(ops);
        await _storage.write(
          key: 'tabby_pending_ops_$scope',
          value: jsonEncode(ops),
        );
      } finally {
        if (identical(_pendingOpWrite, guard)) _pendingOpWrite = null;
      }
    }

    final write = execute();
    guard = write.catchError((Object _) {});
    _pendingOpWrite = guard;
    return write;
  }

  static Future<void> enqueuePendingOp(
    Map<String, dynamic> op, {
    String? userId,
  }) {
    final pending = {
      ...op,
      'operation_id': op['operation_id'] ?? const Uuid().v4(),
    };
    return _updatePendingOps((ops) {
      final index = ops.indexWhere(
        (existing) => existing['operation_id'] == pending['operation_id'],
      );
      if (index >= 0) {
        const runtimeFields = {
          'rpc_name',
          'rpc_command',
          'proof_command',
          'attempt_count',
          'sync_state',
          'next_attempt_at',
        };
        Map<String, dynamic> intent(Map<String, dynamic> value) =>
            Map.fromEntries(
              value.entries.where((e) => !runtimeFields.contains(e.key)),
            );
        if (_canonicalJson(intent(ops[index])) !=
            _canonicalJson(intent(pending))) {
          throw StateError('Operation ID reused with a different intent.');
        }
        return;
      }
      ops.add(pending);
    }, scope: _scope(userId));
  }

  static String _canonicalJson(Object? value) {
    Object? canonical(Object? item) {
      if (item is Map) {
        final keys = item.keys.cast<String>().toList()..sort();
        return {for (final key in keys) key: canonical(item[key])};
      }
      if (item is List) return item.map(canonical).toList();
      return item;
    }

    return jsonEncode(canonical(value));
  }

  static Future<List<Map<String, dynamic>>> _loadPendingOps({
    required String scope,
    bool strict = false,
  }) async {
    try {
      final raw = await _storage.read(key: 'tabby_pending_ops_$scope');
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (e) {
      debugPrint(
        '[TabbyLocalCache] Durable queue read failed (${e.runtimeType}).',
      );
      if (strict) rethrow;
      return [];
    }
  }

  /// Returns all pending operations without changing the durable queue.
  static Future<List<Map<String, dynamic>>> loadPendingOps({
    String? userId,
    bool strict = false,
  }) async {
    final scope = _scope(userId);
    final ops = await _loadPendingOps(scope: scope, strict: strict);
    if (ops.every((op) => op['operation_id'] is String)) return ops;
    // Legacy records predate operation identities; persist the assigned ids so
    // a replay keeps the same identity across app launches.
    await _updatePendingOps((_) {}, scope: scope);
    return _loadPendingOps(scope: scope, strict: strict);
  }

  /// Removes one operation after its remote write has been confirmed.
  static Future<void> removePendingOp(
    Map<String, dynamic> operation, {
    String? userId,
  }) {
    final operationId = operation['operation_id'];
    if (operationId is String) {
      return acknowledgePendingOp(operationId, userId: userId);
    }
    final encodedOperation = jsonEncode(operation);
    return _updatePendingOps(
      (ops) => ops.removeWhere(
        (candidate) => jsonEncode(candidate) == encodedOperation,
      ),
      scope: _scope(userId),
    );
  }

  /// Drains and returns all pending offline operations, clearing the queue.
  static Future<List<Map<String, dynamic>>> drainPendingOps({
    String? userId,
  }) async {
    final scope = _scope(userId);
    late List<Map<String, dynamic>> snapshot;
    await _updatePendingOps((ops) {
      snapshot = ops.map(Map<String, dynamic>.from).toList();
      ops.clear();
    }, scope: scope);
    return snapshot;
  }

  static Future<void> acknowledgePendingOp(
    String operationId, {
    String? userId,
  }) => _updatePendingOps(
    (ops) => ops.removeWhere((op) => op['operation_id'] == operationId),
    scope: _scope(userId),
  );

  static Future<bool> hasPendingOps({String? userId}) async {
    final ops = await loadPendingOps(userId: userId);
    return ops.isNotEmpty;
  }

  static Future<void> retryPendingOperation(
    String operationId, {
    required String userId,
  }) => _updatePendingOps((ops) {
    for (final op in ops.where((p) => p['operation_id'] == operationId)) {
      op['sync_state'] = 'queued';
      op['attempt_count'] = 0;
      op.remove('next_attempt_at');
    }
  }, scope: _scope(userId));

  /// An explicit retry retains the original operation identity and wire command.
  /// Legacy intents without a local/server mapping require separate review.
  static Future<void> retryPendingWrites({required String userId}) =>
      _updatePendingOps((ops) {
        for (final op in ops) {
          if (op['local_entry_id'] is! String && op['type'] != 'm2_command') {
            continue;
          }
          op['sync_state'] = 'queued';
          op['attempt_count'] = 0;
          op.remove('next_attempt_at');
        }
      }, scope: _scope(userId));

  static Future<Map<String, dynamic>> prepareMoneyCommand(
    String operationId, {
    required String userId,
    required String rpc,
    required Map<String, dynamic> command,
  }) async {
    late Map<String, dynamic> prepared;
    await _updatePendingOps((ops) {
      final index = ops.indexWhere((op) => op['operation_id'] == operationId);
      if (index < 0) {
        throw StateError('Money command must be queued before execution.');
      }
      final op = ops[index];
      op['rpc_name'] ??= rpc;
      op['rpc_command'] ??= command;
      prepared = Map<String, dynamic>.from(jsonDecode(jsonEncode(op)) as Map);
    }, scope: _scope(userId));
    return prepared;
  }

  /// Retry metadata is durable so restarts/realtime events cannot reset limits.
  static Future<Map<String, dynamic>> prepareProofCommand(
    String operationId, {
    required String userId,
    required Map<String, dynamic> command,
  }) async {
    late Map<String, dynamic> result;
    await _updatePendingOps((ops) {
      final op = ops.firstWhere((op) => op['operation_id'] == operationId);
      op['proof_command'] ??= command;
      result = Map<String, dynamic>.from(op['proof_command'] as Map);
    }, scope: _scope(userId));
    return result;
  }

  static Future<void> remapPendingProofTargets(
    String localId,
    String serverId, {
    required String userId,
  }) => _updatePendingOps((ops) {
    for (final op in ops) {
      if ((op['type'] == 'append_payment_proof' ||
              op['type'] == 'append_receipt') &&
          op['target_entry_id'] == localId) {
        op['target_entry_id'] = serverId;
      }
    }
  }, scope: _scope(userId));

  static String _mappingKey(String localId, String? userId) =>
      'tabby_entry_mapping_${_scope(userId)}_${base64UrlEncode(utf8.encode(localId))}';
  static Future<Map<String, dynamic>?> loadEntryMapping(
    String localId, {
    String? userId,
  }) async {
    final index = await _loadEntryMappingIndex(userId);
    if (index[localId] is Map) {
      return Map<String, dynamic>.from(index[localId] as Map);
    }
    final raw = await _storage.read(key: _mappingKey(localId, userId));
    return raw == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  static Future<Map<String, dynamic>> _loadEntryMappingIndex(
    String? userId,
  ) async {
    final raw = await _storage.read(key: _key('entry_mappings_v1', userId));
    return raw == null ? {} : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  static Future<List<TabbyActivity>> resolveActivityMappings(
    List<TabbyActivity> activities, {
    String? userId,
  }) async {
    final index = await _loadEntryMappingIndex(userId);
    final mappings = <String, String>{};
    for (final activity in activities) {
      Map? mapping = index[activity.id] as Map?;
      // Compatibility with the earlier per-entry journal keys. Unknown legacy
      // logs stay separate; similarity never establishes an identity.
      if (mapping == null &&
          (activity.id.startsWith('entry-') ||
              activity.id.startsWith('payment-') ||
              activity.id.startsWith('act-'))) {
        final raw = await _storage.read(key: _mappingKey(activity.id, userId));
        if (raw != null) mapping = jsonDecode(raw) as Map;
      }
      final target = mapping?['entry_id'] as String?;
      if (target != null && target.isNotEmpty) mappings[activity.id] = target;
    }
    return reconcileActivityIds(activities, mappings: mappings);
  }

  static Future<void>? _entryMappingWrite;

  static Future<void> saveEntryMapping(
    String localId,
    String serverId,
    String tabId, {
    required String userId,
  }) {
    final previous = _entryMappingWrite;
    late final Future<void> guard;
    Future<void> execute() async {
      try {
        if (previous != null) await previous;
        final mapping = {'entry_id': serverId, 'tab_id': tabId};
        final prior = await loadEntryMapping(localId, userId: userId);
        if (prior != null && _canonicalJson(prior) != _canonicalJson(mapping)) {
          throw StateError('Conflicting entry identity mapping.');
        }
        await _storage.write(
          key: _mappingKey(localId, userId),
          value: jsonEncode(mapping),
        );
        final index = await _loadEntryMappingIndex(userId);
        index[localId] = mapping;
        await _storage.write(
          key: _key('entry_mappings_v1', userId),
          value: jsonEncode(index),
        );
      } finally {
        if (identical(_entryMappingWrite, guard)) _entryMappingWrite = null;
      }
    }

    final write = execute();
    guard = write.catchError((Object _) {});
    _entryMappingWrite = guard;
    return write;
  }

  static bool canAttemptPendingOp(Map<String, dynamic> op, DateTime now) {
    if (op['sync_state'] == 'needsAttention') return false;
    final next = DateTime.tryParse(op['next_attempt_at'] as String? ?? '');
    return next == null || !now.isBefore(next);
  }

  static Future<void> recordPendingFailure(
    String operationId, {
    required String userId,
    required DateTime now,
    bool permanent = false,
  }) => _updatePendingOps((ops) {
    final index = ops.indexWhere((op) => op['operation_id'] == operationId);
    if (index < 0) return;
    final op = ops[index];
    final attempts = (op['attempt_count'] as int? ?? 0) + 1;
    op['attempt_count'] = attempts;
    if (permanent || attempts >= 5) {
      op['sync_state'] = 'needsAttention';
      op.remove('next_attempt_at');
    } else {
      op['sync_state'] = 'retryableFailure';
      op['next_attempt_at'] = now
          .add(Duration(seconds: 5 * (1 << (attempts - 1))))
          .toUtc()
          .toIso8601String();
    }
  }, scope: _scope(userId));
}

List<BilateralTab> _decodeCachedTabs(String raw) => (jsonDecode(raw) as List)
    .map((item) => BilateralTab.fromMap(Map<String, dynamic>.from(item as Map)))
    .toList();
