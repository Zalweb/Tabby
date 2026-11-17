import 'dart:math' as math;
import 'models.dart';
import 'pair_obligations.dart';

/// Reminder allocation is a presentation policy for running pair balances:
/// opposing bills/confirmed payments cover the oldest due bills first, then
/// undated bills. It never changes the ledger or claims a per-bill payment link.
List<UpcomingReminder> deriveDueReminders(
    List<BilateralTab> tabs, String actorId) {
  final result = <UpcomingReminder>[];
  final actor = PartyRef(kind: PartyKind.user, id: actorId);
  for (final tab in tabs) {
    final pairs = <(PartyRef, PartyRef, int)>[];
    if (tab.isGroupTab) {
      for (final pair in groupObligations(tab)) {
        if (pair.payerId != actorId && pair.recipientId != actorId) continue;
        pairs.add((
          PartyRef(kind: PartyKind.user, id: pair.payerId),
          PartyRef(kind: PartyKind.user, id: pair.recipientId),
          pair.amountCentavos
        ));
      }
    } else {
      final other = PartyRef(
          kind: tab.isTabOnlyParticipant ? PartyKind.contact : PartyKind.user,
          id: tab.counterpart.id);
      if (tab.netBalanceCentavos > 0) {
        pairs.add((other, actor, tab.netBalanceCentavos));
      }
      if (tab.netBalanceCentavos < 0) {
        pairs.add((actor, other, -tab.netBalanceCentavos));
      }
    }
    for (final (debtor, creditor, outstanding) in pairs) {
      final bills = <(LedgerEntry, int)>[];
      for (final entry in tab.entries) {
        if (entry.isPayment ||
            (entry.revision != null && !entry.revision!.isReminderCandidate) ||
            entry.status == TransactionStatus.cancelled ||
            entry.status == TransactionStatus.disputed) {
          continue;
        }
        final payer = entry.payer ??
            PartyRef(
                kind: !tab.isGroupTab &&
                        tab.isTabOnlyParticipant &&
                        entry.paidByUserId == tab.counterpart.id
                    ? PartyKind.contact
                    : PartyKind.user,
                id: entry.paidByUserId);
        if (payer != creditor) continue;
        final amount = tab.isGroupTab
            ? entry.participants
                .where((party) => party.userId == debtor.id)
                .fold<int>(0, (sum, party) => sum + party.shareAmountCentavos)
            : (debtor == actor
                ? entry.myShareCentavos
                : entry.counterpartShareCentavos);
        if (amount > 0) bills.add((entry, amount));
      }
      bills.sort((a, b) {
        final ad = a.$1.dueDate, bd = b.$1.dueDate;
        if (ad == null && bd != null) return 1;
        if (ad != null && bd == null) return -1;
        final time = (ad ?? a.$1.date).compareTo(bd ?? b.$1.date);
        return time != 0 ? time : a.$1.id.compareTo(b.$1.id);
      });
      var covered = math.max(
          0, bills.fold<int>(0, (sum, bill) => sum + bill.$2) - outstanding);
      for (final (entry, gross) in bills) {
        final applied = math.min(covered, gross);
        covered -= applied;
        final remaining = gross - applied;
        if (remaining <= 0 || entry.dueDate == null) continue;
        final other = debtor == actor ? creditor : debtor;
        final friendName = tab.isGroupTab
            ? tab.members
                .where((member) => member.id == other.id)
                .firstOrNull
                ?.displayName
            : tab.counterpart.displayName;
        if (friendName == null) continue;
        result.add(UpcomingReminder(
            id: 'due:$actorId:${tab.id}:${debtor.kind.name}:${debtor.id}:${creditor.kind.name}:${creditor.id}:${entry.id}',
            tabId: tab.id,
            friendName: friendName,
            description: entry.title,
            amountCentavos: remaining,
            dueDate: entry.dueDate!,
            isIWhoOwe: debtor == actor,
            counterparty: other,
            sourceEntryId: entry.id));
      }
    }
  }
  result.sort((a, b) {
    final date = a.dueDate.compareTo(b.dueDate);
    return date != 0 ? date : a.id.compareTo(b.id);
  });
  return result;
}
