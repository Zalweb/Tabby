class TabValidationException implements Exception {
  final String message;

  const TabValidationException(this.message);

  @override
  String toString() => message;
}

class LedgerValidation {
  LedgerValidation._();

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

    if (payerId == null || payerId.trim().isEmpty) {
      throw const TabValidationException(
        'Select the friend who paid this expense.',
      );
    }
    if (payerId == currentUserId) {
      throw const TabValidationException(
        'The payer must be the other participant when they paid.',
      );
    }
    if (payerName == null || payerName.trim().isEmpty) {
      throw const TabValidationException(
        'The payer name is required when they paid.',
      );
    }
    if (!isEqualSplit && payerId != counterpartId && participantCount == 2) {
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
    if (amountCentavos <= 0) {
      throw const TabValidationException(
        'The payment amount must be greater than PHP 0.00.',
      );
    }
    if (netBalanceCentavos == 0) {
      throw const TabValidationException(
        'This tab is already settled.',
      );
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
