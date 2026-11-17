import 'package:intl/intl.dart';

/// Currency formatter enforcing ADR-001: Integer Centavo Precision.
/// 1 PHP = 100 centavos. Zero floating-point drift.
class CurrencyFormatter {
  CurrencyFormatter._();

  static final NumberFormat _pesoFormat = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  );

  static final NumberFormat _numberFormat = NumberFormat('#,##0.00', 'en_PH');

  /// Formats [centavos] (e.g. 125050) to formatted currency string (e.g. '₱1,250.50').
  /// If [showSign] is true, prefixes with '+' if positive.
  static String formatCentavos(
    int centavos, {
    bool includeSymbol = true,
    bool showSign = false,
  }) {
    final isNegative = centavos < 0;
    final absCentavos = centavos.abs();
    final whole = absCentavos ~/ 100;
    final fractional = absCentavos % 100;
    final doubleValue = whole + (fractional / 100.0);

    String formatted = includeSymbol
        ? _pesoFormat.format(doubleValue)
        : _numberFormat.format(doubleValue);

    if (isNegative) {
      return '-$formatted';
    } else if (showSign && centavos > 0) {
      return '+$formatted';
    }
    return formatted;
  }

  /// Parses a string representation (e.g. '150.50', '₱1,250.00', '250', '-150.50') into integer centavos.
  static const maxAmountCentavos = 99999999999;

  static int parseToCentavos(String input) {
    var value = input.trim();
    if (value.isEmpty) return 0;
    var negative = false;
    if (value.startsWith('(') && value.endsWith(')')) {
      negative = true;
      value = value.substring(1, value.length - 1).trim();
    }
    if (value.startsWith('-')) {
      if (negative) throw const FormatException('Enter a valid PHP amount.');
      negative = true;
      value = value.substring(1).trim();
    }
    value = value.replaceFirst(
        RegExp(r'^(?:PHP\s*|₱\s*)', caseSensitive: false), '');
    if (!RegExp(
            r'^(?:(?:[0-9]+|[1-9][0-9]{0,2}(?:,[0-9]{3})+)(?:\.[0-9]{0,2})?|\.[0-9]{1,2})$')
        .hasMatch(value)) {
      throw const FormatException(
          'Enter a valid PHP amount with up to two decimal places.');
    }
    final parts = value.replaceAll(',', '').split('.');
    final whole = BigInt.parse(parts[0].isEmpty ? '0' : parts[0]);
    final fraction = parts.length == 1 ? '00' : parts[1].padRight(2, '0');
    final amount = whole * BigInt.from(100) + BigInt.parse(fraction);
    if (amount > BigInt.from(maxAmountCentavos)) {
      throw const FormatException('The maximum amount is PHP 999,999,999.99.');
    }
    return negative ? -amount.toInt() : amount.toInt();
  }

  /// Parses a currency value without throwing for user-entered invalid text.
  /// Returns `null` when the value is empty, malformed, or has excess precision.
  static int? tryParseToCentavos(String input) {
    if (input.trim().isEmpty) return null;
    try {
      return parseToCentavos(input);
    } on FormatException {
      return null;
    }
  }

  /// Converts accumulated keypad digits into centavos.
  /// E.g. digits '50000' -> 50000 centavos -> ₱500.00
  static int digitsToCentavos(String rawDigits) {
    if (rawDigits.isEmpty) return 0;
    return int.tryParse(rawDigits) ?? 0;
  }
}
