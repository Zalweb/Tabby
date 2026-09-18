import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/services/tabby_notification_service.dart';
import '../data/classroom_local_cache.dart';
import '../data/classroom_repository.dart';
import '../domain/classroom_models.dart';

final classroomConnectionProvider =
    StateNotifierProvider<ClassroomConnectionNotifier, ClassroomConnection?>(
        (ref) {
  return ClassroomConnectionNotifier();
});

class ClassroomConnectionNotifier extends StateNotifier<ClassroomConnection?> {
  ClassroomConnectionNotifier({
    ClassroomRepository? repository,
    TabbyNotificationService? notificationService,
    bool loadInitialData = true,
  })  : _repository = repository ?? ClassroomRepository.instance,
        _notificationService =
            notificationService ?? TabbyNotificationService.instance,
        super(null) {
    if (loadInitialData) load();
  }

  final ClassroomRepository _repository;
  final TabbyNotificationService _notificationService;

  Future<void> load() async {
    if (!SupabaseConfig.isInitialized) return;
    final userId = SupabaseConfig.currentUserId;
    if (userId == null || userId.isEmpty) {
      if (mounted) state = null;
      return;
    }

    final cached = await ClassroomLocalCache.loadConnection(userId);
    if (mounted && cached != null) state = cached;

    if (SupabaseConfig.isInitialized) {
      final remote = await _repository.loadConnection(userId);
      if (mounted && remote != null) {
        state = remote;
        await ClassroomLocalCache.saveConnection(userId, remote);
      }
    }
  }

  Future<bool> connect() async {
    if (!SupabaseConfig.isInitialized) return false;
    final userId = SupabaseConfig.currentUserId;
    if (userId == null || userId.isEmpty) return false;

    final authClient = await _repository.requestClassroomAccess();
    if (authClient == null) return false;

    await _repository.initWithAuthClient(authClient);
    final courses = await _repository.fetchCourses(userId);
    final tasks = await _repository.fetchAllTasks(userId, courses);
    final now = DateTime.now();
    final connection = ClassroomConnection(
      userId: userId,
      googleEmail: _repository.authenticatedEmail ??
          SupabaseConfig.currentUser?.email ??
          'Google account',
      connectedAt: now,
      lastSyncedAt: now,
    );

    await _repository.saveConnection(connection);
    await _repository.upsertCourses(courses);
    await _repository.upsertTasks(tasks);
    await ClassroomLocalCache.saveConnection(userId, connection);
    await ClassroomLocalCache.saveCourses(userId, courses);
    await ClassroomLocalCache.saveTasks(userId, tasks);
    if (mounted) state = connection;

    await _scheduleAlarms(tasks, connection);
    return true;
  }

  Future<void> updateAlarmSettings({
    bool? alarm60mEnabled,
    bool? alarm30mEnabled,
    bool? alarm10mEnabled,
  }) async {
    final current = state;
    if (current == null) return;
    final updated = current.copyWith(
      alarm60mEnabled: alarm60mEnabled,
      alarm30mEnabled: alarm30mEnabled,
      alarm10mEnabled: alarm10mEnabled,
    );
    if (mounted) state = updated;
    await _repository.saveConnection(updated);
    await ClassroomLocalCache.saveConnection(updated.userId, updated);

    final tasks = await ClassroomLocalCache.loadTasks(updated.userId) ?? [];
    await _scheduleAlarms(tasks, updated);
  }

  Future<void> disconnect() async {
    final current = state;
    if (current == null) return;
    final tasks = await ClassroomLocalCache.loadTasks(current.userId) ?? [];
    for (final task in tasks) {
      await _notificationService.cancelTaskAlarms(task.googleTaskId);
    }
    await _repository.disconnect();
    await _repository.clearSyncedData(current.userId);
    await ClassroomLocalCache.clear(current.userId);
    if (mounted) state = null;
  }

