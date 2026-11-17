import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/payment_methods/application/payment_methods_provider.dart';
import 'package:tabby/features/payment_methods/domain/payment_method.dart'
    as saved;
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/data/mock_tabby_repository.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:tabby/features/tabs/domain/pair_obligations.dart';
import 'package:tabby/features/tabs/presentation/tab_detail_screen.dart';

const me = 'user-me', bob = 'bob', carol = 'carol';
LedgerEntry _bill(String payer, Map<String, int> shares) => LedgerEntry(
        id: 'bill-$payer',
        tabId: 'g',
        title: 'Bill $payer',
        category: ExpenseCategory.food,
        totalAmountCentavos: shares.values.reduce((a, b) => a + b),
        myShareCentavos: shares[me]!,
        counterpartShareCentavos:
            shares.values.reduce((a, b) => a + b) - shares[me]!,
        paidByUserId: payer,
        paidByName: payer,
        date: DateTime(2026),
        participants: [
          for (final p in shares.entries)
            ParticipantShare(
                userId: p.key,
                name: p.key,
                shareAmountCentavos: p.value,
                isPayer: p.key == payer)
        ]);
BilateralTab _tab() => BilateralTab(
    id: 'g',
    isGroupTab: true,
    groupName: 'Roommates',
    counterpart: const TabbyUser(
        id: 'group-id', displayName: 'Roommates', email: '', phone: ''),
    members: const [
      TabbyUser(id: me, displayName: 'You', email: '', phone: ''),
      TabbyUser(id: bob, displayName: 'Bob', email: '', phone: ''),
      TabbyUser(id: carol, displayName: 'Carol', email: '', phone: '')
    ],
    netBalanceCentavos: 0,
    itemCount: 2,
    lastUpdated: DateTime(2026),
    entries: [
      _bill(me, {me: 5000, bob: 5000, carol: 0}),
      _bill(carol, {me: 5000, bob: 0, carol: 5000})
    ]);

class _Notifier extends TabbyNotifier {
  _Notifier() : super(loadInitialData: false) {
    state = state.copyWith(tabs: [_tab()]);
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('zero aggregate retains two separate direct obligations', () {
    final tab = _tab();
    expect(MockTabbyRepository.calculateNetBalance(tab.entries, me), 0);
    final pairs = groupObligations(tab);
    expect(pairs.length, 2);
    expect(
        pairs.any((p) =>
            p.payerId == me &&
            p.recipientId == carol &&
            p.amountCentavos == 5000),
        isTrue);
    expect(
        pairs.any((p) =>
            p.payerId == bob &&
            p.recipientId == me &&
            p.amountCentavos == 5000),
        isTrue);
    expect(pairOutstanding(tab.entries, bob, carol), 0);
  });
  test(
      'settlement selects a real member and validates pair rather than aggregate',
      () async {
    final n = _Notifier();
    addTearDown(n.dispose);
    await expectLater(
        n.settleTab(
            tabId: 'g',
            amountCentavos: 1000,
            method: PaymentMethod.cash,
            isPayingMe: false),
        throwsA(anything));
    await expectLater(
        n.settleGroupPair(
            tabId: 'g',
            counterpartyUserId: carol,
            amountCentavos: 5001,
            method: PaymentMethod.cash,
            isPayingMe: false),
        throwsArgumentError);
    await n.settleGroupPair(
        tabId: 'g',
        counterpartyUserId: carol,
        amountCentavos: 4000,
        method: PaymentMethod.cash,
        isPayingMe: false);
    final payment = n.state.tabs.single.entries.first;
    expect(payment.payer?.id, me);
    expect(payment.recipient?.id, carol);
    expect(payment.status, TransactionStatus.paymentSubmitted);
    expect(pairOutstanding(n.state.tabs.single.entries, me, carol), 5000);
    await n.settleGroupPair(
        tabId: 'g',
        counterpartyUserId: bob,
        amountCentavos: 1000,
        method: PaymentMethod.cash,
        isPayingMe: true);
    expect(pairOutstanding(n.state.tabs.single.entries, bob, me), 4000);
    expect(pairOutstanding(n.state.tabs.single.entries, me, carol), 5000);
  });
  testWidgets(
      'group debtor opens actual creditor payment methods despite zero aggregate',
      (tester) async {
    TabPaymentMethodRequest? requested;
    final n = _Notifier();
    await tester.pumpWidget(ProviderScope(overrides: [
      tabbyProvider.overrideWith((ref) => n),
      tabPaymentMethodsProvider.overrideWith((ref, request) async {
        requested = request;
        return [
          const saved.PaymentMethod(
              id: 'carol-method',
              ownerUserId: carol,
              provider: 'gcash',
              displayName: 'Carol receiving method',
              accountLabel: 'Fixture only')
        ];
      })
    ], child: const MaterialApp(home: TabDetailScreen(tabId: 'g'))));
    await tester.pumpAndSettle();
    expect(find.text('Who owes whom'), findsOneWidget);
    final info = find.byKey(const ValueKey('pair-info-user-me-carol'));
    await tester.ensureVisible(info);
    await tester.tap(info);
    await tester.pumpAndSettle();
    expect(requested?.tabId, 'g');
    expect(requested?.payeeUserId, carol);
    expect(find.text("Carol's Payment Info"), findsOneWidget);
    expect(find.text('Carol receiving method'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
