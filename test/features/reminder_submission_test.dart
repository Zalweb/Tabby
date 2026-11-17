import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart' hide group;
import 'package:tabby/core/config/supabase_config.dart';
import 'package:tabby/core/services/reminder_submission_service.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/home/presentation/home_dashboard_screen.dart';
import 'due_reminders_test.dart' show groupBill, group, me, bob, carol;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  const command = {
    'tab_id': 't',
    'recipient_user_id': bob,
    'title': 'A reminder',
    'body': 'Review Tabby'
  };

  testWidgets('remind UI shows waiting and waits for accepted response',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final reply = Completer<String?>();
    final notifier = TabbyNotifier(
        loadInitialData: false,
        reminderSubmission:
            ReminderSubmissionService(send: (_, __) => reply.future));
    notifier.state = notifier.state.copyWith(tabs: [
      group([groupBill(me, bob)])
    ]);
    await notifier.refreshDueReminders();
    await tester.pumpWidget(ProviderScope(
        overrides: [tabbyProvider.overrideWith((ref) => notifier)],
        child: const MaterialApp(home: HomeDashboardScreen())));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Remind').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remind').first);
    await tester.pump();
    expect(find.text('Waiting for reminder acceptance…'), findsOneWidget);
    expect(find.text(ReminderSendResult.accepted.message), findsNothing);
    reply.complete('server-id');
    await tester.pumpAndSettle();
    expect(find.text(ReminderSendResult.accepted.message), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
      'lost response and restart reuse the original operation before clearing acknowledged intent',
      () async {
    final operations = <String>[];
    final first = ReminderSubmissionService(send: (id, _) async {
      operations.add(id);
      throw StateError('Response lost');
    });
    await expectLater(
        first.submit(me, command, current: () => true), throwsStateError);
    final next = ReminderSubmissionService(send: (id, _) async {
      operations.add(id);
      return 'notification';
    });
    expect(await next.submit(me, command, current: () => true), 'notification');
    expect(operations[0], operations[1]);
    await next.submit(me, command, current: () => true);
    expect(operations[2], isNot(operations[0]));
  });

  test('rapid repeated taps share one request and completion', () async {
    final reply = Completer<String?>();
    var requests = 0;
    final service = ReminderSubmissionService(send: (_, __) {
      requests++;
      return reply.future;
    });
    final first = service.submit(me, command, current: () => true);
    final second = service.submit(me, command, current: () => true);
    await Future<void>.delayed(Duration.zero);
    expect(requests, 1);
    reply.complete('accepted');
    expect(await first, 'accepted');
    expect(await second, 'accepted');
  });

  test(
      'provider records success only after acknowledgment and retains exact server ID',
      () async {
    final reply = Completer<String?>();
    final notifier = TabbyNotifier(
        loadInitialData: false,
        reminderSubmission:
            ReminderSubmissionService(send: (_, __) => reply.future));
    addTearDown(notifier.dispose);
    notifier.state = notifier.state.copyWith(tabs: [
      group([groupBill(me, bob)])
    ]);
    final request = notifier.sendGentleNudge(
        tabId: 't',
        recipientUserId: bob,
        friendName: 'Bob',
        amountCentavos: 5000);
    await Future<void>.delayed(Duration.zero);
    expect(notifier.state.activities, isEmpty);
    expect(notifier.state.emotionOverride, isNull);
    reply.complete('server-notification-and-activity-id');
    expect(await request, ReminderSendResult.accepted);
    expect(notifier.state.activities.single.id,
        'server-notification-and-activity-id');
    expect(notifier.state.activities.single.description,
        contains('sent friendly reminder'));
  });

  test(
      'offline/rejected request never records sent and uninvolved group member never reaches transport',
      () async {
    var requests = 0;
    final notifier = TabbyNotifier(
        loadInitialData: false,
        reminderSubmission: ReminderSubmissionService(send: (_, __) async {
          requests++;
          return null;
        }));
    addTearDown(notifier.dispose);
    notifier.state = notifier.state.copyWith(tabs: [
      group([groupBill(me, bob)])
    ]);
    expect(
        await notifier.sendGentleNudge(
            tabId: 't',
            recipientUserId: bob,
            friendName: 'Bob',
            amountCentavos: 5000),
        ReminderSendResult.failed);
    expect(notifier.state.activities, isEmpty);
    expect(
        await notifier.sendGentleNudge(
            tabId: 't',
            recipientUserId: carol,
            friendName: 'Carol',
            amountCentavos: 5000),
        ReminderSendResult.unavailable);
    expect(requests, 1);
  });

  test('old account acknowledgment cannot update a new session', () async {
    final reply = Completer<String?>();
    final entered = Completer<void>();
    final notifier = TabbyNotifier(
        loadInitialData: false,
        reminderSubmission: ReminderSubmissionService(send: (_, __) {
          entered.complete();
          return reply.future;
        }));
    addTearDown(notifier.dispose);
    addTearDown(() => SupabaseConfig.debugUserIdOverride = null);
    notifier.state = notifier.state.copyWith(tabs: [
      group([groupBill(me, bob)])
    ]);
    final request = notifier.sendGentleNudge(
        tabId: 't',
        recipientUserId: bob,
        friendName: 'Bob',
        amountCentavos: 5000);
    await entered.future;
    SupabaseConfig.debugUserIdOverride = 'new-account';
    reply.complete('accepted-for-old-account');
    expect(await request, ReminderSendResult.sessionChanged);
    expect(notifier.state.activities, isEmpty);
  });
}
