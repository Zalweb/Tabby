import 'models.dart';
import 'share_allocation.dart';
import '../../../core/utils/currency_formatter.dart';

class TabValidationException implements Exception {
  final String message;

  const TabValidationException(this.message);

  @override
  String toString() => message;
}

class LedgerValidation {
  LedgerValidation._();

  /// Explicit plain amounts use the existing expense participant contract.
  /// Include zero-share payers; names never establish financial identity.
  static List<ParticipantShare> customShares({
    required int total,
    required List<TabbyUser> members,
    required String payerId,
    required Map<String, int> amounts,
  }) {
    final ids = members.map((m) => m.id).toSet();
    if (total <= 0 ||
        total > CurrencyFormatter.maxAmountCentavos ||
        members.length < 2 ||
        ids.length != members.length ||
        ids.contains('') ||
        !ids.contains(payerId) ||
        amounts.length != ids.length ||
        !amounts.keys.every(ids.contains) ||
        amounts.values.any((v) => v < 0) ||
        amounts.values.fold<int>(0, (a, b) => a + b) != total) {
      throw const TabValidationException(
        'Enter an amount for each person. Their shares must add up to the total.',
      );
    }
    return members
        .map(
          (m) => ParticipantShare(
            userId: m.id,
            name: m.displayName,
            shareAmountCentavos: amounts[m.id]!,
            isPayer: m.id == payerId,
          ),
        )
        .toList();
  }

  static List<ParticipantShare> groupShares({
    required int total,
    required List<TabbyUser> members,
    required String payerId,
    required bool equalSplit,
  }) {
    if (total <= 0 ||
        total > CurrencyFormatter.maxAmountCentavos ||
        members.length < 2 ||
        members.map((m) => m.id).toSet().length != members.length ||
        members.any((m) => m.id.isEmpty) ||
        !members.any((m) => m.id == payerId)) {
      throw const TabValidationException(
        'Refresh the group and select a member who paid.',
      );
    }
    final shares = allocateEqualShares(
      total,
      members.where((m) => equalSplit || m.id != payerId).map((m) => m.id),
    );
    return members
        .map(
          (m) => ParticipantShare(
            userId: m.id,
            name: m.displayName,
            shareAmountCentavos: shares[m.id] ?? 0,
            isPayer: m.id == payerId,
          ),
        )
        .toList();
  }

  static void validateExpense({
    required int totalAmountCentavos,
    required bool isEqualSplit,
    required int participantCount,
    required bool paidByMe,
    required String currentUserId,
    required String counterpartId,
    String? payerId,
    String? payerName,
  }) {
    if (totalAmountCentavos <= 0) {
      throw const TabValidationException(
        'The expense amount must be greater than PHP 0.00.',
      );
    }
    if (totalAmountCentavos > CurrencyFormatter.maxAmountCentavos) {
      throw const TabValidationException(
        'The maximum amount is PHP 999,999,999.99.',
      );
    }
    if (participantCount < 2) {
      throw const TabValidationException(
        'A split must include at least two participants.',
      );
    }
    if (paidByMe) {
      if (payerId != null && payerId.isNotEmpty && payerId != currentUserId) {
        throw const TabValidationException(
          'The payer must match the selected payment direction.',
        );
      }
      return;
    }

    final selectedPayerId = payerId == null || payerId.trim().isEmpty
        ? counterpartId
        : payerId;
    if (selectedPayerId == currentUserId) {
      throw const TabValidationException(
        'The payer must be the other participant when they paid.',
      );
    }
    if (selectedPayerId.trim().isEmpty) {
      throw const TabValidationException(
        'Select the friend who paid this expense.',
      );
    }
    if (payerId != null &&
        payerId.trim().isNotEmpty &&
        payerName != null &&
        payerName.trim().isEmpty) {
      throw const TabValidationException(
        'The payer name is required when they paid.',
      );
    }
    if (!isEqualSplit &&
        selectedPayerId != counterpartId &&
        participantCount == 2) {
      throw const TabValidationException(
        'The payer must match the tab participant.',
      );
    }
  }

  static void validatePayment({
    required int amountCentavos,
    required int netBalanceCentavos,
    required bool isPayingMe,
  }) {
    if (amountCentavos > CurrencyFormatter.maxAmountCentavos) {
      throw const TabValidationException(
        'The maximum amount is PHP 999,999,999.99.',
      );
    }
    if (amountCentavos <= 0) {
      throw const TabValidationException(
        'The payment amount must be greater than PHP 0.00.',
      );
    }
    if (netBalanceCentavos == 0) {
      throw const TabValidationException('This tab is already settled.');
    }

    final expectedDirection = netBalanceCentavos > 0;
    if (isPayingMe != expectedDirection) {
      throw const TabValidationException(
        'The payment direction does not match this tab balance.',
      );
    }
    if (amountCentavos > netBalanceCentavos.abs()) {
      throw const TabValidationException(
        'The payment cannot be greater than the remaining tab balance.',
      );
    }
  }

  static int equalSplitShare({
    required int totalAmountCentavos,
    required int participantCount,
  }) {
    if (participantCount < 2 || totalAmountCentavos <= 0) {
      throw const TabValidationException('The split details are invalid.');
    }
    final share = totalAmountCentavos ~/ participantCount;
    final remainder = totalAmountCentavos - (share * participantCount);
    if (remainder < 0 || remainder >= participantCount) {
      throw const TabValidationException('The split could not be balanced.');
    }
    return share;
  }
}
