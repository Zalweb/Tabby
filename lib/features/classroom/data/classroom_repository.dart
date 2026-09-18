import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/classroom/v1.dart' as classroom;
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../core/config/supabase_config.dart';
import '../domain/classroom_models.dart';

class ClassroomRepository {
  ClassroomRepository._();

  static final ClassroomRepository instance = ClassroomRepository._();

  static const List<String> classroomScopes = [
    'https://www.googleapis.com/auth/classroom.courses.readonly',
    'https://www.googleapis.com/auth/classroom.coursework.me.readonly',
    'https://www.googleapis.com/auth/classroom.announcements.readonly',
    'https://www.googleapis.com/auth/classroom.student-submissions.me.readonly',
  ];

  static const String _defaultWebClientId =
      '137141086000-p2o6c1hminjif8i5f739n3a6ils7ucmm.apps.googleusercontent.com';

  static const _courseColors = [
    '#00D09E',
    '#0068FF',
    '#F59E0B',
    '#8B5CF6',
    '#EF4444',
  ];

  classroom.ClassroomApi? _api;
  AuthClient? _authClient;
  String? _lastGoogleEmail;

  String? get authenticatedEmail => _lastGoogleEmail;
  bool get hasApiClient => _api != null;

  Future<void> initWithAuthClient(AuthClient authClient) async {
    _authClient?.close();
    _authClient = authClient;
    _api = classroom.ClassroomApi(authClient);
  }

  Future<void> disconnect() async {
    _api = null;
    _authClient?.close();
    _authClient = null;
    _lastGoogleEmail = null;
    try {
      await GoogleSignIn(scopes: classroomScopes).disconnect();
    } catch (e) {
      debugPrint('[ClassroomRepository] Google disconnect notice: $e');
    }
  }

  Future<AuthClient?> requestClassroomAccess() async {
    final googleSignIn = GoogleSignIn(
      scopes: classroomScopes,
      serverClientId: const String.fromEnvironment(
        'GOOGLE_WEB_CLIENT_ID',
        defaultValue: _defaultWebClientId,
      ),
    );

    try {
      final account =
          await googleSignIn.signInSilently() ?? await googleSignIn.signIn();
      if (account == null) return null;

      final authentication = await account.authentication;
      final accessToken = authentication.accessToken;
      if (accessToken == null || accessToken.isEmpty) return null;

      _lastGoogleEmail = account.email;
      return authenticatedClient(
        http.Client(),
        AccessCredentials(
          AccessToken(
            'Bearer',
            accessToken,
            DateTime.now().toUtc().add(const Duration(hours: 1)),
          ),
          null,
          classroomScopes,
          idToken: authentication.idToken,
        ),
      );
    } catch (e) {
      debugPrint('[ClassroomRepository] Classroom OAuth error: $e');
      return null;
    }
  }

  Future<List<ClassroomCourse>> fetchCourses(String userId) async {
    final api = _api;
    if (api == null) return [];

    try {
      final courses = <ClassroomCourse>[];
      String? pageToken;
      do {
        final response = await api.courses.list(
          courseStates: ['ACTIVE'],
          pageSize: 100,
          pageToken: pageToken,
        );
        for (final course in response.courses ?? const <classroom.Course>[]) {
          final googleCourseId = course.id?.trim() ?? '';
          final name = course.name?.trim() ?? '';
          if (googleCourseId.isEmpty || name.isEmpty) continue;
          final index = courses.length % _courseColors.length;
          courses.add(
            ClassroomCourse(
              id: _localId(userId, googleCourseId),
              googleCourseId: googleCourseId,
              userId: userId,
              name: name,
              section: course.section,
              colorHex: _courseColors[index],
            ),
          );
        }
        pageToken = response.nextPageToken;
      } while (pageToken != null && pageToken.isNotEmpty);
      return courses;
    } catch (e) {
      debugPrint('[ClassroomRepository] fetchCourses error: $e');
      return [];
    }
  }

  Future<List<ClassroomTask>> fetchTasks(
      String userId, String googleCourseId) async {
    final course = ClassroomCourse(
      id: _localId(userId, googleCourseId),
      googleCourseId: googleCourseId,
      userId: userId,
      name: googleCourseId,
      colorHex: _courseColors.first,
    );
    return _fetchTasksForCourse(userId, course);
  }

  Future<List<ClassroomTask>> fetchAllTasks(
      String userId, List<ClassroomCourse> courses) async {
    final results = <ClassroomTask>[];
    for (final course in courses) {
      results.addAll(await _fetchTasksForCourse(userId, course));
    }
    return results;
  }

