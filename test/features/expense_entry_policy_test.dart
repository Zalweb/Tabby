import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/tabs/domain/expense_entry_policy.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:tabby/features/tabs/domain/ledger_validation.dart';

void main() {
  final date = DateTime(2026, 11, 17, 13);
  final expense = LedgerEntry(
    id: 'old',
    tabId: 'tab',
    title: 'Lunch',
    category: ExpenseCategory.food,
    totalAmountCentavos: 15000,
    myShareCentavos: 0,
    counterpartShareCentavos: 15000,
    paidByUserId: 'me',
    paidByName: 'Me',
    date: date,
  );
  ExpenseDraftFingerprint draft({
    String tab = 'tab',
    String title = ' lunch ',
    DateTime? day,
    String payer = 'me',
    int own = 0,
  }) => ExpenseDraftFingerprint(
    tabId: tab,
    amountCentavos: 15000,
    description: title,
    category: ExpenseCategory.food,
    payerId: payer,
    date: day ?? date,
    shares: {'me': own, 'friend': 15000 - own},
  );
  test('matches same tab, details, calendar day, payer and allocation', () {
    expect(
      draft().matches(expense, viewerId: 'me', counterpartId: 'friend'),
      isTrue,
    );
    for (final other in [
      draft(tab: 'other'),
      draft(title: 'Dinner'),
      draft(day: DateTime(2026, 11, 16, 23, 59)),
      draft(payer: 'friend'),
      draft(own: 7500),
    ]) {
      expect(
        other.matches(expense, viewerId: 'me', counterpartId: 'friend'),
        isFalse,
      );
    }
  });
  test(
    'amount alone, payments, cancelled and own operation are not duplicates',
    () {
      for (final row in [
        expense.copyWith(title: 'Coffee'),
        expense.copyWith(isPayment: true),
        expense.copyWith(status: TransactionStatus.cancelled),
        expense.copyWith(id: 'entry-retry'),
        for (final role in ['original', 'reversal'])
          expense.copyWith(
            revision: ExpenseRevision(
              changeId: 'change',
              originalId: 'old',
              role: role,
              kind: 'correct',
              reason: 'Synthetic correction',
            ),
          ),
      ]) {
        expect(
          draft().matches(
            row,
            viewerId: 'me',
            counterpartId: 'friend',
            operationId: 'retry',
          ),
          isFalse,
        );
      }
    },
  );
  test('group allocations are compared by identity, including zero payer', () {
    final row = expense.copyWith(
      totalAmountCentavos: 45000,
      participants: const [
        ParticipantShare(
          userId: 'me',
          name: 'Same',
          shareAmountCentavos: 0,
          isPayer: true,
        ),
        ParticipantShare(userId: 'a', name: 'Same', shareAmountCentavos: 15000),
        ParticipantShare(userId: 'b', name: 'Same', shareAmountCentavos: 30000),
      ],
    );
    final group = ExpenseDraftFingerprint(
      tabId: 'tab',
      amountCentavos: 45000,
      description: 'Lunch',
      category: ExpenseCategory.food,
      payerId: 'me',
      date: date,
      shares: {'b': 30000, 'me': 0, 'a': 15000},
    );
    expect(group.matches(row, viewerId: 'me', counterpartId: 'group'), isTrue);
  });
  test('custom amounts validate exact sum and complete immutable roster', () {
    const members = [
      TabbyUser(id: 'me', displayName: 'Me', email: '', phone: ''),
      TabbyUser(id: 'a', displayName: 'Friend', email: '', phone: ''),
      TabbyUser(id: 'b', displayName: 'Friend', email: '', phone: ''),
    ];
    final shares = LedgerValidation.customShares(
      total: 45000,
      members: members,
      payerId: 'me',
      amounts: {'me': 0, 'a': 15000, 'b': 30000},
    );
    expect(shares.map((p) => p.shareAmountCentavos), [0, 15000, 30000]);
    for (final amounts in [
      {'me': 0, 'a': 15000, 'b': 29999},
      {'me': -1, 'a': 15001, 'b': 30000},
      {'me': 0, 'a': 45000},
      {'me': 0, 'a': 15000, 'b': 30000, 'outsider': 0},
    ]) {
      expect(
        () => LedgerValidation.customShares(
          total: 45000,
          members: members,
          payerId: 'me',
          amounts: amounts,
        ),
        throwsA(isA<TabValidationException>()),
      );
    }
  });
}
