import 'models.dart';

class PairObligation {
  const PairObligation(this.payerId, this.recipientId, this.amountCentavos);
  final String payerId;
  final String recipientId;
  final int amountCentavos;
}

/// Direct obligations only: no debt simplification through uninvolved members.
/// Positive means debtor owes creditor. Opposing expenses/payments offset only
/// the same immutable pair.
int pairOutstanding(List<LedgerEntry> entries, String debtor, String creditor) {
  var amount = 0;
  for (final e in entries) {
    if (e.status == TransactionStatus.cancelled ||
        e.status == TransactionStatus.disputed) {
      continue;
    }
    if (e.isPayment) {
      if (e.status != TransactionStatus.settled ||
          e.recipient?.kind != PartyKind.user ||
          (e.payer != null && e.payer!.kind != PartyKind.user)) {
        continue;
      }
      final payer = e.payer?.id ?? e.paidByUserId;
      if (payer == debtor && e.recipient?.id == creditor) {
        amount -= e.totalAmountCentavos;
      }
      if (payer == creditor && e.recipient?.id == debtor) {
        amount += e.totalAmountCentavos;
      }
    } else {
      if (e.paidByUserId == creditor) {
        amount += e.participants
            .where((p) => p.userId == debtor)
            .fold<int>(0, (n, p) => n + p.shareAmountCentavos);
      }
      if (e.paidByUserId == debtor) {
        amount -= e.participants
            .where((p) => p.userId == creditor)
            .fold<int>(0, (n, p) => n + p.shareAmountCentavos);
      }
    }
  }
  return amount;
}

List<PairObligation> groupObligations(BilateralTab tab) {
  final ids = tab.members.map((m) => m.id).toSet().toList()..sort();
  final result = <PairObligation>[];
  for (var i = 0; i < ids.length; i++) {
    for (var j = i + 1; j < ids.length; j++) {
      final amount = pairOutstanding(tab.entries, ids[i], ids[j]);
      if (amount > 0) result.add(PairObligation(ids[i], ids[j], amount));
      if (amount < 0) result.add(PairObligation(ids[j], ids[i], -amount));
    }
  }
  return result;
}
