import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/config/supabase_config.dart';
import 'package:tabby/core/services/form_draft_store.dart';
import 'package:tabby/features/tabs/application/expense_changes.dart';
import 'package:tabby/features/tabs/data/mock_tabby_repository.dart';
import 'package:tabby/features/tabs/data/supabase_tabby_repository.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:tabby/features/tabs/presentation/expense_change_screen.dart';

class _Drafts extends FormDraftStore {
  final values = <String, Map<String, dynamic>>{};
  bool failWrite = false, failRemove = false;
  String keyFor(String owner, String purpose) => '$owner/$purpose';
  @override
  Future<Map<String, dynamic>?> read(String owner, String purpose) async =>
      values[keyFor(owner, purpose)];
  @override
  Future<void> write(
      String owner, String purpose, Map<String, dynamic> value) async {
    if (failWrite) throw StateError('storage');
    values[keyFor(owner, purpose)] = value;
  }

  @override
  Future<void> removeIf(
      String owner, String purpose, String field, Object expected) async {
    if (failRemove) throw StateError('storage');
    if (values[keyFor(owner, purpose)]?[field] == expected) {
      values.remove(keyFor(owner, purpose));
    }
  }
}

LedgerEntry entry() => LedgerEntry(
    id: 'expense',
    tabId: 'tab',
    title: 'Original dinner',
    category: ExpenseCategory.food,
    totalAmountCentavos: 10001,
    myShareCentavos: 5000,
    counterpartShareCentavos: 5001,
    paidByUserId: 'a',
    paidByName: 'A',
    date: DateTime(2026));

Map<String, dynamic> history(
        {String owner = 'a', bool applied = false, bool showRequest = false}) =>
    {
      'account_id': owner,
      'transaction_id': 'expense',
      'can_request': !applied,
      'changes': showRequest
          ? [
              {
                'id': 'change',
                'transaction_id': 'expense',
                'requested_by': 'a',
                'reviewer_id': 'b',
                'kind': 'correct',
                'new_total_centavos': 7001,
                'reason': 'Wrong total',
                'status': applied ? 'applied' : 'pending'
              }
            ]
          : [],
    };

ExpenseChanges _service(_Drafts store,
        Future<dynamic> Function(String, Map<String, dynamic>) rpc,
        {String owner = 'a',
        bool Function()? current,
        String Function()? operation}) =>
    ExpenseChanges(
        owner: owner,
        current: current ?? () => true,
        rpc: rpc,
        drafts: store,
        operationId: operation ?? () => 'operation');

Future<void> enterRequest(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.text('Reason'), 250,
      scrollable: find.byType(Scrollable).first);
  await tester.enterText(find.byType(TextField).first, '70.01');
  await tester.enterText(find.byType(TextField).last, 'Wrong total');
  await tester.ensureVisible(find.text('Request change'));
  await tester.tap(find.text('Request change'));
}

