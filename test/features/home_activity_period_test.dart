import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/home/domain/activity_period.dart';
import 'package:tabby/features/home/presentation/home_dashboard_screen.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/application/tabby_state.dart';
import 'package:tabby/features/tabs/data/mock_tabby_repository.dart';
import 'package:tabby/features/tabs/data/supabase_tabby_repository.dart';
import 'package:tabby/features/tabs/domain/models.dart';

const me = 'user-me', bob = 'bob', carol = 'carol';
LedgerEntry bill(
  String payer,
  String debtor, {
  TransactionStatus status = TransactionStatus.pending,
}) => LedgerEntry(
  id: 'bill-$payer-$debtor',
  tabId: 'group',
  title: 'Synthetic bill',
  category: ExpenseCategory.food,
  totalAmountCentavos: 10000,
  myShareCentavos: 5000,
  counterpartShareCentavos: 5000,
  paidByUserId: payer,
  paidByName: payer,
  date: DateTime(2026),
  status: status,
  participants: [
    ParticipantShare(
      userId: payer,
      name: payer,
      shareAmountCentavos: 5000,
      isPayer: true,
    ),
    ParticipantShare(userId: debtor, name: debtor, shareAmountCentavos: 5000),
  ],
);
BilateralTab group(List<LedgerEntry> entries) => BilateralTab(
  id: 'group',
  isGroupTab: true,
  groupName: 'Group',
  counterpart: const TabbyUser(
    id: 'group-id',
    displayName: 'Group',
    email: '',
    phone: '',
  ),
  members: const [
    TabbyUser(id: me, displayName: 'You', email: '', phone: ''),
    TabbyUser(id: bob, displayName: 'Bob', email: '', phone: ''),
    TabbyUser(id: carol, displayName: 'Carol', email: '', phone: ''),
  ],
  netBalanceCentavos: 0,
  itemCount: entries.length,
  lastUpdated: DateTime(2026),
  entries: entries,
);
TabbyActivity activity(String id, DateTime date) => TabbyActivity(
  id: id,
  actorName: id,
  description: 'Synthetic $id',
  amountCentavos: 100,
  timestamp: date,
);

