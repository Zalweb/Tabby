import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/data/supabase_tabby_repository.dart';
import 'package:tabby/features/tabs/data/tabby_local_cache.dart';
import 'package:tabby/features/tabs/domain/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final ownerPaid in [true, false]) {
    test(
        'contact cash settlement preserves actual parties when owner paid $ownerPaid',
        () async {
      final notifier = TabbyNotifier(loadInitialData: false);
      addTearDown(notifier.dispose);
      await notifier.addExpense(
          counterpartId: '00000000-0000-4000-8000-000000000040',
          counterpartName: 'Fixture contact',
          title: 'Lunch',
          totalAmountCentavos: 10000,
          category: ExpenseCategory.food,
          paidByMe: ownerPaid,
          isEqualSplit: true);
      final tab = notifier.state.tabs.single;
      expect(tab.isLocalOnly, isTrue);
      await notifier.settleTab(
          tabId: tab.id,
          amountCentavos: 2000,
          method: PaymentMethod.cash,
          isPayingMe: ownerPaid);
      final settled = notifier.state.tabs.single;
      expect(settled.netBalanceCentavos, ownerPaid ? 3000 : -3000);
      final payment = settled.entries.firstWhere((entry) => entry.isPayment);
      expect(payment.status, TransactionStatus.settled);
      expect(
          payment.payer!.kind, ownerPaid ? PartyKind.contact : PartyKind.user);
      expect(payment.recipient!.kind,
          ownerPaid ? PartyKind.user : PartyKind.contact);
      final reloaded = (await TabbyLocalCache.loadTabs())!.single;
      expect(reloaded.netBalanceCentavos, settled.netBalanceCentavos);
      expect(
          reloaded.entries
              .firstWhere((entry) => entry.isPayment)
              .recipient!
              .toMap(),
          payment.recipient!.toMap());
    });
  }
  test(
      'same-name contacts retain explicit identities and local state through reload',
      () async {
    final notifier = TabbyNotifier(loadInitialData: false);
    addTearDown(notifier.dispose);
    for (final id in [
      '00000000-0000-4000-8000-000000000040',
      '00000000-0000-4000-8000-000000000041'
    ]) {
      await notifier.addExpense(
          counterpartId: id,
          counterpartName: 'Same name',
          title: 'Lunch',
          totalAmountCentavos: 10000,
          category: ExpenseCategory.food,
          paidByMe: true,
          isEqualSplit: true);
    }
    expect(notifier.state.tabs, hasLength(2));
    final reloaded = await TabbyLocalCache.loadTabs();
    expect(reloaded, hasLength(2));
    expect(reloaded!.every((tab) => tab.isLocalOnly), isTrue);
  });
  test(
      'contact identity mapping is account-scoped and independent of display name',
      () {
    final one =
        SupabaseTabbyRepository.contactIdentity('owner-A', 'local-id-one');
    expect(SupabaseTabbyRepository.contactIdentity('owner-A', 'local-id-one'),
        one);
    expect(SupabaseTabbyRepository.contactIdentity('owner-B', 'local-id-one'),
        isNot(one));
    expect(SupabaseTabbyRepository.contactIdentity('owner-A', 'local-id-two'),
        isNot(one));
  });
  test(
      'contact payment parser uses actual contact payer instead of recording owner',
      () {
    final parsed = SupabaseTabbyRepository.parseTabRow({
      'id': 'tab',
      'tab_type': 'individual',
      'created_at': '2026-10-31',
      'tab_members': [
        {
          'user_id': 'owner',
          'users': {'id': 'owner', 'display_name': 'Owner'}
        },
        {
          'contact_id': 'contact',
          'contacts': {'id': 'contact', 'display_name': 'Contact'}
        }
      ],
      'transactions': [],
      'payments': [
        {
          'id': 'payment',
          'submitted_by': 'owner',
          'payer_contact_id': 'contact',
          'recipient_user_id': 'owner',
          'amount_centavos': 2000,
          'payment_method': 'cash',
          'status': 'confirmed',
          'submitted_at': '2026-10-31'
        }
      ]
    }, 'owner');
    expect(parsed!.entries.single.paidByUserId, 'contact');
    expect(parsed.entries.single.payer!.kind, PartyKind.contact);
    expect(parsed.entries.single.recipient!.id, 'owner');
  });
}
