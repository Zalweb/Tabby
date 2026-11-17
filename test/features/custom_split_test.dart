import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/services/form_draft_store.dart';
import 'package:tabby/features/tabs/domain/custom_split.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:tabby/features/tabs/domain/m2_capabilities.dart';
import 'package:tabby/features/tabs/data/m2_command_queue.dart';
import 'package:tabby/features/tabs/data/tabby_local_cache.dart';
import 'package:tabby/features/tabs/presentation/custom_split_form.dart';

const a = PartyRef(
  kind: PartyKind.user,
  id: '00000000-0000-4000-8000-000000000001',
);
const b = PartyRef(
  kind: PartyKind.user,
  id: '00000000-0000-4000-8000-000000000002',
);
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('explicit retry resets only the saved M2 request and preserves attention truth', () async {
    var attempts = 0;
    final queue = M2CommandQueue(
      actor: a.id,
      current: () => true,
      wake: () async {
        if (++attempts == 1) {
          await TabbyLocalCache.recordPendingFailure(
            'retry',
            userId: a.id,
            now: DateTime.now(),
            permanent: true,
          );
        }
      },
    );
    final command = {'p_expected_actor': a.id, 'p_tab_id': 'tab'};
    await queue.enqueue('retry', 'create_expense_v3', command);
    expect(await queue.needsAttention('retry'), isTrue);
    await queue.enqueue('retry', 'create_expense_v3', command);
    expect(await queue.needsAttention('retry'), isFalse);
    expect((await TabbyLocalCache.loadPendingOps(userId: a.id)), hasLength(1));
  });
  testWidgets(
    'unreadable prior draft cannot silently create a new financial intent',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        FormDraftStore.key(a.id, 'custom-split:tab'): 'not-json',
      });
      var wakes = 0;
      final queue = M2CommandQueue(
        actor: a.id,
        current: () => true,
        wake: () async {
          wakes++;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CustomSplitForm(
            tabId: 'tab',
            parties: {a: 'You', b: 'Friend'},
            queue: queue,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Save expense'), findsNothing);
      expect(wakes, 0);
      expect(find.textContaining('could not be restored'), findsOneWidget);
    },
  );
  test('independent charges and integer remainder allocation match stored SQL contract', () {
    final split = CustomSplit(
      baseShares: {a: 5000, b: 5001},
      taxBasisPoints: 1200,
      serviceBasisPoints: 1000,
    );
    expect(split.total, 12201);
    expect(split.tax, 1200);
    expect(split.service, 1000);
    expect(split.shares, {a: 6100, b: 6101});
    expect(
      CustomSplit(
        baseShares: {b: 5001, a: 5000},
        taxBasisPoints: 1200,
        serviceBasisPoints: 1000,
      ).shares,
      split.shares,
    );
  });
  test('half cents round up, zero shares stay zero, and ties follow immutable identity', () {
    final zero = CustomSplit(
      baseShares: {a: 0, b: 1},
      taxBasisPoints: 5000,
      serviceBasisPoints: 5000,
    );
    expect(zero.shares, {a: 0, b: 3});
    final ties = CustomSplit(baseShares: {b: 1, a: 1}, taxBasisPoints: 5000);
    expect(ties.shares, {a: 2, b: 1});
  });
  test(
    'negative, empty, overflow and invalid rates fail before submission',
    () {
      for (final work in [
        () => CustomSplit(baseShares: {}),
        () => CustomSplit(baseShares: {a: -1, b: 10}),
        () => CustomSplit(baseShares: {a: 0}),
        () => CustomSplit(baseShares: {a: 99999999999}, taxBasisPoints: 1),
        () => CustomSplit(baseShares: {a: 1}, taxBasisPoints: 10001),
      ]) {
        expect(work, throwsFormatException);
      }
    },
  );
  test('M2 intents retain operation identity and cannot edit a queued command or cross accounts', () async {
    var current = true;
    var wakes = 0;
    final queue = M2CommandQueue(
      actor: a.id,
      current: () => current,
      wake: () async {
        wakes++;
      },
    );
    final command = CustomSplit(baseShares: {a: 1, b: 2})
        .toCommand(actor: a.id, tabId: 'tab', payer: a, description: 'Fixture');
    await queue.enqueue('op', 'create_expense_v3', command);
    await queue.enqueue('op', 'create_expense_v3', command);
    await expectLater(
      queue.enqueue('op', 'create_expense_v3', {
        ...command,
        'p_description': 'Changed',
      }),
      throwsStateError,
    );
    expect((await TabbyLocalCache.loadPendingOps(userId: a.id)), hasLength(1));
    expect(await queue.result('op'), null);
    expect(wakes, 2);
    current = false;
    await expectLater(
      queue.enqueue('new', 'create_expense_v3', command),
      throwsStateError,
    );
    expect((await TabbyLocalCache.loadPendingOps(userId: b.id)), isEmpty);
  });
  test('all M2 application rollout flags remain off', () {
    expect([
      M2Capabilities.customSplits,
      M2Capabilities.recurring,
      M2Capabilities.contactClaiming,
      M2Capabilities.expenseReview,
    ], everyElement(false));
  });
  testWidgets(
    'custom split previews totals and saves a frozen durable request without implying server success',
    (tester) async {
      final queue = M2CommandQueue(
        actor: a.id,
        current: () => true,
        wake: () async {},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CustomSplitForm(
            tabId: 'tab',
            parties: {a: 'You', b: 'Friend'},
            queue: queue,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Description'),
        'Dinner',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'You base share (PHP)'),
        '50.00',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Friend base share (PHP)'),
        '50.01',
      );
      await tester.enterText(find.widgetWithText(TextField, 'Tax (%)'), '12');
      await tester.enterText(
        find.widgetWithText(TextField, 'Service (%)'),
        '10',
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Save expense'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save expense'));
      await tester.pumpAndSettle();
      expect(find.text('Saved on this device. Sync pending.'), findsOneWidget);
      final saved = (await TabbyLocalCache.loadPendingOps(userId: a.id)).single;
      expect(saved['m2_command']['p_total_amount_centavos'], 12201);
      expect(find.text('Expense recorded.'), findsNothing);
      await tester.scrollUntilVisible(
        find.widgetWithText(TextField, 'Description'),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Description'))
            .enabled,
        isFalse,
      );
    },
  );
}
