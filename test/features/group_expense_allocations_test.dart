import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/data/mock_tabby_repository.dart';
import 'package:tabby/features/tabs/data/supabase_tabby_repository.dart';
import 'package:tabby/features/tabs/data/tabby_local_cache.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:tabby/features/tabs/domain/ledger_validation.dart';
import 'package:tabby/features/tabs/presentation/add_expense_modal.dart';

List<TabbyUser> _members(int count) => [
  MockTabbyRepository.currentUser,
  for (var i = 1; i < count; i++)
    TabbyUser(id: 'friend-$i', displayName: 'Friend $i', email: '', phone: ''),
];
BilateralTab _group(int count) => BilateralTab(
  id: 'group-tab',
  counterpart: const TabbyUser(
    id: 'group-id',
    displayName: 'Dinner group',
    email: '',
    phone: '',
  ),
  members: _members(count),
  isGroupTab: true,
  groupName: 'Dinner group',
  entries: const [],
  netBalanceCentavos: 0,
  itemCount: 0,
  lastUpdated: DateTime(2026),
);

class _GroupNotifier extends TabbyNotifier {
  _GroupNotifier(int count) : super(loadInitialData: false) {
    state = state.copyWith(tabs: [_group(count)]);
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final count in [3, 5]) {
    for (final payer in _members(count)) {
      test(
        '$count member odd-cent expense with payer ${payer.id} matches every perspective',
        () async {
          final notifier = _GroupNotifier(count);
          addTearDown(notifier.dispose);
          // Omit participantCount deliberately: existing roster is authoritative.
          await notifier.addExpense(
            counterpartId: 'group-tab',
            counterpartName: 'Dinner group',
            title: 'Bill',
            totalAmountCentavos: 10001,
            category: ExpenseCategory.food,
            paidByMe: payer.id == MockTabbyRepository.currentUser.id,
            payerId: payer.id,
            payerName: payer.displayName,
            isEqualSplit: true,
          );
          final tab = notifier.state.tabs.single;
          final entry = tab.entries.single;
          expect(entry.participants.length, count);
          expect(
            entry.participants.fold<int>(
              0,
              (n, p) => n + p.shareAmountCentavos,
            ),
            10001,
          );
          expect(
            entry.participants.where((p) => p.isPayer).single.userId,
            payer.id,
          );
          final balances = [
            for (final m in tab.members)
              MockTabbyRepository.calculateNetBalance([entry], m.id),
          ];
          expect(balances.reduce((a, b) => a + b), 0);
          for (final m in tab.members) {
            final own = entry.participants
                .singleWhere((p) => p.userId == m.id)
                .shareAmountCentavos;
            expect(
              MockTabbyRepository.calculateNetBalance([entry], m.id),
              m.id == payer.id ? 10001 - own : -own,
            );
          }
          expect(
            tab.netBalanceCentavos,
            MockTabbyRepository.calculateNetBalance([
              entry,
            ], MockTabbyRepository.currentUser.id),
          );
          await TabbyLocalCache.saveTabs(
            [tab],
            userId: 'fixture',
            strict: true,
          );
          final cached = (await TabbyLocalCache.loadTabs(userId: 'fixture'))!
              .single;
          expect(cached.members.map((m) => m.id), tab.members.map((m) => m.id));
          expect(
            cached.entries.single.participants.map((p) => p.toMap()),
            entry.participants.map((p) => p.toMap()),
          );
        },
      );
    }
  }
  test('full group obligation allocates among everyone except payer', () {
    final shares = LedgerValidation.groupShares(
      total: 10001,
      members: _members(3),
      payerId: 'friend-2',
      equalSplit: false,
    );
    expect(shares.singleWhere((p) => p.isPayer).shareAmountCentavos, 0);
    expect(
      shares.where((p) => !p.isPayer).map((p) => p.shareAmountCentavos).toSet(),
      {5000, 5001},
    );
    expect(
      () => LedgerValidation.groupShares(
        total: 10001,
        members: _members(3),
        payerId: 'group-id',
        equalSplit: true,
      ),
      throwsA(isA<TabValidationException>()),
    );
  });
  test('server per-member shares produce correct payer-owned balance independent of viewer', () {
    final tab = SupabaseTabbyRepository.parseTabRow({
      'id': 'g',
      'tab_type': 'group',
      'tab_members': [
        for (final m in _members(3))
          {
            'user_id': m.id,
            'users': {'display_name': m.displayName},
          },
      ],
      'transactions': [
        {
          'id': 'expense',
          'created_by': 'user-me',
          'total_amount_centavos': 10001,
          'transaction_participants': [
            {
              'user_id': 'friend-1',
              'participant_role': 'payer',
              'share_amount_centavos': 3334,
            },
            {
              'user_id': 'friend-2',
              'participant_role': 'debtor',
              'share_amount_centavos': 3334,
            },
            {
              'user_id': 'user-me',
              'participant_role': 'debtor',
              'share_amount_centavos': 3333,
            },
          ],
        },
      ],
    }, 'user-me')!;
    expect(tab.netBalanceCentavos, -3333);
    expect(
      MockTabbyRepository.calculateNetBalance(tab.entries, 'friend-1'),
      6667,
    );
    expect(tab.entries.single.participants.length, 3);
  });
  testWidgets(
    'existing group offers actual member payer and exact share preview',
    (tester) async {
      final notifier = _GroupNotifier(3);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [tabbyProvider.overrideWith((ref) => notifier)],
          child: const MaterialApp(
            home: Scaffold(
              body: AddExpenseModal(initialCounterpartId: 'group-tab'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Next'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('create-tab-amount')),
        '100.01',
      );
      await tester.pumpAndSettle();
      expect(find.text('Who paid?'), findsOneWidget);
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Friend 2').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('₱33.34'), findsWidgets);
      expect(find.textContaining('₱33.33'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