  Future<List<ClassroomTask>> _fetchTasksForCourse(
      String userId, ClassroomCourse course) async {
    final api = _api;
    if (api == null) return [];

    try {
      final tasks = <ClassroomTask>[];
      String? pageToken;
      do {
        final response = await api.courses.courseWork.list(
          course.googleCourseId,
          courseWorkStates: ['PUBLISHED'],
          orderBy: 'dueDate asc',
          pageSize: 100,
          pageToken: pageToken,
        );
        for (final work
            in response.courseWork ?? const <classroom.CourseWork>[]) {
          final googleTaskId = work.id?.trim() ?? '';
          final dueAt = _dueAt(work);
          if (googleTaskId.isEmpty) continue;

          final state =
              await _fetchTaskState(course.googleCourseId, googleTaskId);
          tasks.add(
            ClassroomTask(
              id: _localId(userId, '$course.googleCourseId:$googleTaskId'),
              googleTaskId: googleTaskId,
              userId: userId,
              courseId: course.id,
              courseName: course.name,
              courseColorHex: course.colorHex,
              title: work.title?.trim().isNotEmpty == true
                  ? work.title!.trim()
                  : 'Untitled assignment',
              description: work.description,
              dueAt: dueAt,
              classroomLink: work.alternateLink,
              state: state,
              syncedAt: DateTime.now(),
            ),
          );
        }
        pageToken = response.nextPageToken;
      } while (pageToken != null && pageToken.isNotEmpty);
      return tasks;
    } catch (e) {
      debugPrint('[ClassroomRepository] fetchTasks error: $e');
      return [];
    }
  }

  Future<ClassroomTaskState> _fetchTaskState(
      String googleCourseId, String googleTaskId) async {
    final api = _api;
    if (api == null) return ClassroomTaskState.assigned;

    try {
      final response = await api.courses.courseWork.studentSubmissions.list(
        googleCourseId,
        googleTaskId,
        userId: 'me',
        pageSize: 1,
      );
      final submissions = response.studentSubmissions;
      final state = submissions == null || submissions.isEmpty
          ? null
          : submissions.first.state;
      switch (state) {
        case 'RETURNED':
          return ClassroomTaskState.returned;
        case 'TURNED_IN':
          return ClassroomTaskState.turnedIn;
        default:
          return ClassroomTaskState.assigned;
      }
    } catch (e) {
      debugPrint('[ClassroomRepository] fetchTaskState error: $e');
      return ClassroomTaskState.assigned;
    }
  }

  Future<List<ClassroomAnnouncement>> fetchAnnouncements(
      String userId, String googleCourseId) async {
    final api = _api;
    if (api == null) return [];

    try {
      final announcements = <ClassroomAnnouncement>[];
      String? pageToken;
      do {
        final response = await api.courses.announcements.list(
          googleCourseId,
          announcementStates: ['PUBLISHED'],
          orderBy: 'updateTime desc',
          pageSize: 100,
          pageToken: pageToken,
        );
        for (final announcement
            in response.announcements ?? const <classroom.Announcement>[]) {
          final googleId = announcement.id?.trim() ?? '';
          if (googleId.isEmpty) continue;
          announcements.add(
            ClassroomAnnouncement(
              id: _localId(userId, 'announcement:$googleId'),
              googleAnnounceId: googleId,
              userId: userId,
              courseId: _localId(userId, googleCourseId),
              courseName: googleCourseId,
              text: announcement.text?.trim() ?? '',
              postedAt: DateTime.tryParse(announcement.creationTime ?? '') ??
                  DateTime.now(),
            ),
          );
        }
        pageToken = response.nextPageToken;
      } while (pageToken != null && pageToken.isNotEmpty);
      return announcements;
    } catch (e) {
      debugPrint('[ClassroomRepository] fetchAnnouncements error: $e');
      return [];
    }
  }

  Future<void> saveConnection(ClassroomConnection connection) async {
    if (!_isCurrentUser(connection.userId)) return;
    try {
      await SupabaseConfig.client.from('classroom_connections').upsert({
        'user_id': connection.userId,
        'google_email': connection.googleEmail,
        'connected_at': connection.connectedAt.toIso8601String(),
        'last_synced_at': connection.lastSyncedAt?.toIso8601String(),
        'is_active': connection.isActive,
        'alarm_60m': connection.alarm60mEnabled,
        'alarm_30m': connection.alarm30mEnabled,
        'alarm_10m': connection.alarm10mEnabled,
      }, onConflict: 'user_id');
    } catch (e) {
      debugPrint('[ClassroomRepository] saveConnection error: $e');
    }
  }

  Future<ClassroomConnection?> loadConnection(String userId) async {
    if (!_isCurrentUser(userId)) return null;
    try {
      final row = await SupabaseConfig.client
          .from('classroom_connections')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      return row == null ? null : ClassroomConnection.fromMap(row);
    } catch (e) {
      debugPrint('[ClassroomRepository] loadConnection error: $e');
      return null;
    }
  }

  Future<void> upsertCourses(List<ClassroomCourse> courses) async {
    if (courses.isEmpty || !_isCurrentUser(courses.first.userId)) return;
    try {
      await SupabaseConfig.client.from('classroom_courses').upsert(
            courses
                .map((course) => {
                      'id': course.id,
                      'user_id': course.userId,
                      'google_course_id': course.googleCourseId,
                      'name': course.name,
                      'section': course.section,
                      'color_hex': course.colorHex,
                    })
                .toList(),
            onConflict: 'user_id,google_course_id',
          );
    } catch (e) {
      debugPrint('[ClassroomRepository] upsertCourses error: $e');
    }
  }

