import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/home/domain/activity_period.dart';
import 'package:tabby/features/home/domain/home_dashboard_summary.dart';
import 'package:tabby/features/tabs/application/tabby_state.dart';
import 'package:tabby/features/tabs/domain/models.dart';

const owner = 'summary-owner', bob = 'summary-bob', carol = 'summary-carol';
final now = DateTime(2026, 11, 17, 12);
LedgerEntry payment(
  String id,
  int cents, {
  String payer = owner,
  String recipient = bob,
  TransactionStatus status = TransactionStatus.settled,
  DateTime? date,
  bool parties = true,
}) => LedgerEntry(
  id: id,
  tabId: 'summary-tab',
  title: 'Payment',
  category: ExpenseCategory.other,
  totalAmountCentavos: cents,
  myShareCentavos: 0,
  counterpartShareCentavos: 0,
  paidByUserId: payer,
  paidByName: 'A recorded party',
  date: date ?? now,
  isPayment: true,
  status: status,
  payer: parties ? PartyRef(kind: PartyKind.user, id: payer) : null,
  recipient: parties ? PartyRef(kind: PartyKind.user, id: recipient) : null,
);
BilateralTab tab(List<LedgerEntry> rows, {bool group = false, int net = 0}) =>
    BilateralTab(
      id: 'summary-tab',
      counterpart: const TabbyUser(
        id: bob,
        displayName: 'Bob',
        email: '',
        phone: '',
      ),
      netBalanceCentavos: net,
      itemCount: rows.length,
      entries: rows,
      lastUpdated: now,
      isGroupTab: group,
      members: group
          ? const [
              TabbyUser(id: owner, displayName: 'Owner', email: '', phone: ''),
              TabbyUser(id: bob, displayName: 'Bob', email: '', phone: ''),
              TabbyUser(id: carol, displayName: 'Carol', email: '', phone: ''),
            ]
          : const [],
    );
HomeDashboardSummary summary(
  List<BilateralTab> tabs, {
  ActivityPeriod period = ActivityPeriod.thisMonth,
}) => HomeDashboardSummary(
  state: TabbyDashboardState(
    viewerUserId: owner,
    tabs: tabs,
    activities: const [],
    reminders: const [],
  ),
  period: period,
  now: now,
  viewerId: owner,
);
LedgerEntry bill(
  String id,
  String payer,
  String debtor, {
  bool details = true,
}) => LedgerEntry(
  id: id,
  tabId: 'summary-tab',
  title: 'Shared meal',
  category: ExpenseCategory.food,
  totalAmountCentavos: 10000,
  myShareCentavos: 5000,
  counterpartShareCentavos: 5000,
  paidByUserId: payer,
  paidByName: 'Recorded payer',
  date: now,
  status: TransactionStatus.acknowledged,
  participants: details
      ? [
          ParticipantShare(
            userId: payer,
            name: 'Payer',
            shareAmountCentavos: 5000,
            isPayer: true,
          ),
          ParticipantShare(
            userId: debtor,
            name: 'Other',
            shareAmountCentavos: 5000,
          ),
        ]
      : const [],
);
void main() {
  test(
    'Received/Paid use confirmed explicit parties and integer centavos only',
    () {
      final s = summary([
        tab([
          payment('received', 12345, payer: bob, recipient: owner),
          payment('paid', 6789),
          payment(
            'submitted',
            99999,
            status: TransactionStatus.paymentSubmitted,
          ),
          payment('rejected', 9000, status: TransactionStatus.cancelled),
          bill('expense', owner, bob),
        ]),
      ]);
      expect(s.receivedCentavos, 12345);
      expect(s.paidCentavos, 6789);
    },
  );
  test('Payment totals deduplicate repeated ledger IDs across cached tabs', () {
    final p = payment('same', 1201);
    final s = summary([
      tab([p]),
      tab([p]),
    ]);
    expect(s.paidCentavos, 1201);
  });
  test('Payment windows use inclusive recorded dates and exclude future or prior records', () {
    final s = summary([
      tab([
        payment('boundary', 111, date: now.subtract(const Duration(hours: 24))),
        payment(
          'old',
          222,
          date: now.subtract(const Duration(hours: 24, seconds: 1)),
        ),
        payment('future', 333, date: now.add(const Duration(seconds: 1))),
      ]),
    ], period: ActivityPeriod.last24Hours);
    expect(s.paidCentavos, 111);
  });
  test(
    'Unknown legacy parties are disclosed and never inferred from names',
    () {
      final s = summary([
        tab([payment('legacy', 700, parties: false)]),
      ]);
      expect(s.hasUnattributedPayments, isTrue);
      expect(s.paidCentavos, 0);
      expect(s.receivedCentavos, 0);
    },
  );
  test('Offsetting group pairs remain active despite a zero net position', () {
    final s = summary([
      tab([bill('a', owner, bob), bill('b', carol, owner)], group: true),
    ]);
    expect(s.activeTabs, 1);
    expect(s.clearTabs, 0);
    expect(s.clearance, 0);
  });
  test(
    'Group clearance is explicitly personal, not a claim all members settled',
    () {
      final s = summary([
        tab([bill('other-members', bob, carol)], group: true),
      ]);
      expect(s.clearTabs, 1);
      expect(s.activeTabs, 0);
    },
  );
  test('Unknown legacy group obligations cannot inflate clearance', () {
    final s = summary([
      tab([bill('legacy', owner, bob, details: false)], group: true),
    ]);
    expect(s.activeTabs, 1);
    expect(s.clearTabs, 0);
  });
  test('Empty tabs have finite zero progress', () {
    final s = summary([]);
    expect(s.totalTabs, 0);
    expect(s.clearance, 0);
    expect(s.clearance.isFinite, isTrue);
  });
}
