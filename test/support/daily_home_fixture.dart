import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/domain/models.dart';

import 'warm_design_fixture.dart';

final dailyFixtureNow = DateTime(2026, 11, 17, 12);
TabbyNotifier dailyHomeLedger() {
  final date = dailyFixtureNow;
  final expense = LedgerEntry(
    id: 'daily-expense',
    tabId: 'warm-tab',
    title: 'Trip to Baguio',
    category: ExpenseCategory.other,
    totalAmountCentavos: 50000,
    myShareCentavos: 25000,
    counterpartShareCentavos: 25000,
    paidByUserId: warmOwner.id,
    paidByName: warmOwner.displayName,
    date: date.subtract(const Duration(days: 1)),
    status: TransactionStatus.acknowledged,
    participants: [
      ParticipantShare(
        userId: warmOwner.id,
        name: warmOwner.displayName,
        shareAmountCentavos: 25000,
        isPayer: true,
      ),
      ParticipantShare(
        userId: warmFriend.id,
        name: warmFriend.displayName,
        shareAmountCentavos: 25000,
      ),
    ],
  );
  final payment = LedgerEntry(
    id: 'daily-confirmed',
    tabId: 'warm-tab',
    title: 'Recorded payment',
    category: ExpenseCategory.other,
    totalAmountCentavos: 12500,
    myShareCentavos: 0,
    counterpartShareCentavos: 0,
    paidByUserId: warmFriend.id,
    paidByName: warmFriend.displayName,
    date: date.subtract(const Duration(hours: 2)),
    status: TransactionStatus.settled,
    isPayment: true,
    payer: PartyRef(kind: PartyKind.user, id: warmFriend.id),
    recipient: PartyRef(kind: PartyKind.user, id: warmOwner.id),
  );
  final n = TabbyNotifier(loadInitialData: false);
  n.state = n.state.copyWith(
    viewerUserId: warmOwner.id,
    tabs: [
      BilateralTab(
        id: 'warm-tab',
        counterpart: warmFriend,
        isGroupTab: true,
        groupName: 'Trip to Baguio',
        members: const [warmOwner, warmFriend],
        netBalanceCentavos: 12500,
        itemCount: 2,
        entries: [expense, payment],
        lastUpdated: date,
      ),
      BilateralTab(
        id: 'daily-clear-1',
        counterpart: const TabbyUser(
          id: 'daily-clear-user-1',
          displayName: 'Jordan',
          email: '',
          phone: '',
        ),
        netBalanceCentavos: 0,
        itemCount: 0,
        entries: const [],
        lastUpdated: date,
      ),
      BilateralTab(
        id: 'daily-clear-2',
        counterpart: const TabbyUser(
          id: 'daily-clear-user-2',
          displayName: 'Sam',
          email: '',
          phone: '',
        ),
        netBalanceCentavos: 0,
        itemCount: 0,
        entries: const [],
        lastUpdated: date,
      ),
    ],
    reminders: [
      UpcomingReminder(
        id: 'daily-reminder',
        tabId: 'warm-tab',
        friendName: 'Alex',
        description: 'Trip to Baguio',
        amountCentavos: 12500,
        dueDate: date.add(const Duration(days: 1)),
        isIWhoOwe: false,
        counterparty: PartyRef(kind: PartyKind.user, id: warmFriend.id),
      ),
    ],
    activities: [
      TabbyActivity(
        id: 'daily-activity-1',
        actorName: 'Alex',
        description: 'Payment confirmed',
        amountCentavos: 12500,
        timestamp: date.subtract(const Duration(hours: 2)),
      ),
      TabbyActivity(
        id: 'daily-activity-2',
        actorName: 'You',
        description: 'Created Trip to Baguio',
        amountCentavos: 0,
        timestamp: date.subtract(const Duration(hours: 5)),
      ),
      TabbyActivity(
        id: 'daily-activity-3',
        actorName: 'You',
        description: 'Tab cleared',
        amountCentavos: 0,
        timestamp: date.subtract(const Duration(days: 1)),
      ),
    ],
  );
  return n;
}
