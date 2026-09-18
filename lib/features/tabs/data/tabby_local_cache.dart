import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/config/supabase_config.dart';
import '../domain/models.dart';

/// Local offline cache manager for Tabby.
///
/// Persists tabs, activities, and reminders locally to prevent blank screens
/// or data loss when offline or during slow network handshakes.
class TabbyLocalCache {
  static const _storage = FlutterSecureStorage();
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

  /// Saves tabs to local secure cache
  static Future<void> saveTabs(List<BilateralTab> tabs,
      {String? userId}) async {
    try {
      final jsonList = tabs.map((t) => t.toMap()).toList();
      final jsonStr = jsonEncode(jsonList);
      await _storage.write(key: _key('tabs', userId), value: jsonStr);
    } catch (e) {
      debugPrint('[TabbyLocalCache] saveTabs warning: $e');
    }
  }

  /// Loads cached tabs from local secure cache.
  /// Returns `null` if no cache exists or on read failure.
  static Future<List<BilateralTab>?> loadTabs({String? userId}) async {
    try {
      final raw = await _storage.read(key: _key('tabs', userId));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => BilateralTab.fromMap(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[TabbyLocalCache] loadTabs warning: $e');
      return null;
    }
  }

  static List<TabbyActivity> _dedupActivities(List<TabbyActivity> list) {
    final seenIds = <String>{};
    final seenKeys = <String>{};
    final result = <TabbyActivity>[];
    for (final a in list) {
      if (a.id.isNotEmpty && !seenIds.add(a.id)) {
        continue;
      }
      final timeKey = a.timestamp.millisecondsSinceEpoch ~/ 3000;
      final key =
          '${a.actorName}_${a.description}_${a.amountCentavos}_$timeKey';
      if (!seenKeys.add(key)) {
        continue;
      }
      result.add(a);
    }
    return result;
  }

  /// Saves activities to local secure cache
  static Future<void> saveActivities(List<TabbyActivity> activities,
      {String? userId}) async {
    try {
      final deduped = _dedupActivities(activities);
      final jsonList = deduped.map((a) => a.toMap()).toList();
      final jsonStr = jsonEncode(jsonList);
      await _storage.write(key: _key('activities', userId), value: jsonStr);
    } catch (e) {
      debugPrint('[TabbyLocalCache] saveActivities warning: $e');
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
      return _dedupActivities(list);
    } catch (e) {
      debugPrint('[TabbyLocalCache] loadActivities warning: $e');
      return null;
    }
  }

  /// Saves reminders to local secure cache
  static Future<void> saveReminders(List<UpcomingReminder> reminders,
      {String? userId}) async {
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
  static Future<void> saveNotifications(List<AppNotification> notifications,
      {String? userId}) async {
    try {
      final jsonList = notifications.map((n) => n.toMap()).toList();
      final jsonStr = jsonEncode(jsonList);
      await _storage.write(key: _key('notifications', userId), value: jsonStr);
    } catch (e) {
      debugPrint('[TabbyLocalCache] saveNotifications warning: $e');
    }
  }

  /// Loads cached notifications from local secure cache.
  static Future<List<AppNotification>?> loadNotifications(
      {String? userId}) async {
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
      await _storage.delete(key: _key('tabs', userId));
      await _storage.delete(key: _key('activities', userId));
      await _storage.delete(key: _key('reminders', userId));
      await _storage.delete(key: _key('notifications', userId));
      await _storage.delete(key: 'tabby_pending_ops_${_scope(userId)}');

      // Remove cache written by versions before account scoping was added.
      await _storage.delete(key: _legacyKeyTabs);
      await _storage.delete(key: _legacyKeyActivities);
      await _storage.delete(key: _legacyKeyReminders);
    } catch (e) {
      debugPrint('[TabbyLocalCache] clearCache warning: $e');
    }
  }

  /// Enqueues an offline operation to be synced when connectivity returns.
  static Future<void> enqueuePendingOp(
    Map<String, dynamic> op, {
    String? userId,
  }) async {
    try {
      final existing = await _loadPendingOps(userId: userId);
      existing.add(op);
      await _storage.write(
        key: 'tabby_pending_ops_${_scope(userId)}',
        value: jsonEncode(existing),
      );
    } catch (e) {
      debugPrint('[TabbyLocalCache] enqueuePendingOp warning: $e');
    }
  }

  /// Returns all pending offline operations in FIFO order.
  static Future<List<Map<String, dynamic>>> _loadPendingOps({
    String? userId,
  }) async {
    try {
      final raw =
          await _storage.read(key: 'tabby_pending_ops_${_scope(userId)}');
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Drains and returns all pending offline operations, clearing the queue.
  static Future<List<Map<String, dynamic>>> drainPendingOps({
    String? userId,
  }) async {
    final ops = await _loadPendingOps(userId: userId);
    if (ops.isNotEmpty) {
      await _storage.delete(key: 'tabby_pending_ops_${_scope(userId)}');
    }
    return ops;
  }

  /// Returns true if there are pending offline operations waiting to sync.
  static Future<bool> hasPendingOps({String? userId}) async {
    final ops = await _loadPendingOps(userId: userId);
    return ops.isNotEmpty;
  }
}
