import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/config/supabase_config.dart';
import '../domain/classroom_models.dart';

class ClassroomLocalCache {
  ClassroomLocalCache._();

  static const _storage = FlutterSecureStorage();

  static String _scope(String userId) {
    final normalized = userId.trim();
    if (normalized.isNotEmpty) {
      return normalized.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    }
    return SupabaseConfig.isInitialized
        ? (SupabaseConfig.currentUserId ?? 'unauthenticated')
        : 'offline';
  }

  static String _key(String type, String userId) =>
      'tabby_classroom_${type}_${_scope(userId)}';

  static String encodeTasks(List<ClassroomTask> tasks) =>
      jsonEncode(tasks.map((task) => task.toMap()).toList());

  static List<ClassroomTask> decodeTasks(String raw) {
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => ClassroomTask.fromMap(
            Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
        .toList();
  }

  static Future<void> saveTasks(
      String userId, List<ClassroomTask> tasks) async {
    try {
      await _storage.write(
          key: _key('tasks', userId), value: encodeTasks(tasks));
    } catch (e) {
      debugPrint('[ClassroomLocalCache] saveTasks warning: $e');
    }
  }

  static Future<List<ClassroomTask>?> loadTasks(String userId) async {
    try {
      final raw = await _storage.read(key: _key('tasks', userId));
      return raw == null || raw.isEmpty ? null : decodeTasks(raw);
    } catch (e) {
      debugPrint('[ClassroomLocalCache] loadTasks warning: $e');
      return null;
    }
  }

  static Future<void> saveCourses(
      String userId, List<ClassroomCourse> courses) async {
    try {
      await _storage.write(
        key: _key('courses', userId),
        value: jsonEncode(courses.map((course) => course.toMap()).toList()),
      );
    } catch (e) {
      debugPrint('[ClassroomLocalCache] saveCourses warning: $e');
    }
  }

  static Future<List<ClassroomCourse>?> loadCourses(String userId) async {
    try {
      final raw = await _storage.read(key: _key('courses', userId));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => ClassroomCourse.fromMap(
              Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
          .toList();
    } catch (e) {
      debugPrint('[ClassroomLocalCache] loadCourses warning: $e');
      return null;
    }
  }

  static Future<void> saveConnection(
      String userId, ClassroomConnection? connection) async {
    try {
      final key = _key('connection', userId);
      if (connection == null) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: jsonEncode(connection.toMap()));
      }
    } catch (e) {
      debugPrint('[ClassroomLocalCache] saveConnection warning: $e');
    }
  }

  static Future<ClassroomConnection?> loadConnection(String userId) async {
    try {
      final raw = await _storage.read(key: _key('connection', userId));
      if (raw == null || raw.isEmpty) return null;
      return ClassroomConnection.fromMap(
          Map<String, dynamic>.from(jsonDecode(raw) as Map<dynamic, dynamic>));
    } catch (e) {
      debugPrint('[ClassroomLocalCache] loadConnection warning: $e');
      return null;
    }
  }

  static Future<void> clear(String userId) async {
    try {
      await Future.wait([
        _storage.delete(key: _key('tasks', userId)),
        _storage.delete(key: _key('courses', userId)),
        _storage.delete(key: _key('connection', userId)),
      ]);
    } catch (e) {
      debugPrint('[ClassroomLocalCache] clear warning: $e');
    }
  }
}