  Future<void> _scheduleAlarms(
      List<ClassroomTask> tasks, ClassroomConnection connection) async {
    for (final task in tasks) {
      await _notificationService.scheduleTaskAlarms(
        task: task,
        alarm60mEnabled: connection.alarm60mEnabled,
        alarm30mEnabled: connection.alarm30mEnabled,
        alarm10mEnabled: connection.alarm10mEnabled,
      );
    }
  }
}

final classroomCoursesProvider =
    StateNotifierProvider<ClassroomCoursesNotifier, List<ClassroomCourse>>(
        (ref) {
  return ClassroomCoursesNotifier();
});

class ClassroomCoursesNotifier extends StateNotifier<List<ClassroomCourse>> {
  ClassroomCoursesNotifier({
    List<ClassroomCourse>? initialCourses,
    ClassroomRepository? repository,
    bool loadInitialData = true,
  })  : _repository = repository ?? ClassroomRepository.instance,
        super(initialCourses ?? const []) {
    if (loadInitialData) refresh();
  }

  final ClassroomRepository _repository;

  Future<void> refresh() async {
    if (!SupabaseConfig.isInitialized) return;
    final userId = SupabaseConfig.currentUserId;
    if (userId == null || userId.isEmpty) return;

    final cached = await ClassroomLocalCache.loadCourses(userId);
    if (mounted && cached != null) state = cached;
    if (!_repository.hasApiClient) return;

    final courses = await _repository.fetchCourses(userId);
    if (!mounted || courses.isEmpty) return;
    state = courses;
    await _repository.upsertCourses(courses);
    await ClassroomLocalCache.saveCourses(userId, courses);
  }

  void clear() {
    if (mounted) state = const [];
  }
}

final classroomTasksProvider =
    StateNotifierProvider<ClassroomTasksNotifier, List<ClassroomTask>>((ref) {
  return ClassroomTasksNotifier();
});

class ClassroomTasksNotifier extends StateNotifier<List<ClassroomTask>> {
  ClassroomTasksNotifier({
    List<ClassroomTask>? initialTasks,
    ClassroomRepository? repository,
    TabbyNotificationService? notificationService,
    bool loadInitialData = true,
  })  : _repository = repository ?? ClassroomRepository.instance,
        _notificationService =
            notificationService ?? TabbyNotificationService.instance,
        super(initialTasks ?? const []) {
    if (loadInitialData) refresh();
  }

  final ClassroomRepository _repository;
  final TabbyNotificationService _notificationService;

  Future<void> refresh({List<ClassroomCourse>? courses}) async {
    if (!SupabaseConfig.isInitialized) return;
    final userId = SupabaseConfig.currentUserId;
    if (userId == null || userId.isEmpty) return;

    final cached = await ClassroomLocalCache.loadTasks(userId);
    if (mounted && cached != null) state = cached;
    if (!_repository.hasApiClient) return;

    final effectiveCourses = courses ??
        await ClassroomLocalCache.loadCourses(userId) ??
        await _repository.fetchCourses(userId);
    final tasks = await _repository.fetchAllTasks(userId, effectiveCourses);
    if (!mounted) return;

    final previousIds = state.map((task) => task.googleTaskId).toSet();
    state = tasks;
    await _repository.upsertTasks(tasks);
    await ClassroomLocalCache.saveTasks(userId, tasks);

    final connection = await ClassroomLocalCache.loadConnection(userId);
    if (connection == null || !connection.isActive) return;
    for (final task in tasks) {
      if (!previousIds.contains(task.googleTaskId)) {
        await _notificationService.showNewTaskDetected(
          taskTitle: task.title,
          courseName: task.courseName,
          dueAt: task.dueAt,
          googleTaskId: task.googleTaskId,
        );
      }
      await _notificationService.scheduleTaskAlarms(
        task: task,
        alarm60mEnabled: connection.alarm60mEnabled,
        alarm30mEnabled: connection.alarm30mEnabled,
        alarm10mEnabled: connection.alarm10mEnabled,
      );
    }
  }

