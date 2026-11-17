import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/tabs/data/mock_tabby_repository.dart';
import 'package:tabby/features/tabs/data/supabase_tabby_repository.dart';
import 'package:tabby/features/tabs/data/tabby_local_cache.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/presentation/tab_detail_screen.dart';

class _GroupNotifier extends TabbyNotifier {
  _GroupNotifier(BilateralTab tab) : super(loadInitialData: false) {
    replace(tab);
  }
  void replace(BilateralTab tab) {
    state = state.copyWith(tabs: [tab]);
  }
}

Map<String, dynamic> _row(String paymentStatus) => {
      'id': 'group-tab',
      'tab_type': 'group',
      'group_name': 'Friends',
      'tab_members': [
        for (final id in ['alice', 'bob', 'carol'])
          {
            'user_id': id,
            'users': {'display_name': id}
          }
      ],
      'transactions': [
        {
          'id': 'expense',
          'description': 'Shared bill',
          'created_by': 'carol',
          'total_amount_centavos': 10000,
          'status': 'acknowledged',
          'transaction_participants': [
            {
              'user_id': 'alice',
              'participant_role': 'debtor',
              'share_amount_centavos': 3000
            },
            {
              'user_id': 'bob',
              'participant_role': 'debtor',
              'share_amount_centavos': 3000
            },
            {
              'user_id': 'carol',
              'participant_role': 'payer',
              'share_amount_centavos': 4000
            },
          ]
        }
      ],
      'payments': [
        {
          'id': 'bob-carol',
          'submitted_by': 'bob',
          'payer_user_id': 'bob',
          'recipient_user_id': 'carol',
          'amount_centavos': 1000,
          'status': paymentStatus,
          'payment_method': 'cash'
        }
      ],
    };

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
      'Alice group detail retains her amount after Bob pays Carol and refreshes',
      (tester) async {
    final notifier = _GroupNotifier(
        SupabaseTabbyRepository.parseTabRow(_row('submitted'), 'alice')!);
    await tester.pumpWidget(ProviderScope(
        overrides: [tabbyProvider.overrideWith((ref) => notifier)],
        child: const MaterialApp(home: TabDetailScreen(tabId: 'group-tab'))));
    await tester.pumpAndSettle();
    expect(find.text('₱30.00'), findsWidgets);
    notifier.replace(
        SupabaseTabbyRepository.parseTabRow(_row('confirmed'), 'alice')!);
    await tester.pumpAndSettle();
    expect(find.text('₱30.00'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Shared bill'));
    await tester.pumpAndSettle();
    expect(find.text("alice's share"), findsOneWidget);
    expect(find.text("bob's share"), findsOneWidget);
    expect(find.text("carol's share"), findsOneWidget);
  });
  test('Bob-to-Carol payment changes only those two perspectives', () {
    for (final status in ['submitted', 'confirmed', 'rejected']) {
      final alice = SupabaseTabbyRepository.parseTabRow(_row(status), 'alice')!;
      final bob = SupabaseTabbyRepository.parseTabRow(_row(status), 'bob')!;
      final carol = SupabaseTabbyRepository.parseTabRow(_row(status), 'carol')!;
      expect(alice.netBalanceCentavos, -3000);
      expect(bob.netBalanceCentavos, status == 'confirmed' ? -2000 : -3000);
      expect(carol.netBalanceCentavos, status == 'confirmed' ? 5000 : 6000);
      expect(
          alice.netBalanceCentavos +
              bob.netBalanceCentavos +
              carol.netBalanceCentavos,
          0);
    }
  });
  test('explicit recipients survive cache reload and authoritative refresh',
      () async {
    final tab =
        SupabaseTabbyRepository.parseTabRow(_row('confirmed'), 'alice')!;
    await TabbyLocalCache.saveTabs([tab], userId: 'alice', strict: true);
    final cached = (await TabbyLocalCache.loadTabs(userId: 'alice'))!.single;
    final payment = cached.entries.singleWhere((e) => e.isPayment);
    expect(payment.recipient?.id, 'carol');
    expect(payment.payer?.id, 'bob');
    expect(MockTabbyRepository.calculateNetBalance(cached.entries, 'alice'),
        -3000);
    final fresh =
        SupabaseTabbyRepository.parseTabRow(_row('confirmed'), 'alice')!;
    final merged =
        MockTabbyRepository.mergeServerEntries(fresh.entries, cached.entries);
    expect(MockTabbyRepository.calculateNetBalance(merged, 'alice'), -3000);
  });
  test(
      'unknown recipients and contact identities cannot credit an uninvolved user',
      () {
    final payment =
        SupabaseTabbyRepository.parseTabRow(_row('confirmed'), 'alice')!
            .entries
            .singleWhere((e) => e.isPayment);
    final legacy = LedgerEntry.fromMap({...payment.toMap(), 'recipient': null});
    expect(MockTabbyRepository.calculateNetBalance([legacy], 'alice'), 0);
    final contact = payment.copyWith(
        recipient: const PartyRef(kind: PartyKind.contact, id: 'alice'));
    expect(MockTabbyRepository.calculateNetBalance([contact], 'alice'), 0);
  });
}
