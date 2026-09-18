import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/config/app_state.dart';
import 'package:tabby/core/router/app_router.dart';
import 'package:tabby/features/classroom/application/classroom_providers.dart';
import 'package:tabby/features/classroom/domain/classroom_models.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/main.dart';

ClassroomTask _createTask({
  required String id,
  required String title,
  required String courseName,
  DateTime? dueAt,
  ClassroomTaskState state = ClassroomTaskState.assigned,
}) {
  return ClassroomTask(
    id: id,
    googleTaskId: 'g-$id',
    userId: 'user-1',
    courseId: 'course-1',
    courseName: courseName,
    courseColorHex: '#00D09E',
    title: title,
    description: 'Task description for $title',
    dueAt: dueAt,
    state: state,
    syncedAt: DateTime(2026, 9, 18, 9),
  );
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets(
      'Upcoming & Reminders on Home Dashboard includes Google Classroom tasks with due date',
      (tester) async {
    AppState.isAuthenticated.value = true;
    AppState.hasSeenOnboarding.value = true;
    appRouter.go('/home');

    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final now = DateTime.now();
    final taskWithDue = _createTask(
      id: 'task-due-soon',
      title: 'Math Assignment 1',
      courseName: 'Calculus I',
      dueAt: now.add(const Duration(hours: 3)),
    );
    final taskOverdue = _createTask(
      id: 'task-overdue',
      title: 'History Essay',
      courseName: 'World History',
      dueAt: now.subtract(const Duration(hours: 2)),
    );
    final taskNoDue = _createTask(
      id: 'task-no-due',
      title: 'Optional Reading',
      courseName: 'Literature',
      dueAt: null,
    );

    final connection = ClassroomConnection(
      userId: 'user-1',
      googleEmail: 'frienzalsumalpong@gmail.com',
      connectedAt: DateTime.now(),
      lastSyncedAt: DateTime.now(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tabbyProvider.overrideWith(
            (_) => TabbyNotifier(loadInitialData: false),
          ),
          classroomConnectionProvider.overrideWith(
            (_) => ClassroomConnectionNotifier(
              loadInitialData: false,
            )..state = connection,
          ),
          classroomTasksProvider.overrideWith(
            (_) => ClassroomTasksNotifier(
              initialTasks: [taskWithDue, taskOverdue, taskNoDue],
              loadInitialData: false,
            ),
          ),
        ],
        child: const TabbyApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Verify Upcoming & Reminders header exists
    expect(find.text('Upcoming & Reminders'), findsOneWidget);

    // 2. Tasks with due dates (2 items) appear in the list, task without due date does NOT appear
    expect(find.text('Math Assignment 1'), findsOneWidget);
    expect(find.text('Calculus I'), findsOneWidget);
    expect(find.text('History Essay'), findsOneWidget);
    expect(find.text('World History'), findsOneWidget);
    expect(find.text('Optional Reading'), findsNothing);

    // 3. Check items count in header (2 items)
    expect(find.text('2 items'), findsOneWidget);

    // 4. Overdue task displays 'Past due date'
    expect(find.text('Past due date'), findsOneWidget);

    // 5. Tapping on a classroom reminder navigates to /tasks
    await tester.tap(find.text('Math Assignment 1'));
    await tester.pumpAndSettle();

    expect(find.text('Your Tasks'), findsOneWidget);
  });

  testWidgets(
      'Upcoming & Reminders shows empty state when no dues and no classroom tasks with due date exist',
      (tester) async {
    AppState.isAuthenticated.value = true;
    AppState.hasSeenOnboarding.value = true;
    appRouter.go('/home');

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tabbyProvider.overrideWith(
            (_) => TabbyNotifier(loadInitialData: false),
          ),
          classroomTasksProvider.overrideWith(
            (_) => ClassroomTasksNotifier(
              initialTasks: [],
              loadInitialData: false,
            ),
          ),
        ],
        child: const TabbyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Upcoming & Reminders'), findsOneWidget);
    expect(find.text('No pending dues. All caught up!'), findsOneWidget);
  });
}
