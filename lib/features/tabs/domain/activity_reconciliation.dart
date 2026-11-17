import 'package:flutter/material.dart';
import 'models.dart';

/// Only an explicit operation result may equate different activity IDs.
/// Callers place authoritative server rows first for repeated exact IDs.
List<TabbyActivity> reconcileActivityIds(Iterable<TabbyActivity> rows,
    {Map<String, String> mappings = const {}}) {
  final seen = <String>{};
  final result = <TabbyActivity>[];
  for (final row in rows) {
    final id = mappings[row.id] ?? row.id;
    if (id.isNotEmpty && !seen.add(id)) continue;
    result.add(id == row.id ? row : row.copyWith(id: id));
  }
  return result;
}

TabbyActivity activityForEntry(
    LedgerEntry entry, String actorId, String counterpartName) {
  final paymentStatus = switch (entry.status) {
    TransactionStatus.settled => 'Payment confirmed',
    TransactionStatus.cancelled => 'Payment rejected',
    _ => 'Payment submitted',
  };
  return TabbyActivity(
      id: entry.id,
      actorName: entry.paidByName.isNotEmpty
          ? entry.paidByName
          : (entry.paidByUserId == actorId ? 'You' : counterpartName),
      description:
          entry.isPayment ? '$paymentStatus: ${entry.title}' : entry.title,
      amountCentavos: entry.totalAmountCentavos,
      timestamp: entry.date,
      icon: entry.isPayment ? 'payment' : entry.category.name,
      iconData:
          entry.isPayment ? Icons.payments_outlined : entry.category.icon);
}
