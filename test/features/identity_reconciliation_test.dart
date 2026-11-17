import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tabby/features/tabs/data/tabby_local_cache.dart';
import 'package:tabby/features/tabs/data/mock_tabby_repository.dart';
import 'package:tabby/features/tabs/domain/models.dart';

void main() {
  BilateralTab tab(String id, String party, {bool group = false}) =>
      BilateralTab(
          id: id,
          counterpart:
              TabbyUser(id: party, displayName: 'Alex', email: '', phone: ''),
          netBalanceCentavos: 100,
          itemCount: 0,
          entries: const [],
          lastUpdated: DateTime(2026),
          isGroupTab: group);
  test('same-price distinct expenses survive reconciliation', () {
    LedgerEntry entry(String id, String title, int minute) => LedgerEntry(
        id: id,
        tabId: 'tab',
        title: title,
        category: ExpenseCategory.values.first,
        totalAmountCentavos: 10000,
        myShareCentavos: 5000,
        counterpartShareCentavos: 5000,
        paidByUserId: 'me',
        paidByName: 'Me',
        date: DateTime(2026, 10, 31, 12, minute));
    final lunch = entry('entry-local', 'Lunch', 0);
    final coffee = entry('11111111-1111-4111-8111-111111111111', 'Coffee', 10);
    expect(MockTabbyRepository.deduplicateLedgerEntries([lunch, coffee]),
        hasLength(2));
    expect(MockTabbyRepository.deduplicateLedgerEntries([coffee, coffee]),
        hasLength(1));
    expect(
        MockTabbyRepository.deduplicateLedgerEntries(
            [coffee, coffee.copyWith(id: 'entry-${coffee.id}')]),
        hasLength(2));
  });

  test('same-name people and groups survive repeated reconciliation', () {
    var tabs = [
      tab('a', 'one'),
      tab('b', 'two'),
      tab('g1', 'g1', group: true),
      tab('g2', 'g2', group: true)
    ];
    for (var i = 0; i < 3; i++) {
      tabs = MockTabbyRepository.deduplicateTabs(tabs);
      expect(tabs.map((t) => t.id), ['a', 'b', 'g1', 'g2']);
    }
  });
  test('same immutable party reconciles across tab IDs', () {
    expect(
        MockTabbyRepository.deduplicateTabs(
            [tab('local', 'one'), tab('server', 'one')]),
        hasLength(1));
  });
  test('registered and contact namespaces never match by display name or ID',
      () {
    final registered = tab('registered', 'same-id');
    final contact =
        tab('contact', 'same-id').copyWith(isTabOnlyParticipant: true);
    expect(MockTabbyRepository.sameRelationship(registered, contact), isFalse);
    expect(
        MockTabbyRepository.sameRelationship(tab('a', 'one'), tab('b', 'two')),
        isFalse);
    expect(
        MockTabbyRepository.sameRelationship(
            tab('g1', 'g1', group: true), tab('g2', 'g2', group: true)),
        isFalse);
  });
  test('server confirmation overrides a newer optimistic copy of the same ID',
      () {
    final pending = LedgerEntry(
        id: 'payment',
        tabId: 'tab',
        title: 'Payment',
        category: ExpenseCategory.other,
        totalAmountCentavos: 100,
        myShareCentavos: 0,
        counterpartShareCentavos: 0,
        paidByUserId: 'me',
        paidByName: 'Me',
        date: DateTime(2026, 10, 31),
        isPayment: true,
        status: TransactionStatus.paymentSubmitted);
    final confirmed = pending.copyWith(
        status: TransactionStatus.settled, date: DateTime(2026, 10, 30));
    final merged =
        MockTabbyRepository.mergeServerEntries([confirmed], [pending]);
    expect(merged.single.status, TransactionStatus.settled);
    expect(MockTabbyRepository.calculateNetBalance(merged, 'me'), 100);
  });
  test(
      'explicit server result mapping survives cache reload without duplicate debt',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    final entry = LedgerEntry(
        id: 'local-entry',
        tabId: 'local-tab',
        title: 'Lunch',
        category: ExpenseCategory.food,
        totalAmountCentavos: 100,
        myShareCentavos: 50,
        counterpartShareCentavos: 50,
        paidByUserId: 'me',
        paidByName: 'Me',
        date: DateTime(2026));
    final mapped = MockTabbyRepository.applyOperationResult([
      tab('local-tab', 'friend').copyWith(entries: [entry])
    ],
        localEntryId: 'local-entry',
        remoteTabId: 'server-tab',
        remoteEntryId: 'server-entry',
        currentUserId: 'me');
    await TabbyLocalCache.saveTabs(mapped, userId: 'me', strict: true);
    final reloaded = (await TabbyLocalCache.loadTabs(userId: 'me'))!.single;
    expect(reloaded.id, 'server-tab');
    expect(reloaded.entries.single.id, 'server-entry');
    expect(
        MockTabbyRepository.mergeServerEntries(
            reloaded.entries, reloaded.entries),
        hasLength(1));
    expect(reloaded.netBalanceCentavos, 50);
  });
  test('same-name parties and groups survive durable cache reload', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final tabs = [
      tab('a', 'one'),
      tab('b', 'two'),
      tab('g1', 'g1', group: true),
      tab('g2', 'g2', group: true)
    ];
    await TabbyLocalCache.saveTabs(tabs, userId: 'owner');
    final loaded = await TabbyLocalCache.loadTabs(userId: 'owner');
    expect(loaded!.map((t) => t.id), ['a', 'b', 'g1', 'g2']);
    await TabbyLocalCache.saveTabs(loaded, userId: 'owner');
    expect((await TabbyLocalCache.loadTabs(userId: 'owner'))!.length, 4);
  });
}
