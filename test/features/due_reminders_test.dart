import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/services/reminder_notification_id.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/data/tabby_local_cache.dart';
import 'package:tabby/features/tabs/domain/due_reminders.dart';
import 'package:tabby/features/tabs/domain/models.dart';

const me = 'user-me', bob = 'bob', carol = 'carol';
final due = DateTime(2026, 11, 2);
LedgerEntry bill(String id,
        {String payer = me,
        DateTime? date,
        int share = 5000,
        TransactionStatus status = TransactionStatus.pending,
        PartyRef? party}) =>
    LedgerEntry(
        id: id,
        tabId: 't',
        title: id,
        category: ExpenseCategory.food,
        totalAmountCentavos: share * 2,
        myShareCentavos: share,
        counterpartShareCentavos: share,
        paidByUserId: payer,
        paidByName: payer,
        date: DateTime(2026, 11, 1),
        dueDate: date,
        status: status,
        payer: party);
BilateralTab tab(List<LedgerEntry> entries,
        {int net = 5000, bool contact = false, String other = bob}) =>
    BilateralTab(
        id: 't',
        counterpart:
            TabbyUser(id: other, displayName: 'Other', email: '', phone: ''),
        entries: entries,
        netBalanceCentavos: net,
        itemCount: entries.length,
        lastUpdated: DateTime(2026),
        isTabOnlyParticipant: contact);
LedgerEntry groupBill(String payer, String debtor) =>
    bill('$payer-$debtor', payer: payer, date: due).copyWith(participants: [
      ParticipantShare(
          userId: payer, name: payer, shareAmountCentavos: 5000, isPayer: true),
      ParticipantShare(userId: debtor, name: debtor, shareAmountCentavos: 5000)
    ]);
