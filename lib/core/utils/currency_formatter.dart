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

  /// Parses a string representation (e.g. '150.50', '₱1,250.00', '250') into integer centavos.
  static int parseToCentavos(String input) {
    if (input.trim().isEmpty) return 0;
    // Remove symbols, commas, spaces
    final cleaned = input.replaceAll('₱', '').replaceAll(',', '').trim();
    if (cleaned.isEmpty) return 0;

    final parts = cleaned.split('.');
    final wholeStr = parts[0];
    final whole = int.tryParse(wholeStr) ?? 0;

    int centavos = whole * 100;
    if (parts.length > 1) {
      String fracStr = parts[1];
      if (fracStr.length > 2) {
        fracStr = fracStr.substring(0, 2);
      } else if (fracStr.length == 1) {
        fracStr = '${fracStr}0';
      }
      final frac = int.tryParse(fracStr) ?? 0;
      centavos += frac;
    }

    return centavos;
  }

  /// Converts accumulated keypad digits into centavos.
  /// E.g. digits '50000' -> 50000 centavos -> ₱500.00
  static int digitsToCentavos(String rawDigits) {
    if (rawDigits.isEmpty) return 0;
    return int.tryParse(rawDigits) ?? 0;
  }
}