void main() {
  test(
    'legacy group without member shares retains known net and flags review',
    () {
      final legacy = group([])
          .copyWith(members: [], netBalanceCentavos: -12345);
      final state = TabbyDashboardState(
        viewerUserId: me,
        tabs: [legacy],
        activities: const [],
        reminders: const [],
      );
      expect(state.youOweCentavos, 12345);
      expect(state.youAreOwedCentavos, 0);
      expect(state.hasIncompleteGroupBalances, isTrue);
      final zeroLegacy = group([bill(me, bob).copyWith(participants: [])]);
      expect(
        state.copyWith(tabs: [zeroLegacy]).hasIncompleteGroupBalances,
        isTrue,
      );
    },
  );
  final now = DateTime(2026, 11, 10, 12, 30);
  for (final period in [ActivityPeriod.last24Hours, ActivityPeriod.last7Days]) {
    test(
      '${period.label} uses exact inclusive rolling boundaries and excludes future',
      () {
        final start = now.subtract(
          period == ActivityPeriod.last24Hours
              ? const Duration(hours: 24)
              : const Duration(days: 7),
        );
        expect(period.includes(start, now), isTrue);
        expect(
          period.includes(start.subtract(const Duration(microseconds: 1)), now),
          isFalse,
        );
        expect(period.includes(now, now), isTrue);
        expect(
          period.includes(now.add(const Duration(microseconds: 1)), now),
          isFalse,
        );
      },
    );
  }
  test('calendar month uses local month start, equivalent UTC instants and excludes prior/future', () {
    final start = DateTime(2026, 11, 1);
    expect(ActivityPeriod.thisMonth.includes(start.toUtc(), now), isTrue);
    expect(
      ActivityPeriod.thisMonth.includes(
        start.subtract(const Duration(microseconds: 1)),
        now,
      ),
      isFalse,
    );
    expect(
      ActivityPeriod.thisMonth.includes(
        now.add(const Duration(seconds: 1)),
        now,
      ),
      isFalse,
    );
    expect(
      ActivityPeriod.thisMonth.includes(DateTime(2025, 11, 10), now),
      isFalse,
    );
    expect(
      ActivityPeriod.thisMonth.includes(
        DateTime(2026, 10, 31, 23, 59, 59),
        DateTime(2026, 11, 1, 0, 1),
      ),
      isFalse,
    );
  });
  test(
    'activity windows keep distinct same-price IDs and sort newest first',
    () {
      final rows = activitiesForPeriod(
        [
          activity('a', now.subtract(const Duration(hours: 1))),
          activity('b', now),
          activity('c', DateTime(2026, 10, 31)),
        ],
        ActivityPeriod.thisMonth,
        now,
      );
      expect(rows.map((r) => r.id), ['b', 'a']);
    },
  );
  test(
    'group dashboard retains payable and receivable despite zero aggregate',
    () {
      final state = TabbyDashboardState(
        viewerUserId: me,
        tabs: [
          group([bill(me, bob), bill(carol, me)]),
        ],
        activities: const [],
        reminders: const [],
      );
      expect(state.youOweCentavos, 5000);
      expect(state.youAreOwedCentavos, 5000);
      expect(state.netBalanceCentavos, 0);
      expect(state.activeEmotion, isNot(MascotEmotion.sleeping));
      expect(state.copyWith().viewerUserId, me);
    },
  );
  test('pending payment does not reduce obligations; confirmed payment changes only actual pair', () {
    final payment = LedgerEntry(
      id: 'pay',
      tabId: 'group',
      title: 'Payment',
      category: ExpenseCategory.other,
      totalAmountCentavos: 5000,
      myShareCentavos: 0,
      counterpartShareCentavos: 0,
      paidByUserId: me,
      paidByName: 'You',
      date: now,
      isPayment: true,
      status: TransactionStatus.paymentSubmitted,
      payer: const PartyRef(kind: PartyKind.user, id: me),
      recipient: const PartyRef(kind: PartyKind.user, id: carol),
    );
    final state = TabbyDashboardState(
      viewerUserId: me,
      tabs: [
        group([bill(me, bob), bill(carol, me), payment]),
      ],
      activities: const [],
      reminders: const [],
    );
    expect(state.youOweCentavos, 5000);
    final confirmed = state.copyWith(
      tabs: [
        group([
          bill(me, bob),
          bill(carol, me),
          payment.copyWith(status: TransactionStatus.settled),
        ]),
      ],
    );
    expect(confirmed.youOweCentavos, 0);
    expect(confirmed.youAreOwedCentavos, 5000);
  });
  test('existing disputed server rows stay visible but do not count toward balances', () {
    expect(
      SupabaseTabbyRepository.unmapTransactionStatus('disputed'),
      TransactionStatus.disputed,
    );
    final entries = [
      bill(me, bob, status: TransactionStatus.disputed),
      bill(carol, me, status: TransactionStatus.cancelled),
    ];
    final state = TabbyDashboardState(
      viewerUserId: me,
      tabs: [group(entries)],
      activities: const [],
      reminders: const [],
    );
    expect(state.youAreOwedCentavos, 0);
    expect(state.youOweCentavos, 0);
    expect(MockTabbyRepository.calculateNetBalance(entries, me), 0);
    expect(
      LedgerEntry.fromMap(entries.first.toMap()).status,
      TransactionStatus.disputed,
    );
    expect(state.tabs.single.entries.length, 2);
  });
  testWidgets(
    'dashboard labels obligations and changes actual activity by selected period',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final n = TabbyNotifier(loadInitialData: false);
      n.state = n.state.copyWith(
        activities: [
          activity('RecentActor', now),
          activity('EarlierMonthActor', DateTime(2026, 11, 1)),
          activity('PriorMonthActor', DateTime(2026, 10, 31)),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [tabbyProvider.overrideWith((ref) => n)],
          child: MaterialApp(home: HomeDashboardScreen(now: () => now)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nothing outstanding'), findsOneWidget);
      expect(find.text('NET BALANCE'), findsOneWidget);
      expect(find.text('Received'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Total Expense'), findsNothing);
      expect(find.text('Total Balance'), findsNothing);
      expect(find.text('PriorMonthActor'), findsNothing);
      await tester.ensureVisible(find.text('Recent Activity'));
      expect(find.text('2 logs'), findsOneWidget);
      await tester.ensureVisible(find.text('Last 24h'));
      await tester.tap(find.text('Last 24h'));
      await tester.pumpAndSettle();
      expect(find.text('1 log'), findsOneWidget);
      expect(find.text('EarlierMonthActor'), findsNothing);
      await tester.ensureVisible(find.text('This month'));
      await tester.tap(find.text('This month'));
      await tester.pumpAndSettle();
      expect(find.text('2 logs'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
