import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabby/features/classroom/application/classroom_providers.dart';
import 'package:tabby/features/classroom/data/classroom_local_cache.dart';
import 'package:tabby/features/classroom/domain/classroom_models.dart';
import 'package:tabby/core/services/tabby_notification_service.dart';

ClassroomTask _task({
  String id = 'task-1',
  String courseId = 'course-1',
  DateTime? dueAt,
  ClassroomTaskState state = ClassroomTaskState.assigned,
}) {
  return ClassroomTask(
    id: id,
    googleTaskId: 'google-$id',
    userId: 'user-1',
    courseId: courseId,
    courseName: 'Computer Architecture',
    courseColorHex: '#00D09E',
    title: 'Read chapter one',
    description: 'Read the first chapter.',
    dueAt: dueAt,
    classroomLink: 'https://classroom.google.com/task/$id',
    state: state,
    syncedAt: DateTime(2026, 9, 17, 9),
  );
}

void main() {
  test('ClassroomTask.urgency returns every supported urgency window', () {
    final now = DateTime.now();

    expect(_task(dueAt: now.add(const Duration(minutes: 30))).urgency,
        TaskUrgency.veryUrgent);
    expect(_task(dueAt: now.add(const Duration(days: 1))).urgency,
        TaskUrgency.dueSoon);
    expect(
      _task(dueAt: DateTime(2026, 9, 17, 23, 59))
          .urgencyAt(DateTime(2026, 9, 17, 12)),
      TaskUrgency.dueToday,
    );
    expect(_task(dueAt: now.add(const Duration(days: 8))).urgency,
        TaskUrgency.upcoming);
    expect(
      _task(dueAt: now.subtract(const Duration(minutes: 1))).urgency,
      TaskUrgency.overdue,
    );
    expect(
      _task(
        dueAt: now.add(const Duration(days: 1)),
        state: ClassroomTaskState.turnedIn,
      ).urgency,
      TaskUrgency.done,
    );
  });

  test('ClassroomTask.isOverdue only applies to assigned past-due tasks', () {
    final past = DateTime.now().subtract(const Duration(minutes: 1));

    expect(_task(dueAt: past).isOverdue, isTrue);
    expect(
      _task(dueAt: past, state: ClassroomTaskState.turnedIn).isOverdue,
      isFalse,
    );
  });

  test('Classroom task alarm IDs are stable and unique per offset', () {
    final first = TabbyNotificationService.taskAlarmIdForTesting('task-1', 60);
    final same = TabbyNotificationService.taskAlarmIdForTesting('task-1', 60);
    final otherOffset =
        TabbyNotificationService.taskAlarmIdForTesting('task-1', 30);
    final otherTask =
        TabbyNotificationService.taskAlarmIdForTesting('task-2', 60);

    expect(same, first);
    expect(otherOffset, isNot(first));
    expect(otherTask, isNot(first));
  });

  test('ClassroomLocalCache task codec round-trips task fields', () {
    final task = _task(dueAt: DateTime(2026, 9, 20, 14, 30));

    final restored = ClassroomLocalCache.decodeTasks(
      ClassroomLocalCache.encodeTasks([task]),
    ).single;

    expect(restored, task);
  });

  test('ClassroomConnection round-trips its alarm settings', () {
    final connection = ClassroomConnection(
      userId: 'user-1',
      googleEmail: 'student@example.com',
      connectedAt: DateTime(2026, 9, 17, 8),
      lastSyncedAt: DateTime(2026, 9, 17, 9),
      isActive: true,
      alarm60mEnabled: true,
      alarm30mEnabled: false,
      alarm10mEnabled: true,
    );

    expect(ClassroomConnection.fromMap(connection.toMap()), connection);
  });

  test('filteredTasksProvider filters tasks by course ID', () {
    final container = ProviderContainer(
      overrides: [
        classroomTasksProvider.overrideWith(
          (ref) => ClassroomTasksNotifier(
            initialTasks: [
              _task(id: 'one', courseId: 'course-1'),
              _task(id: 'two', courseId: 'course-2'),
            ],
            loadInitialData: false,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(filteredTasksProvider('course-2')).map((t) => t.id),
        ['two']);
  });

  test('upcomingTasksPreviewProvider returns two tasks sorted by due date', () {
    final now = DateTime.now();
    final container = ProviderContainer(
      overrides: [
        classroomTasksProvider.overrideWith(
          (ref) => ClassroomTasksNotifier(
            initialTasks: [
              _task(id: 'later', dueAt: now.add(const Duration(days: 2))),
              _task(id: 'earlier', dueAt: now.add(const Duration(hours: 2))),
              _task(id: 'latest', dueAt: now.add(const Duration(days: 3))),
            ],
            loadInitialData: false,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(upcomingTasksPreviewProvider).map((t) => t.id),
      ['earlier', 'later'],
    );
  });

  test('tasksDueTodayCountProvider counts only assigned tasks today', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 23, 59);
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 9);
    final container = ProviderContainer(
      overrides: [
        classroomTasksProvider.overrideWith(
          (ref) => ClassroomTasksNotifier(
            initialTasks: [
              _task(id: 'today', dueAt: today),
              _task(id: 'tomorrow', dueAt: tomorrow),
              _task(
                id: 'done-today',
                dueAt: today,
                state: ClassroomTaskState.returned,
              ),
            ],
            loadInitialData: false,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(tasksDueTodayCountProvider), 1);
  });
}