  Future<void> upsertTasks(List<ClassroomTask> tasks) async {
    if (tasks.isEmpty || !_isCurrentUser(tasks.first.userId)) return;
    try {
      await SupabaseConfig.client.from('classroom_tasks').upsert(
            tasks
                .map((task) => {
                      'id': task.id,
                      'user_id': task.userId,
                      'google_task_id': task.googleTaskId,
                      'course_id': task.courseId,
                      'course_name': task.courseName,
                      'course_color_hex': task.courseColorHex,
                      'title': task.title,
                      'description': task.description,
                      'due_at': task.dueAt?.toIso8601String(),
                      'classroom_link': task.classroomLink,
                      'state': task.state.name,
                      'notified_60m': task.notified60m,
                      'notified_30m': task.notified30m,
                      'notified_10m': task.notified10m,
                      'synced_at': task.syncedAt.toIso8601String(),
                    })
                .toList(),
            onConflict: 'user_id,google_task_id',
          );
    } catch (e) {
      debugPrint('[ClassroomRepository] upsertTasks error: $e');
    }
  }

  Future<void> upsertAnnouncements(
      List<ClassroomAnnouncement> announcements) async {
    if (announcements.isEmpty || !_isCurrentUser(announcements.first.userId)) {
      return;
    }
    try {
      await SupabaseConfig.client.from('classroom_announcements').upsert(
            announcements
                .map((announcement) => {
                      'id': announcement.id,
                      'user_id': announcement.userId,
                      'google_announce_id': announcement.googleAnnounceId,
                      'course_id': announcement.courseId,
                      'course_name': announcement.courseName,
                      'text': announcement.text,
                      'posted_at': announcement.postedAt.toIso8601String(),
                      'is_read': announcement.isRead,
                    })
                .toList(),
            onConflict: 'user_id,google_announce_id',
          );
    } catch (e) {
      debugPrint('[ClassroomRepository] upsertAnnouncements error: $e');
    }
  }

  Future<void> markTaskDone(String taskId) async {
    if (!SupabaseConfig.isInitialized) return;
    final userId = SupabaseConfig.currentUserId;
    if (userId == null) return;
    try {
      await SupabaseConfig.client
          .from('classroom_tasks')
          .update({'state': ClassroomTaskState.turnedIn.name})
          .eq('id', taskId)
          .eq('user_id', userId);
    } catch (e) {
      debugPrint('[ClassroomRepository] markTaskDone error: $e');
    }
  }

  Future<void> markAnnouncementRead(String announcementId) async {
    if (!SupabaseConfig.isInitialized) return;
    final userId = SupabaseConfig.currentUserId;
    if (userId == null) return;
    try {
      await SupabaseConfig.client
          .from('classroom_announcements')
          .update({'is_read': true})
          .eq('id', announcementId)
          .eq('user_id', userId);
    } catch (e) {
      debugPrint('[ClassroomRepository] markAnnouncementRead error: $e');
    }
  }

  Future<void> setTaskNotified(String taskId,
      {bool? m60, bool? m30, bool? m10}) async {
    if (!SupabaseConfig.isInitialized) return;
    final userId = SupabaseConfig.currentUserId;
    if (userId == null) return;
    final updates = <String, dynamic>{
      if (m60 != null) 'notified_60m': m60,
      if (m30 != null) 'notified_30m': m30,
      if (m10 != null) 'notified_10m': m10,
    };
    if (updates.isEmpty) return;
    try {
      await SupabaseConfig.client
          .from('classroom_tasks')
          .update(updates)
          .eq('id', taskId)
          .eq('user_id', userId);
    } catch (e) {
      debugPrint('[ClassroomRepository] setTaskNotified error: $e');
    }
  }

  Future<void> clearSyncedData(String userId) async {
    if (!_isCurrentUser(userId)) return;
    try {
      await SupabaseConfig.client
          .from('classroom_announcements')
          .delete()
          .eq('user_id', userId);
      await SupabaseConfig.client
          .from('classroom_tasks')
          .delete()
          .eq('user_id', userId);
      await SupabaseConfig.client
          .from('classroom_courses')
          .delete()
          .eq('user_id', userId);
      await SupabaseConfig.client
          .from('classroom_connections')
          .delete()
          .eq('user_id', userId);
    } catch (e) {
      debugPrint('[ClassroomRepository] clearSyncedData error: $e');
    }
  }

  static String _localId(String userId, String googleId) =>
      const Uuid().v5(Namespace.url.value, '$userId:$googleId');

  static DateTime? _dueAt(classroom.CourseWork work) {
    final date = work.dueDate;
    if (date?.year == null || date?.month == null || date?.day == null) {
      return null;
    }
    final time = work.dueTime;
    return DateTime.utc(
      date!.year!,
      date.month!,
      date.day!,
      time?.hours ?? 23,
      time?.minutes ?? 59,
      time?.seconds ?? 59,
    ).toLocal();
  }

  static bool _isCurrentUser(String userId) =>
      SupabaseConfig.isInitialized && SupabaseConfig.currentUserId == userId;
}
