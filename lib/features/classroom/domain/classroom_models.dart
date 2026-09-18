import 'package:flutter/foundation.dart';

enum ClassroomTaskState { assigned, turnedIn, returned }

enum TaskUrgency { upcoming, dueToday, dueSoon, veryUrgent, overdue, done }

String _readString(Map<String, dynamic> map, String camel, String snake) {
  final value = map[camel] ?? map[snake];
  return value is String ? value : '';
}

String? _readNullableString(
    Map<String, dynamic> map, String camel, String snake) {
  final value = map[camel] ?? map[snake];
  return value is String && value.isNotEmpty ? value : null;
}

DateTime? _readDate(Map<String, dynamic> map, String camel, String snake) {
  final value = map[camel] ?? map[snake];
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

bool _readBool(Map<String, dynamic> map, String camel, String snake,
    {bool fallback = false}) {
  final value = map[camel] ?? map[snake];
  return value is bool ? value : fallback;
}

@immutable
class ClassroomCourse {
  final String id;
  final String googleCourseId;
  final String userId;
  final String name;
  final String? section;
  final String colorHex;

  const ClassroomCourse({
    required this.id,
    required this.googleCourseId,
    required this.userId,
    required this.name,
    this.section,
    this.colorHex = '#00D09E',
  });

  ClassroomCourse copyWith({
    String? id,
    String? googleCourseId,
    String? userId,
    String? name,
    String? section,
    String? colorHex,
  }) {
    return ClassroomCourse(
      id: id ?? this.id,
      googleCourseId: googleCourseId ?? this.googleCourseId,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      section: section ?? this.section,
      colorHex: colorHex ?? this.colorHex,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'googleCourseId': googleCourseId,
        'userId': userId,
        'name': name,
        'section': section,
        'colorHex': colorHex,
      };

  factory ClassroomCourse.fromMap(Map<String, dynamic> map) {
    return ClassroomCourse(
      id: _readString(map, 'id', 'id'),
      googleCourseId: _readString(map, 'googleCourseId', 'google_course_id'),
      userId: _readString(map, 'userId', 'user_id'),
      name: _readString(map, 'name', 'name'),
      section: _readNullableString(map, 'section', 'section'),
      colorHex: _readString(map, 'colorHex', 'color_hex').isEmpty
          ? '#00D09E'
          : _readString(map, 'colorHex', 'color_hex'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ClassroomCourse &&
      other.id == id &&
      other.googleCourseId == googleCourseId &&
      other.userId == userId &&
      other.name == name &&
      other.section == section &&
      other.colorHex == colorHex;

  @override
  int get hashCode => Object.hash(
        id,
        googleCourseId,
        userId,
        name,
        section,
        colorHex,
      );
}

@immutable
class ClassroomTask {
  final String id;
  final String googleTaskId;
  final String userId;
  final String courseId;
  final String courseName;
  final String courseColorHex;
  final String title;
  final String? description;
  final DateTime? dueAt;
  final String? classroomLink;
  final ClassroomTaskState state;
  final bool notified60m;
  final bool notified30m;
  final bool notified10m;
  final DateTime syncedAt;

  const ClassroomTask({
    required this.id,
    required this.googleTaskId,
    required this.userId,
    required this.courseId,
    required this.courseName,
    required this.courseColorHex,
    required this.title,
    this.description,
    this.dueAt,
    this.classroomLink,
    this.state = ClassroomTaskState.assigned,
    this.notified60m = false,
    this.notified30m = false,
    this.notified10m = false,
    required this.syncedAt,
  });

  bool get hasDueDate => dueAt != null;

  bool get isOverdue =>
      dueAt != null &&
      dueAt!.isBefore(DateTime.now()) &&
      state == ClassroomTaskState.assigned;

  Duration? get timeUntilDue => dueAt?.difference(DateTime.now());

  TaskUrgency get urgency => urgencyAt(DateTime.now());

  TaskUrgency urgencyAt(DateTime now) {
    if (state != ClassroomTaskState.assigned) return TaskUrgency.done;
    if (dueAt == null) return TaskUrgency.upcoming;

    final due = dueAt!;
    final remaining = due.difference(now);
    if (remaining.isNegative) return TaskUrgency.overdue;
    if (remaining <= const Duration(hours: 1)) return TaskUrgency.veryUrgent;
    if (due.year == now.year && due.month == now.month && due.day == now.day) {
      return TaskUrgency.dueToday;
    }
    if (remaining <= const Duration(hours: 48)) return TaskUrgency.dueSoon;
    return TaskUrgency.upcoming;
  }

  ClassroomTask copyWith({
    String? id,
    String? googleTaskId,
    String? userId,
    String? courseId,
    String? courseName,
    String? courseColorHex,
    String? title,
    String? description,
    DateTime? dueAt,
    String? classroomLink,
    ClassroomTaskState? state,
    bool? notified60m,
    bool? notified30m,
    bool? notified10m,
    DateTime? syncedAt,
  }) {
    return ClassroomTask(
      id: id ?? this.id,
      googleTaskId: googleTaskId ?? this.googleTaskId,
      userId: userId ?? this.userId,
      courseId: courseId ?? this.courseId,
      courseName: courseName ?? this.courseName,
      courseColorHex: courseColorHex ?? this.courseColorHex,
      title: title ?? this.title,
      description: description ?? this.description,
      dueAt: dueAt ?? this.dueAt,
      classroomLink: classroomLink ?? this.classroomLink,
      state: state ?? this.state,
      notified60m: notified60m ?? this.notified60m,
      notified30m: notified30m ?? this.notified30m,
      notified10m: notified10m ?? this.notified10m,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'googleTaskId': googleTaskId,
        'userId': userId,
        'courseId': courseId,
        'courseName': courseName,
        'courseColorHex': courseColorHex,
        'title': title,
        'description': description,
        'dueAt': dueAt?.toIso8601String(),
        'classroomLink': classroomLink,
        'state': state.name,
        'notified60m': notified60m,
        'notified30m': notified30m,
        'notified10m': notified10m,
        'syncedAt': syncedAt.toIso8601String(),
      };

  factory ClassroomTask.fromMap(Map<String, dynamic> map) {
    final stateName = _readString(map, 'state', 'state');
    final state = ClassroomTaskState.values.firstWhere(
      (value) => value.name == stateName,
      orElse: () => ClassroomTaskState.assigned,
    );

    return ClassroomTask(
      id: _readString(map, 'id', 'id'),
      googleTaskId: _readString(map, 'googleTaskId', 'google_task_id'),
      userId: _readString(map, 'userId', 'user_id'),
      courseId: _readString(map, 'courseId', 'course_id'),
      courseName: _readString(map, 'courseName', 'course_name'),
      courseColorHex:
          _readString(map, 'courseColorHex', 'course_color_hex').isEmpty
              ? '#00D09E'
              : _readString(map, 'courseColorHex', 'course_color_hex'),
      title: _readString(map, 'title', 'title'),
      description: _readNullableString(map, 'description', 'description'),
      dueAt: _readDate(map, 'dueAt', 'due_at'),
      classroomLink:
          _readNullableString(map, 'classroomLink', 'classroom_link'),
      state: state,
      notified60m: _readBool(map, 'notified60m', 'notified_60m'),
      notified30m: _readBool(map, 'notified30m', 'notified_30m'),
      notified10m: _readBool(map, 'notified10m', 'notified_10m'),
      syncedAt: _readDate(map, 'syncedAt', 'synced_at') ?? DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ClassroomTask &&
      other.id == id &&
      other.googleTaskId == googleTaskId &&
      other.userId == userId &&
      other.courseId == courseId &&
      other.courseName == courseName &&
      other.courseColorHex == courseColorHex &&
      other.title == title &&
      other.description == description &&
      other.dueAt == dueAt &&
      other.classroomLink == classroomLink &&
      other.state == state &&
      other.notified60m == notified60m &&
      other.notified30m == notified30m &&
      other.notified10m == notified10m &&
      other.syncedAt == syncedAt;

  @override
  int get hashCode => Object.hashAll([
        id,
        googleTaskId,
        userId,
        courseId,
        courseName,
        courseColorHex,
        title,
        description,
        dueAt,
        classroomLink,
        state,
        notified60m,
        notified30m,
        notified10m,
        syncedAt,
      ]);
}

@immutable
class ClassroomAnnouncement {
  final String id;
  final String googleAnnounceId;
  final String userId;
  final String courseId;
  final String courseName;
  final String text;
  final DateTime postedAt;
  final bool isRead;

  const ClassroomAnnouncement({
    required this.id,
    required this.googleAnnounceId,
    required this.userId,
    required this.courseId,
    required this.courseName,
    required this.text,
    required this.postedAt,
    this.isRead = false,
  });

  ClassroomAnnouncement copyWith({
    String? id,
    String? googleAnnounceId,
    String? userId,
    String? courseId,
    String? courseName,
    String? text,
    DateTime? postedAt,
    bool? isRead,
  }) {
    return ClassroomAnnouncement(
      id: id ?? this.id,
      googleAnnounceId: googleAnnounceId ?? this.googleAnnounceId,
      userId: userId ?? this.userId,
      courseId: courseId ?? this.courseId,
      courseName: courseName ?? this.courseName,
      text: text ?? this.text,
      postedAt: postedAt ?? this.postedAt,
      isRead: isRead ?? this.isRead,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'googleAnnounceId': googleAnnounceId,
        'userId': userId,
        'courseId': courseId,
        'courseName': courseName,
        'text': text,
        'postedAt': postedAt.toIso8601String(),
        'isRead': isRead,
      };

  factory ClassroomAnnouncement.fromMap(Map<String, dynamic> map) {
    return ClassroomAnnouncement(
      id: _readString(map, 'id', 'id'),
      googleAnnounceId:
          _readString(map, 'googleAnnounceId', 'google_announce_id'),
      userId: _readString(map, 'userId', 'user_id'),
      courseId: _readString(map, 'courseId', 'course_id'),
      courseName: _readString(map, 'courseName', 'course_name'),
      text: _readString(map, 'text', 'text'),
      postedAt: _readDate(map, 'postedAt', 'posted_at') ?? DateTime.now(),
      isRead: _readBool(map, 'isRead', 'is_read'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ClassroomAnnouncement &&
      other.id == id &&
      other.googleAnnounceId == googleAnnounceId &&
      other.userId == userId &&
      other.courseId == courseId &&
      other.courseName == courseName &&
      other.text == text &&
      other.postedAt == postedAt &&
      other.isRead == isRead;

  @override
  int get hashCode => Object.hash(
        id,
        googleAnnounceId,
        userId,
        courseId,
        courseName,
        text,
        postedAt,
        isRead,
      );
}

@immutable
class ClassroomConnection {
  final String userId;
  final String googleEmail;
  final DateTime connectedAt;
  final DateTime? lastSyncedAt;
  final bool isActive;
  final bool alarm60mEnabled;
  final bool alarm30mEnabled;
  final bool alarm10mEnabled;

  const ClassroomConnection({
    required this.userId,
    required this.googleEmail,
    required this.connectedAt,
    this.lastSyncedAt,
    this.isActive = true,
    this.alarm60mEnabled = true,
    this.alarm30mEnabled = true,
    this.alarm10mEnabled = true,
  });

  ClassroomConnection copyWith({
    String? userId,
    String? googleEmail,
    DateTime? connectedAt,
    DateTime? lastSyncedAt,
    bool? isActive,
    bool? alarm60mEnabled,
    bool? alarm30mEnabled,
    bool? alarm10mEnabled,
  }) {
    return ClassroomConnection(
      userId: userId ?? this.userId,
      googleEmail: googleEmail ?? this.googleEmail,
      connectedAt: connectedAt ?? this.connectedAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      isActive: isActive ?? this.isActive,
      alarm60mEnabled: alarm60mEnabled ?? this.alarm60mEnabled,
      alarm30mEnabled: alarm30mEnabled ?? this.alarm30mEnabled,
      alarm10mEnabled: alarm10mEnabled ?? this.alarm10mEnabled,
    );
  }

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'googleEmail': googleEmail,
        'connectedAt': connectedAt.toIso8601String(),
        'lastSyncedAt': lastSyncedAt?.toIso8601String(),
        'isActive': isActive,
        'alarm60mEnabled': alarm60mEnabled,
        'alarm30mEnabled': alarm30mEnabled,
        'alarm10mEnabled': alarm10mEnabled,
      };

  factory ClassroomConnection.fromMap(Map<String, dynamic> map) {
    return ClassroomConnection(
      userId: _readString(map, 'userId', 'user_id'),
      googleEmail: _readString(map, 'googleEmail', 'google_email'),
      connectedAt:
          _readDate(map, 'connectedAt', 'connected_at') ?? DateTime.now(),
      lastSyncedAt: _readDate(map, 'lastSyncedAt', 'last_synced_at'),
      isActive: _readBool(map, 'isActive', 'is_active', fallback: true),
      alarm60mEnabled:
          _readBool(map, 'alarm60mEnabled', 'alarm_60m', fallback: true),
      alarm30mEnabled:
          _readBool(map, 'alarm30mEnabled', 'alarm_30m', fallback: true),
      alarm10mEnabled:
          _readBool(map, 'alarm10mEnabled', 'alarm_10m', fallback: true),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ClassroomConnection &&
      other.userId == userId &&
      other.googleEmail == googleEmail &&
      other.connectedAt == connectedAt &&
      other.lastSyncedAt == lastSyncedAt &&
      other.isActive == isActive &&
      other.alarm60mEnabled == alarm60mEnabled &&
      other.alarm30mEnabled == alarm30mEnabled &&
      other.alarm10mEnabled == alarm10mEnabled;

  @override
  int get hashCode => Object.hash(
        userId,
        googleEmail,
        connectedAt,
        lastSyncedAt,
        isActive,
        alarm60mEnabled,
        alarm30mEnabled,
        alarm10mEnabled,
      );
}
