import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/data/mock_tabby_repository.dart';
import 'package:tabby/features/tabs/data/tabby_local_cache.dart';
import 'package:tabby/features/tabs/domain/models.dart';

const me = MockTabbyRepository.currentUser;
const other = TabbyUser(
  id: 'other-user',
  displayName: 'Other',
  email: '',
  phone: '',
);
BilateralTab tab(String id, {bool group = false}) => BilateralTab(
  id: id,
  counterpart: other,
  isGroupTab: group,
  members: group ? [me, other] : [],
  entries: const [],
  netBalanceCentavos: 0,
  itemCount: 0,
  lastUpdated: DateTime(2026),
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'retry after server hydration reuses acknowledged bilateral custom expense',
    () async {
      final notifier = TabbyNotifier(loadInitialData: false);
      addTearDown(notifier.dispose);
      final acknowledged = LedgerEntry(
        id: 'server-expense',
        tabId: 'active-tab',
        title: 'Loan',
        category: ExpenseCategory.food,
        totalAmountCentavos: 15000,
        myShareCentavos: 0,
        counterpartShareCentavos: 15000,
        paidByUserId: me.id,
        paidByName: 'You',
        date: DateTime(2026),
        participants: [
          ParticipantShare(
            userId: me.id,
            name: 'You',
            shareAmountCentavos: 0,
            isPayer: true,
          ),
          ParticipantShare(
            userId: other.id,
            name: 'Other',
            shareAmountCentavos: 15000,
          ),
        ],
      );
      notifier.state = notifier.state.copyWith(
        tabs: [
          tab('active-tab').copyWith(
            entries: [acknowledged],
            itemCount: 1,
            netBalanceCentavos: 15000,
          ),
        ],
      );
      await TabbyLocalCache.saveEntryMapping(
        'entry-same-operation',
        'server-expense',
        'active-tab',
        userId: me.id,
      );
      await notifier.addExpense(
        operationId: 'same-operation',
        counterpartId: 'active-tab',
        counterpartName: 'Other',
        title: 'Loan',
        totalAmountCentavos: 15000,
        category: ExpenseCategory.food,
        paidByMe: true,
        isEqualSplit: false,
        isConnectedFriend: true,
        customAmounts: {me.id: 0, other.id: 15000},
      );
      expect(notifier.state.tabs.single.entries, [acknowledged]);
      expect(notifier.state.tabs.single.netBalanceCentavos, 15000);
    },
  );
  test(
    'actual chosen tab ID wins over another historical tab with the same user',
    () async {
      final notifier = TabbyNotifier(loadInitialData: false);
      addTearDown(notifier.dispose);
      notifier.state = notifier.state.copyWith(
        tabs: [tab('old-tab'), tab('active-tab')],
      );
      await notifier.addExpense(
        counterpartId: 'active-tab',
        counterpartName: 'Other',
        title: 'Other paid',
        totalAmountCentavos: 15000,
        category: ExpenseCategory.food,
        paidByMe: false,
        isEqualSplit: false,
        isConnectedFriend: true,
        customAmounts: {me.id: 15000, other.id: 0},
      );
      expect(notifier.state.tabs.first.entries, isEmpty);
      final actual = notifier.state.tabs.last;
      expect(actual.entries.single.tabId, 'active-tab');
      expect(actual.entries.single.paidByUserId, other.id);
      expect(actual.netBalanceCentavos, -15000);
      expect(actual.isTabOnlyParticipant, isFalse);
    },
  );
  test(
    'two-member group uses an actual member payer for custom full obligation',
    () async {
      final notifier = TabbyNotifier(loadInitialData: false);
      addTearDown(notifier.dispose);
      notifier.state = notifier.state.copyWith(
        tabs: [tab('group-tab', group: true)],
      );
      await notifier.addExpense(
        counterpartId: 'group-tab',
        counterpartName: 'Group',
        title: 'Other paid',
        totalAmountCentavos: 15001,
        category: ExpenseCategory.food,
        paidByMe: false,
        payerId: other.id,
        payerName: other.displayName,
        isEqualSplit: false,
        customAmounts: {me.id: 15001, other.id: 0},
      );
      final actual = notifier.state.tabs.single;
      expect(
        actual.entries.single.participants.map((p) => p.shareAmountCentavos),
        [15001, 0],
      );
      expect(actual.netBalanceCentavos, -15001);
    },
  );
}
