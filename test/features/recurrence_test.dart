import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as data;
import 'package:timezone/timezone.dart' as tz;
import 'package:tabby/features/tabs/domain/recurrence.dart';
import 'package:tabby/features/tabs/domain/custom_split.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:tabby/features/tabs/data/m2_command_queue.dart';
import 'package:tabby/features/tabs/data/m2_queries.dart';
import 'package:tabby/features/tabs/data/tabby_local_cache.dart';
import 'package:tabby/features/tabs/application/m2_saved_action.dart';
import 'package:tabby/features/tabs/presentation/recurrence_screen.dart';

const owner = '00000000-0000-4000-8000-000000000001',
    peer = '00000000-0000-4000-8000-000000000002';
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('monthly dates clamp from the original anchor without drift', () {
    final schedule = RecurrenceSchedule(
      anchor: RecurrenceSchedule.date('2028-01-31'),
      timeZone: 'Asia/Manila',
      unit: RecurrenceUnit.monthly,
    );
    expect(RecurrenceSchedule.label(schedule.occurrence(1)), '2028-02-29');
    expect(RecurrenceSchedule.label(schedule.occurrence(2)), '2028-03-31');
    expect(() => RecurrenceSchedule.date('2028-02-30'), throwsFormatException);
    expect(() => schedule.occurrence(-1), throwsFormatException);
  });
  test(
    'daily timezone schedule crosses DST as a calendar day, not 24 hours',
    () {
      data.initializeTimeZones();
      final schedule = RecurrenceSchedule(
        anchor: RecurrenceSchedule.date('2026-03-08'),
        timeZone: 'America/New_York',
        unit: RecurrenceUnit.daily,
      );
      expect(
        schedule
            .dueUtc(1, tz.getLocation('America/New_York'))
            .difference(schedule.dueUtc(0, tz.getLocation('America/New_York')))
            .inHours,
        23,
      );
      expect(() => schedule.dueUtc(0, tz.UTC), throwsFormatException);
    },
  );
  test('frozen control request survives reopen and rejects changed decisions or account scope', () async {
    var current = true;
    final queue = M2CommandQueue(
      actor: owner,
      current: () => current,
      wake: () async {},
    );
    final action = M2SavedAction(
      queue: queue,
      purpose: 'rule:fixture',
      scope: const {'rule_id': 'rule'},
    );
    final command = {
      'action': 'pause',
      'rule_id': 'rule',
      'expected_revision': 1,
    };
    expect(
      (await action.send('change_recurrence_v1', command)).confirmed,
      isFalse,
    );
    final first = (await TabbyLocalCache.loadPendingOps(userId: owner))
        .single['operation_id'];
    final reopened = M2SavedAction(
      queue: queue,
      purpose: 'rule:fixture',
      scope: const {'rule_id': 'rule'},
    );
    await reopened.restore();
    await reopened.retry();
    expect(
      (await TabbyLocalCache.loadPendingOps(userId: owner))
          .single['operation_id'],
      first,
    );
    await expectLater(
      reopened.send('change_recurrence_v1', {...command, 'action': 'end'}),
      throwsStateError,
    );
    await expectLater(
      reopened.send('change_recurrence_v1', {...command, 'rule_id': 'other'}),
      throwsStateError,
    );
    current = false;
    await expectLater(reopened.retry(), throwsStateError);
  });
  test('late and foreign read responses are never applied', () async {
    var current = true;
    final pending = Completer<dynamic>();
    final queries = M2Queries(
      actor: owner,
      current: () => current,
      rpc: (_, __) => pending.future,
    );
    final read = queries.read(
      'list_recurrences_v1',
      {'p_tab_id': 'tab'},
      scope: const {'tab_id': 'tab'},
    );
    current = false;
    pending.complete({'account_id': owner, 'tab_id': 'tab', 'records': []});
    await expectLater(read, throwsStateError);
    final wrong = M2Queries(
      actor: owner,
      current: () => true,
      rpc: (_, __) async => {'account_id': peer},
    );
    await expectLater(
      wrong.read('list_recurrences_v1', {}),
      throwsFormatException,
    );
    await expectLater(
      wrong.read('change_recurrence_v1', {}),
      throwsUnsupportedError,
    );
  });
  testWidgets(
    'rule editor saves a durable calendar command and never claims offline completion',
    (tester) async {
      final template =
          CustomSplit(
            baseShares: {
              const PartyRef(kind: PartyKind.user, id: owner): 5000,
              const PartyRef(kind: PartyKind.user, id: peer): 5001,
            },
          ).toCommand(
            actor: owner,
            tabId: 'tab',
            payer: const PartyRef(kind: PartyKind.user, id: owner),
            description: 'Rent fixture',
          );
      final queue = M2CommandQueue(
        actor: owner,
        current: () => true,
        wake: () async {},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: RecurrenceEditor(
            tabId: 'tab',
            template: template,
            queue: queue,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Save repeating expense'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save repeating expense'));
      await tester.pumpAndSettle();
      expect(find.text('Saved on this device. Sync pending.'), findsOneWidget);
      final op = (await TabbyLocalCache.loadPendingOps(userId: owner)).single;
      expect(op['m2_command']['timezone'], 'Asia/Manila');
      expect(op['m2_command']['unit'], 'monthly');
      expect(op['m2_command']['template']['p_total_amount_centavos'], 10001);
      expect(find.text('Saved by the server.'), findsNothing);
      final originalRule = op['m2_command']['rule_id'];
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          home: RecurrenceEditor(
            tabId: 'tab',
            template: template,
            queue: queue,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Retry saved request'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Retry saved request'));
      await tester.pumpAndSettle();
      final reopened = (await TabbyLocalCache.loadPendingOps(userId: owner))
          .single;
      expect(reopened['operation_id'], op['operation_id']);
      expect(reopened['m2_command']['rule_id'], originalRule);
    },
  );
}