  Future<void> markDone(String taskId) async {
    final index = state.indexWhere((task) => task.id == taskId);
    if (index < 0) return;
    final task = state[index];
    final updated = task.copyWith(state: ClassroomTaskState.turnedIn);
    final tasks = List<ClassroomTask>.from(state)..[index] = updated;
    if (mounted) state = tasks;
    await _repository.markTaskDone(taskId);
    await _notificationService.cancelTaskAlarms(task.googleTaskId);
    await ClassroomLocalCache.saveTasks(task.userId, tasks);
  }

  void clear() {
    if (mounted) state = const [];
  }
}

final classroomAnnouncementsProvider = StateNotifierProvider<
    ClassroomAnnouncementsNotifier, List<ClassroomAnnouncement>>((ref) {
  return ClassroomAnnouncementsNotifier();
});

class ClassroomAnnouncementsNotifier
    extends StateNotifier<List<ClassroomAnnouncement>> {
  ClassroomAnnouncementsNotifier({
    List<ClassroomAnnouncement>? initialAnnouncements,
    ClassroomRepository? repository,
    bool loadInitialData = true,
  })  : _repository = repository ?? ClassroomRepository.instance,
        super(initialAnnouncements ?? const []) {
    if (loadInitialData) refresh();
  }

  final ClassroomRepository _repository;

  Future<void> refresh({List<ClassroomCourse>? courses}) async {
    if (!SupabaseConfig.isInitialized) return;
    final userId = SupabaseConfig.currentUserId;
    if (userId == null || userId.isEmpty || !_repository.hasApiClient) return;
    final effectiveCourses = courses ??
        await ClassroomLocalCache.loadCourses(userId) ??
        await _repository.fetchCourses(userId);
    final announcements = <ClassroomAnnouncement>[];
    for (final course in effectiveCourses) {
      final courseAnnouncements = await _repository.fetchAnnouncements(
        userId,
        course.googleCourseId,
      );
      announcements.addAll(courseAnnouncements.map(
        (announcement) => announcement.copyWith(
          courseId: course.id,
          courseName: course.name,
        ),
      ));
    }
    if (!mounted) return;
    state = announcements;
    await _repository.upsertAnnouncements(announcements);
  }

  Future<void> markRead(String announcementId) async {
    final index =
        state.indexWhere((announcement) => announcement.id == announcementId);
    if (index < 0) return;
    final updated = state[index].copyWith(isRead: true);
    final announcements = List<ClassroomAnnouncement>.from(state)
      ..[index] = updated;
    if (mounted) state = announcements;
    await _repository.markAnnouncementRead(announcementId);
  }

  void clear() {
    if (mounted) state = const [];
  }
}

final upcomingTasksPreviewProvider = Provider<List<ClassroomTask>>((ref) {
  final now = DateTime.now();
  final latest = now.add(const Duration(days: 7));
  final tasks = ref
      .watch(classroomTasksProvider)
      .where((task) =>
          task.state == ClassroomTaskState.assigned &&
          task.dueAt != null &&
          task.dueAt!.isBefore(latest))
      .toList()
    ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
  return tasks.take(2).toList();
});

final tasksDueTodayCountProvider = Provider<int>((ref) {
  final now = DateTime.now();
  return ref.watch(classroomTasksProvider).where((task) {
    final dueAt = task.dueAt;
    return task.state == ClassroomTaskState.assigned &&
        dueAt != null &&
        dueAt.year == now.year &&
        dueAt.month == now.month &&
        dueAt.day == now.day;
  }).length;
});

final filteredTasksProvider =
    Provider.family<List<ClassroomTask>, String?>((ref, courseId) {
  final tasks = ref.watch(classroomTasksProvider);
  if (courseId == null) return tasks;
  return tasks.where((task) => task.courseId == courseId).toList();
});