BilateralTab group(List<LedgerEntry> entries) => tab(entries, net: 0)
        .copyWith(isGroupTab: true, groupName: 'Group', members: const [
      TabbyUser(id: me, displayName: 'You', email: '', phone: ''),
      TabbyUser(id: bob, displayName: 'Bob', email: '', phone: ''),
      TabbyUser(id: carol, displayName: 'Carol', email: '', phone: '')
    ]);
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
      'zero aggregate after a partial group receipt retains both pair reminders',
      () async {
    final n = TabbyNotifier(loadInitialData: false);
    addTearDown(n.dispose);
    final larger = groupBill(me, bob).copyWith(
        totalAmountCentavos: 20000,
        myShareCentavos: 10000,
        counterpartShareCentavos: 10000,
        participants: [
          const ParticipantShare(
              userId: me,
              name: 'You',
              shareAmountCentavos: 10000,
              isPayer: true),
          const ParticipantShare(
              userId: bob, name: 'Bob', shareAmountCentavos: 10000),
        ]);
    n.state = n.state.copyWith(tabs: [
      group([larger, groupBill(carol, me)]).copyWith(netBalanceCentavos: 5000)
    ]);
    await n.refreshDueReminders();
    await n.settleGroupPair(
        tabId: 't',
        counterpartyUserId: bob,
        amountCentavos: 5000,
        method: PaymentMethod.cash,
        isPayingMe: true);
    expect(n.state.tabs.single.netBalanceCentavos, 0);
    expect(n.state.reminders.length, 2);
    expect(n.state.mascotMessage, isNot(contains('completely settled')));
    expect(n.state.mascotMessage, isNot(contains('is clear')));
  });
  test('recipient confirmation removes original due reminder before a refresh',
      () async {
    final changes = <List<UpcomingReminder>>[];
    final n = TabbyNotifier(
        loadInitialData: false,
        paymentDecision: (id, _, __) async => id,
        reminderScheduler: (_, next, __) async {
          changes.add(List.of(next));
        });
    addTearDown(n.dispose);
    final payment = bill('pay', payer: bob).copyWith(
        isPayment: true,
        totalAmountCentavos: 5000,
        status: TransactionStatus.paymentSubmitted,
        payer: const PartyRef(kind: PartyKind.user, id: bob),
        recipient: const PartyRef(kind: PartyKind.user, id: me));
    n.state = n.state.copyWith(tabs: [
      tab([bill('original', date: due), payment])
    ]);
    await n.refreshDueReminders();
    expect(n.state.reminders.length, 1);
    await n.decidePayment('pay', confirm: true);
    expect(n.state.reminders, isEmpty);
    expect(changes.last, isEmpty);
    expect(n.state.tabs.single.entries.first.dueDate, due);
    expect(n.state.tabs.single.entries.length, 2);
  });
  test('settled pair retains original dated entry without recreating reminder',
      () {
    expect(
        deriveDueReminders([
          tab([bill('old', date: due)], net: 0)
        ], me),
        isEmpty);
    expect(
        deriveDueReminders([
          tab([bill('old', date: due)])
        ], me)
            .single
            .amountCentavos,
        5000);
  });
  test('partial pair balance covers oldest due obligations first', () {
    final reminders = deriveDueReminders([
      tab([
        bill('later', date: due.add(const Duration(days: 1))),
        bill('earlier', date: due)
      ], net: 7000)
    ], me);
    expect(reminders.map((r) => r.sourceEntryId), ['earlier', 'later']);
    expect(reminders.map((r) => r.amountCentavos), [2000, 5000]);
    expect(reminders.fold<int>(0, (sum, r) => sum + r.amountCentavos), 7000);
  });
  test('undated balance remains without reviving a covered dated bill', () {
    final reminders = deriveDueReminders([
      tab([bill('dated', date: due), bill('undated')], net: 4000)
    ], me);
    expect(reminders, isEmpty);
  });
  test(
      'cancelled/disputed expenses and payment due dates never create reminders',
      () {
    final rows = [
      bill('cancelled', date: due, status: TransactionStatus.cancelled),
      bill('disputed', date: due, status: TransactionStatus.disputed),
      bill('payment', date: due)
          .copyWith(isPayment: true, status: TransactionStatus.settled)
    ];
    expect(deriveDueReminders([tab(rows)], me), isEmpty);
  });
  test(
      'zero-net group keeps actual pair reminders and settlement clears only its pair',
      () {
    final entries = [groupBill(me, bob), groupBill(carol, me)];
    final initial = deriveDueReminders([group(entries)], me);
    expect(initial.length, 2);
    expect(initial.map((r) => r.friendName).toSet(), {'Bob', 'Carol'});
    final payment = bill('pay').copyWith(
        isPayment: true,
        totalAmountCentavos: 5000,
        status: TransactionStatus.settled,
        payer: const PartyRef(kind: PartyKind.user, id: me),
        recipient: const PartyRef(kind: PartyKind.user, id: carol));
    final after = deriveDueReminders([
      group([...entries, payment])
    ], me);
    expect(after.single.counterparty,
        const PartyRef(kind: PartyKind.user, id: bob));
    expect(after.single.isIWhoOwe, isFalse);
    expect(
        after.single.id, initial.firstWhere((r) => r.friendName == 'Bob').id);
    final pending = deriveDueReminders([
      group([
        ...entries,
        payment.copyWith(status: TransactionStatus.paymentSubmitted)
      ])
    ], me);
    expect(pending.length, 2);
  });
  test('contact/user namespaces survive same raw ID and cache serialization',
      () {
    const contact = PartyRef(kind: PartyKind.contact, id: me);
    expect(contact, isNot(const PartyRef(kind: PartyKind.user, id: me)));
    final reminder = deriveDueReminders([
      tab([bill('contact-paid', payer: me, date: due, party: contact)],
          net: -5000, contact: true, other: me)
    ], me)
        .single;
    expect(reminder.counterparty, contact);
    expect(reminder.isIWhoOwe, isTrue);
    expect(UpcomingReminder.fromMap(reminder.toMap()).counterparty, contact);
  });
  test('notification identifiers use stable digest values', () {
    expect(reminderNotificationId('abc'), 0x3a7816bf);
    expect(reminderNotificationId('abc'), reminderNotificationId('abc'));
    expect(
        reminderNotificationId('abc'), isNot(reminderNotificationId('other')));
  });
  test(
      'cash settlement cancels derived alarms and stale cache cannot restore them',
      () async {
    final updates = <(List<UpcomingReminder>, List<UpcomingReminder>)>[];
    Future<void> scheduler(List<UpcomingReminder> old,
        List<UpcomingReminder> next, String actor) async {
      expect(actor, me);
      updates.add((List.of(old), List.of(next)));
    }

    final n =
        TabbyNotifier(loadInitialData: false, reminderScheduler: scheduler);
    addTearDown(n.dispose);
    await n.addExpense(
        counterpartId: 'contact',
        counterpartName: 'Contact',
        title: 'Dated bill',
        totalAmountCentavos: 10000,
        category: ExpenseCategory.food,
        paidByMe: true,
        isEqualSplit: true,
        dueDate: due);
    final original = n.state.reminders.single;
    await n.settleTab(
        tabId: n.state.tabs.single.id,
        amountCentavos: 5000,
        method: PaymentMethod.cash,
        isPayingMe: true);
    expect(n.state.reminders, isEmpty);
    expect(updates.last.$1.single.id, original.id);
    expect(updates.last.$2, isEmpty);
    await TabbyLocalCache.saveReminders(
        [original]); // Simulate stale prior cache.
    final restarted =
        TabbyNotifier(loadInitialData: false, reminderScheduler: scheduler);
    addTearDown(restarted.dispose);
    await restarted.refreshTabs();
    expect(restarted.state.tabs.single.entries.length, 2);
    expect(restarted.state.reminders, isEmpty);
    expect(updates.expand((u) => u.$1).any((r) => r.id == original.id), isTrue);
    await restarted.refreshTabs();
    expect(restarted.state.reminders, isEmpty);
  });
  test('alarm failure cannot roll back the acknowledged local cash ledger',
      () async {
    final n = TabbyNotifier(
        loadInitialData: false,
        reminderScheduler: (_, __, ___) async =>
            throw StateError('synthetic OS failure'));
    addTearDown(n.dispose);
    await n.addExpense(
        counterpartId: 'contact',
        counterpartName: 'Contact',
        title: 'Dated',
        totalAmountCentavos: 10000,
        category: ExpenseCategory.food,
        paidByMe: true,
        isEqualSplit: true,
        dueDate: due);
    await n.settleTab(
        tabId: n.state.tabs.single.id,
        amountCentavos: 5000,
        method: PaymentMethod.cash,
        isPayingMe: true);
    expect(n.state.tabs.single.netBalanceCentavos, 0);
    expect(n.state.tabs.single.entries.length, 2);
    expect(n.state.reminders, isEmpty);
  });
}
