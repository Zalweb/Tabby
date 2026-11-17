import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/utils/currency_formatter.dart';

void main() {
  group('CurrencyFormatter (ADR-001 Integer Centavos)', () {
    test('formats integer centavos to Philippine Peso string', () {
      expect(CurrencyFormatter.formatCentavos(10050), '₱100.50');
      expect(CurrencyFormatter.formatCentavos(0), '₱0.00');
      expect(CurrencyFormatter.formatCentavos(50), '₱0.50');
      expect(CurrencyFormatter.formatCentavos(1250050), '₱12,500.50');
    });

    test('handles negative debt amounts correctly', () {
      expect(CurrencyFormatter.formatCentavos(-25000), '-₱250.00');
      expect(CurrencyFormatter.formatCentavos(-500), '-₱5.00');
    });

    test('formats with explicit positive sign when requested', () {
      expect(
          CurrencyFormatter.formatCentavos(50000, showSign: true), '+₱500.00');
      expect(
          CurrencyFormatter.formatCentavos(-50000, showSign: true), '-₱500.00');
      expect(CurrencyFormatter.formatCentavos(0, showSign: true), '₱0.00');
    });

    test('parses formatted string inputs back to integer centavos', () {
      expect(CurrencyFormatter.parseToCentavos('100.50'), 10050);
      expect(CurrencyFormatter.parseToCentavos('₱1,250.50'), 125050);
      expect(CurrencyFormatter.parseToCentavos('₱12,500.50'), 1250050);
      expect(CurrencyFormatter.parseToCentavos('250'), 25000);
      expect(CurrencyFormatter.parseToCentavos('0'), 0);
      expect(CurrencyFormatter.parseToCentavos(''), 0);
      expect(CurrencyFormatter.parseToCentavos('-150.50'), -15050);
      expect(CurrencyFormatter.parseToCentavos('-0.50'), -50);
      expect(CurrencyFormatter.parseToCentavos('-₱1,250.50'), -125050);
      expect(CurrencyFormatter.parseToCentavos('-250'), -25000);
      expect(CurrencyFormatter.parseToCentavos('(150.50)'), -15050);
      expect(CurrencyFormatter.parseToCentavos('(₱1,250.50)'), -125050);
      expect(CurrencyFormatter.parseToCentavos('-0.05'), -5);
      expect(CurrencyFormatter.parseToCentavos('-0'), 0);
      expect(CurrencyFormatter.parseToCentavos('-.50'), -50);
    });

    test('rejects currency values with more than two decimal places', () {
      expect(
        () => CurrencyFormatter.parseToCentavos('10.125'),
        throwsA(isA<FormatException>()),
      );
      expect(CurrencyFormatter.tryParseToCentavos('10.125'), isNull);
    });

    test(
        'validates the complete PHP amount instead of accepting a valid suffix',
        () {
      for (final text in [
        'abc.50',
        '1.234',
        '1e3',
        '1e2.50',
        '1,00',
        '12,34,567.89',
        '1,,000',
        'NaN',
        'Infinity',
        '--1',
        '(1',
        '1)',
        'PHP',
        '₱',
        '1.2.3',
        '1 000',
        '1a',
        'abc',
        '1e309'
      ]) {
        expect(() => CurrencyFormatter.parseToCentavos(text),
            throwsFormatException,
            reason: text);
        expect(CurrencyFormatter.tryParseToCentavos(text), isNull,
            reason: text);
      }
    });
    test('parses PHP bounds exactly and rejects overflow', () {
      expect(
          CurrencyFormatter.parseToCentavos('PHP 999,999,999.99'), 99999999999);
      expect(CurrencyFormatter.parseToCentavos('₱ 1,250.5'), 125050);
      expect(CurrencyFormatter.parseToCentavos('.01'), 1);
      for (final text in [
        '1,000,000,000.00',
        '1000000000',
        '99999999999999999999999999999999.99'
      ]) {
        expect(() => CurrencyFormatter.parseToCentavos(text),
            throwsFormatException);
      }
    });

    test('guarantees zero floating-point drift on repeated centavo arithmetic',
        () {
      int totalCentavos = 0;
      // Add ₱0.10 (10 centavos) 1000 times
      for (int i = 0; i < 1000; i++) {
        totalCentavos += 10;
      }
      expect(totalCentavos, 10000); // exactly ₱100.00
      expect(CurrencyFormatter.formatCentavos(totalCentavos), '₱100.00');
    });
  });
}
