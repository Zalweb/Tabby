import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/tabs/domain/ledger_validation.dart';

void main() {
  group('LedgerValidation', () {
    test('rejects invalid group split counts and amounts', () {
      expect(
        () => LedgerValidation.validateExpense(
          totalAmountCentavos: 100,
          isEqualSplit: true,
          participantCount: 1,
          paidByMe: true,
          currentUserId: 'me',
          counterpartId: 'friend',
        ),
        throwsA(isA<TabValidationException>()),
      );
    });

    test('requires a distinct payer when the other party paid', () {
      expect(
        () => LedgerValidation.validateExpense(
          totalAmountCentavos: 100,
          isEqualSplit: true,
          participantCount: 2,
          paidByMe: false,
          currentUserId: 'me',
          counterpartId: 'friend',
          payerId: 'me',
          payerName: 'Me',
        ),
        throwsA(isA<TabValidationException>()),
      );
    });

    test(
        'defaults counterpart as payer when counterpart-paid fields are omitted',
        () {
      expect(
        () => LedgerValidation.validateExpense(
          totalAmountCentavos: 100,
          isEqualSplit: false,
          participantCount: 2,
          paidByMe: false,
          currentUserId: 'me',
          counterpartId: 'friend',
        ),
        returnsNormally,
      );
    });

    test('rejects payment direction and overpayment', () {
      expect(
        () => LedgerValidation.validatePayment(
          amountCentavos: 100,
          netBalanceCentavos: -500,
          isPayingMe: true,
        ),
        throwsA(isA<TabValidationException>()),
      );
      expect(
        () => LedgerValidation.validatePayment(
          amountCentavos: 600,
          netBalanceCentavos: 500,
          isPayingMe: true,
        ),
        throwsA(isA<TabValidationException>()),
      );
    });

    test('keeps equal split arithmetic in integer centavos', () {
      expect(
        LedgerValidation.equalSplitShare(
          totalAmountCentavos: 100,
          participantCount: 3,
        ),
        33,
      );
    });
  });
}
