import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/models.dart';

/// Local offline cache manager for Tabby.
///
/// Persists tabs, activities, and reminders locally to prevent blank screens
/// or data loss when offline or during slow network handshakes.
class TabbyLocalCache {
  static const _storage = FlutterSecureStorage();
  static const _keyTabs = 'tabby_cached_tabs';
  static const _keyActivities = 'tabby_cached_activities';
  static const _keyReminders = 'tabby_cached_reminders';

  /// Saves tabs to local secure cache
  static Future<void> saveTabs(List<BilateralTab> tabs) async {
    try {
      final jsonList = tabs.map((t) => t.toMap()).toList();
      final jsonStr = jsonEncode(jsonList);
      await _storage.write(key: _keyTabs, value: jsonStr);
    } catch (e) {
      debugPrint('[TabbyLocalCache] saveTabs warning: $e');
    }
  }

  /// Loads cached tabs from local secure cache.
  /// Returns `null` if no cache exists or on read failure.
  static Future<List<BilateralTab>?> loadTabs() async {
    try {
      final raw = await _storage.read(key: _keyTabs);
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

  /// Saves activities to local secure cache
  static Future<void> saveActivities(List<TabbyActivity> activities) async {
    try {
      final jsonList = activities.map((a) => a.toMap()).toList();
      final jsonStr = jsonEncode(jsonList);
      await _storage.write(key: _keyActivities, value: jsonStr);
    } catch (e) {
      debugPrint('[TabbyLocalCache] saveActivities warning: $e');
    }
  }

  /// Loads cached activities from local secure cache.
  static Future<List<TabbyActivity>?> loadActivities() async {
    try {
      final raw = await _storage.read(key: _keyActivities);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => TabbyActivity.fromMap(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[TabbyLocalCache] loadActivities warning: $e');
      return null;
    }
  }

  /// Saves reminders to local secure cache
  static Future<void> saveReminders(List<UpcomingReminder> reminders) async {
    try {
      final jsonList = reminders.map((r) => r.toMap()).toList();
      final jsonStr = jsonEncode(jsonList);
      await _storage.write(key: _keyReminders, value: jsonStr);
    } catch (e) {
      debugPrint('[TabbyLocalCache] saveReminders warning: $e');
    }
  }

  /// Loads cached reminders from local secure cache.
  static Future<List<UpcomingReminder>?> loadReminders() async {
    try {
      final raw = await _storage.read(key: _keyReminders);
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

  /// Clears all local cache (e.g., on logout)
  static Future<void> clearCache() async {
    try {
      await _storage.delete(key: _keyTabs);
      await _storage.delete(key: _keyActivities);
      await _storage.delete(key: _keyReminders);
    } catch (e) {
      debugPrint('[TabbyLocalCache] clearCache warning: $e');
    }
  }
}
