import 'package:flutter/foundation.dart';

import 'models.dart';

/// Similarity is a review hint, never a uniqueness constraint or write.
class ExpenseDraftFingerprint {
  ExpenseDraftFingerprint({
    required this.tabId,
    required this.amountCentavos,
    required String description,
    required this.category,
    required this.payerId,
    required DateTime date,
    required Map<String, int> shares,
  }) : description = normalize(description),
       date = date.toLocal(),
       shares = Map.unmodifiable(shares);

  final String tabId, description, payerId;
  final int amountCentavos;
  final ExpenseCategory category;
  final DateTime date;
  final Map<String, int> shares;
  static String normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  bool matches(
    LedgerEntry entry, {
    required String viewerId,
    required String counterpartId,
    String? operationId,
  }) {
    final day = entry.date.toLocal();
    if (entry.tabId != tabId ||
        entry.isPayment ||
        entry.status == TransactionStatus.cancelled ||
        (entry.revision != null && entry.revision!.role != 'replacement') ||
        entry.id == 'entry-$operationId' ||
        entry.totalAmountCentavos != amountCentavos ||
        normalize(entry.title) != description ||
        entry.category != category ||
        entry.paidByUserId != payerId ||
        day.year != date.year ||
        day.month != date.month ||
        day.day != date.day) {
      return false;
    }
    final existing = entry.participants.isNotEmpty
        ? {for (final p in entry.participants) p.userId: p.shareAmountCentavos}
        : {
            viewerId: entry.myShareCentavos,
            counterpartId: entry.counterpartShareCentavos,
          };
    return mapEquals(existing, shares);
  }
}
