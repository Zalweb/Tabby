import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/tabs/data/m2_command_queue.dart';
import 'package:tabby/features/tabs/data/m2_queries.dart';
import 'package:tabby/features/tabs/data/tabby_local_cache.dart';
import 'package:tabby/features/tabs/presentation/expense_review_screen.dart';

const owner = '00000000-0000-4000-8000-000000000001',
    peer = '00000000-0000-4000-8000-000000000002',
    expense = '00000000-0000-4000-8000-000000000003';
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  M2CommandQueue queue() =>
      M2CommandQueue(actor: peer, current: () => true, wake: () async {});
  Future<void> confirm(WidgetTester tester) async {
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Confirm request'));
    await tester.tap(find.text('Confirm request'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'acknowledgment requires consent and offline save never reports counterpart acceptance',
    (tester) async {
      final q = queue();
      Widget screen() => MaterialApp(
        home: ExpenseReviewAction(
          transactionId: expense,
          queue: q,
          action: 'acknowledge',
          summary: 'Recorded dinner: PHP 100.01',
        ),
      );
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm request'),
            )
            .onPressed,
        isNull,
      );
      await confirm(tester);
      expect(find.text('Saved on this device. Sync pending.'), findsOneWidget);
      final first = (await TabbyLocalCache.loadPendingOps(userId: peer)).single;
      expect(first['m2_command']['action'], 'acknowledge');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry saved review request'));
      await tester.pumpAndSettle();
      expect(
        (await TabbyLocalCache.loadPendingOps(userId: peer))
            .single['operation_id'],
        first['operation_id'],
      );
      expect(find.textContaining('Saved by the server.'), findsNothing);
    },
  );
  testWidgets(
    'proposal freezes integer amount and reason; reopened fields cannot replace uncertain intent',
    (tester) async {
      final q = queue();
      Widget screen() => MaterialApp(
        home: ExpenseReviewAction(
          transactionId: expense,
          queue: q,
          action: 'propose',
        ),
      );
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '90.01');
      await tester.enterText(
        find.byType(TextField).last,
        'Wrong recorded total',
      );
      await confirm(tester);
      final first = (await TabbyLocalCache.loadPendingOps(userId: peer)).single;
      expect(first['m2_command']['new_total_centavos'], 9001);
      expect(first['m2_command']['reason'], 'Wrong recorded total');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).enabled,
        isFalse,
      );
      expect(find.text('90.01'), findsOneWidget);
      await tester.ensureVisible(find.text('Retry saved review request'));
      await tester.tap(find.text('Retry saved review request'));
      await tester.pumpAndSettle();
      expect(
        (await TabbyLocalCache.loadPendingOps(userId: peer))
            .single['operation_id'],
        first['operation_id'],
      );
    },
  );
  testWidgets(
    'resolution vote retains exact dispute and resolution identifiers and explicit decision',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ExpenseReviewAction(
            transactionId: expense,
            queue: queue(),
            action: 'vote_resolution',
            resource: const {
              'dispute_id': 'dispute',
              'resolution_id': 'resolution',
              'accept': false,
            },
            summary: 'Reject the proposed text',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await confirm(tester);
      final c = (await TabbyLocalCache.loadPendingOps(userId: peer))
          .single['m2_command'];
      expect(c['accept'], false);
      expect(c['dispute_id'], 'dispute');
      expect(c['resolution_id'], 'resolution');
      expect(c['transaction_id'], expense);
    },
  );
  testWidgets(
    'legacy acknowledged transaction status does not create actual acknowledgment or resolved dispute UI',
    (tester) async {
      final q = queue(),
          queries = M2Queries(
            actor: peer,
            current: () => true,
            rpc: (_, __) async => {
              'account_id': peer,
              'transaction_id': expense,
              'expense': {
                'description': 'Recorded expense',
                'total_centavos': 10001,
                'status': 'acknowledged',
              },
              'acknowledgments': [
                {'actor_id': owner, 'required': false, 'acknowledged': false},
                {'actor_id': peer, 'required': true, 'acknowledged': false},
              ],
              'proposals': [],
              'disputes': [],
              'can_acknowledge': true,
              'can_propose': true,
              'can_dispute': true,
            },
          );
      await tester.pumpWidget(
        MaterialApp(
          home: ExpenseReviewScreen(
            transactionId: expense,
            queue: q,
            queries: queries,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Awaiting acknowledgment'), findsOneWidget);
      expect(
        find.text('Creator (not a counterpart acknowledgment)'),
        findsOneWidget,
      );
      expect(find.text('Acknowledge this recorded expense'), findsOneWidget);
      expect(find.text('Acknowledged'), findsNothing);
    },
  );
  testWidgets('blank dispute reason cannot enqueue a request', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ExpenseReviewAction(
          transactionId: expense,
          queue: queue(),
          action: 'open_dispute',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await confirm(tester);
    expect(find.text('Enter 1–500 characters.'), findsOneWidget);
    expect(await TabbyLocalCache.loadPendingOps(userId: peer), isEmpty);
  });

  testWidgets(
    'open dispute exposes explicit unanimous resolution vote and freezes its target',
    (tester) async {
      final q = queue(),
          queries = M2Queries(
            actor: peer,
            current: () => true,
            rpc: (_, __) async => {
              'account_id': peer,
              'transaction_id': expense,
              'expense': {
                'description': 'Recorded expense',
                'total_centavos': 10001,
                'created_by': owner,
              },
              'acknowledgments': [],
              'proposals': [],
              'disputes': [
                {
                  'id': '00000000-0000-4000-8000-000000000004',
                  'status': 'open',
                  'reason': 'The allocation needs review.',
                  'required_parties': [owner, peer],
                  'resolutions': [
                    {
                      'id': '00000000-0000-4000-8000-000000000005',
                      'status': 'pending',
                      'resolution': 'Keep the original recorded amount.',
                      'accepted_count': 1,
                      'my_vote': null,
                    },
                  ],
                },
              ],
              'can_acknowledge': false,
              'can_propose': false,
              'can_dispute': false,
            },
          );
      await tester.pumpWidget(
        MaterialApp(
          home: ExpenseReviewScreen(
            transactionId: expense,
            queue: q,
            queries: queries,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Dispute: open'), findsOneWidget);
      expect(find.text('1 / 2 approvals'), findsOneWidget);
      await tester.tap(find.text('Agree to resolution'));
      await tester.pumpAndSettle();
      await confirm(tester);
      final command = (await TabbyLocalCache.loadPendingOps(userId: peer))
          .single['m2_command'];
      expect(command['action'], 'vote_resolution');
      expect(command['accept'], true);
      expect(command['dispute_id'], '00000000-0000-4000-8000-000000000004');
      expect(
        command['resolution_id'],
        '00000000-0000-4000-8000-000000000005',
      );
      expect(command['transaction_id'], expense);
    },
  );
}