void main() {
  test('corrupt saved commands fail closed before reaching the form', () async {
    final store = _Drafts();
    store.values['a/expense-change:expense'] = {
      'operation_id': 'saved',
      'command': {
        'p_transaction_id': 'expense',
        'p_kind': 'unknown',
        'p_reason': 7
      }
    };
    await expectLater(_service(store, (_, __) async => null).pending('expense'),
        throwsFormatException);
  });

  testWidgets('back protects unsubmitted edits and permits explicit discard',
      (tester) async {
    final s = _service(_Drafts(), (_, __) async => history());
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => ExpenseChangeScreen(
                                entry: entry(),
                                service: s,
                                refreshHistory: () async => true))),
                    child: const Text('Open changes'))))));
    await tester.tap(find.text('Open changes'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Reason'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(find.byType(TextField).last, 'Unsubmitted reason');
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Leave expense changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byType(ExpenseChangeScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave form'));
    await tester.pumpAndSettle();
    expect(find.text('Open changes'), findsOneWidget);
  });

  test('request is durable before RPC; failed storage prevents network writes',
      () async {
    final store = _Drafts()..failWrite = true;
    var calls = 0;
    final s = _service(store, (_, __) async {
      calls++;
      return 'change';
    });
    await expectLater(
        s.request('expense', kind: 'correct', newTotal: 7001, reason: 'Wrong'),
        throwsStateError);
    expect(calls, 0);
    store.failWrite = false;
    final ack = _service(store, (_, params) async {
      expect(params['p_expected_actor'], 'a');
      expect(store.values, isNotEmpty);
      return 'change';
    });
    expect(
        await ack.request('expense',
            kind: 'correct', newTotal: 7001, reason: 'Wrong'),
        'change');
    expect(store.values, isEmpty);
  });

  test(
      'response loss/restart retries exactly one saved payload; edits cannot replace it',
      () async {
    final store = _Drafts(), operations = <dynamic>[];
    final first = _service(store, (_, params) async {
      operations.add(params['p_operation_id']);
      throw StateError('response lost');
    });
    await expectLater(
        first.request('expense',
            kind: 'correct', newTotal: 7001, reason: 'Wrong'),
        throwsStateError);
    final restarted = _service(store, (_, params) async {
      operations.add(params['p_operation_id']);
      return 'change';
    }, operation: () => 'new-operation');
    await expectLater(
        restarted.request('expense',
            kind: 'correct', newTotal: 8001, reason: 'Wrong'),
        throwsStateError);
    expect(
        await restarted.request('expense',
            kind: 'correct', newTotal: 7001, reason: 'Wrong'),
        'change');
    expect(operations, ['operation', 'operation']);
  });

  test(
      'late session acknowledgment retains durable intent and rejects parallel work',
      () async {
    final store = _Drafts(), ack = Completer<dynamic>();
    var current = true;
    final s = _service(store, (_, __) => ack.future, current: () => current);
    final write = s.request('expense',
        kind: 'cancel', newTotal: null, reason: 'Duplicate');
    await Future<void>.delayed(Duration.zero);
    await expectLater(
        s.request('expense',
            kind: 'cancel', newTotal: null, reason: 'Duplicate'),
        throwsStateError);
    current = false;
    ack.complete('change');
    await expectLater(write, throwsStateError);
    expect(store.values, isNotEmpty);
  });

  test('acknowledged request is not reported failed when local cleanup fails',
      () async {
    final store = _Drafts()..failRemove = true;
    final s = _service(store, (_, __) async => 'change');
    expect(
        await s.request('expense',
            kind: 'cancel', newTotal: null, reason: 'Duplicate'),
        'change');
    expect(s.cleanupPending, isTrue);
    expect(store.values, isNotEmpty);
  });

  test(
      'history refuses foreign data and decisions require exact ID acknowledgment',
      () async {
    await expectLater(
        _service(_Drafts(), (_, __) async => history(owner: 'b'))
            .list('expense'),
        throwsFormatException);
    await expectLater(
        _service(_Drafts(), (_, __) async => 'different')
            .decide('change', accept: true),
        throwsFormatException);
    var accepted = true;
    await _service(_Drafts(), (_, params) async {
      accepted = params['p_accept'] as bool;
      return 'change';
    }).decide('change', accept: false);
    expect(accepted, isFalse);
  });

  testWidgets(
      'request form waits for server acknowledgment before claiming success',
      (tester) async {
    final ack = Completer<dynamic>();
    final s = _service(
        _Drafts(),
        (name, _) => name == 'list_expense_changes_v1'
            ? Future.value(history())
            : ack.future);
    await tester.pumpWidget(MaterialApp(
        home: ExpenseChangeScreen(
            entry: entry(), service: s, refreshHistory: () async => true)));
    await tester.pumpAndSettle();
    await enterRequest(tester);
    await tester.pump();
    expect(find.textContaining('Request recorded.'), findsNothing);
    ack.complete('change');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.textContaining('Request recorded.'), -250,
        scrollable: find.byType(Scrollable).first);
    expect(
        find.textContaining('balance changes only if the other person accepts'),
        findsOneWidget);
  });

  testWidgets(
      'reviewer confirmation targets exact request and refreshes only after acknowledgment',
      (tester) async {
    final ack = Completer<dynamic>();
    var applied = false, refreshes = 0, writes = 0;
    final s = _service(_Drafts(), (name, params) async {
      if (name == 'list_expense_changes_v1') {
        return history(owner: 'b', showRequest: true, applied: applied);
      }
      writes++;
      expect(params['p_change_id'], 'change');
      expect(params['p_expected_actor'], 'b');
      expect(params['p_accept'], isTrue);
      final id = await ack.future;
      applied = true;
      return id;
    }, owner: 'b');
    await tester.pumpWidget(MaterialApp(
        home: ExpenseChangeScreen(
            entry: entry(),
            service: s,
            refreshHistory: () async {
              refreshes++;
              return true;
            })));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Review and accept'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Review and accept'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    await tester.tap(find.text('Accept change'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(refreshes, 0);
    ack.complete('change');
    await tester.pumpAndSettle();
    expect(refreshes, 1);
    expect(find.text('Correction · applied'), findsOneWidget);
  });

  testWidgets('failed local save leaves form editable and makes no RPC write',
      (tester) async {
    final store = _Drafts()..failWrite = true;
    var writes = 0;
    final s = _service(store, (name, _) async {
      if (name == 'list_expense_changes_v1') return history();
      writes++;
      return 'change';
    });
    await tester.pumpWidget(MaterialApp(
        home: ExpenseChangeScreen(
            entry: entry(), service: s, refreshHistory: () async => true)));
    await tester.pumpAndSettle();
    await enterRequest(tester);
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(
        tester.widget<TextField>(find.byType(TextField).last).enabled, isTrue);
  });

  testWidgets('account switch hides every financial and draft field',
      (tester) async {
    var current = true;
    final s =
        _service(_Drafts(), (_, __) async => history(), current: () => current);
    await tester.pumpWidget(MaterialApp(
        home: ExpenseChangeScreen(
            entry: entry(), service: s, refreshHistory: () async => true)));
    await tester.pumpAndSettle();
    expect(find.text('Original dinner'), findsOneWidget);
    current = false;
    SupabaseConfig.sessionRevision.value++;
    await tester.pump();
    expect(find.text('Original dinner'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  test(
      'normal parser/cache/balance replay preserves original plus reversal and replacement',
      () {
    Map<String, dynamic> tx(
            String id, int total, String payer, int aShare, int bShare) =>
        {
          'id': id,
          'description': id,
          'total_amount_centavos': total,
          'status': 'acknowledged',
          'created_at': '2026-11-02T00:00:00Z',
          'category': 'food',
          'transaction_participants': [
            for (final who in ['a', 'b'])
              {
                'user_id': who,
                'participant_role': who == payer ? 'payer' : 'debtor',
                'share_amount_centavos': who == 'a' ? aShare : bShare
              }
          ],
        };
    final row = {
      'id': 'tab',
      'tab_type': 'individual',
      'user_a': 'a',
      'user_b': 'b',
      'tab_members': [
        for (final id in ['a', 'b'])
          {
            'user_id': id,
            'users': {'id': id, 'display_name': id}
          }
      ],
      'transactions': [
        tx('original', 10001, 'a', 5000, 5001),
        tx('reversal', 5001, 'b', 5001, 0),
        tx('replacement', 7001, 'a', 3501, 3500)
      ],
      'payments': <dynamic>[]
    };
    for (final user in ['a', 'b']) {
      final tab = SupabaseTabbyRepository.parseTabRow(row, user)!;
      final restored = BilateralTab.fromMap(tab.toMap());
      expect(restored.entries.map((e) => e.id).toSet(),
          {'original', 'reversal', 'replacement'});
      expect(MockTabbyRepository.calculateNetBalance(restored.entries, user),
          user == 'a' ? 3500 : -3500);
    }
  });
}
