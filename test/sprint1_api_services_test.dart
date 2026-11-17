import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/services/tabby_api_services.dart';
import 'package:tabby/core/utils/qr_code_renderer.dart';
import 'package:tabby/features/payment_methods/domain/payment_method.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // 1. QR codes — rendered on-device, never through a third-party API
  // ─────────────────────────────────────────────────────────────────────────

  group('renderQrPng', () {
    testWidgets('renders PNG bytes for an account number', (tester) async {
      // Picture.toImage needs the real event loop.
      final bytes = await tester.runAsync(
        () => renderQrPng('09171234567', size: 120),
      );
      expect(bytes, isNotNull);
      expect(bytes!.length, greaterThan(100));
    });

    testWidgets('renders PNG bytes for a payment URI', (tester) async {
      final bytes = await tester.runAsync(
        () => renderQrPng('gcash://pay?account=09171234567'),
      );
      expect(bytes, isNotNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 2. Philippine phone validation — offline regex
  // ─────────────────────────────────────────────────────────────────────────

  group('TabbyApiServices.validatePhilippinePhone (offline regex)', () {
    String? validate(String phone) =>
        TabbyApiServices.validatePhilippinePhone(phone);

    test('accepts 11-digit 09xx number', () {
      expect(validate('09171234567'), isNull);
    });

    test('accepts +63 prefixed number', () {
      expect(validate('+639171234567'), isNull);
    });

    test('accepts 63-prefixed 12-digit number (no leading +)', () {
      expect(validate('639171234567'), isNull);
    });

    test('accepts number with dashes and spaces', () {
      expect(validate('0917 123-4567'), isNull);
    });

    test('rejects too short number', () {
      expect(validate('1234'), isNotNull);
    });

    test('rejects empty string', () {
      expect(validate(''), isNotNull);
    });

    test('rejects landline-formatted number (02 prefix)', () {
      // A Manila landline: 028-123-4567 → 10 digits starting with 2, not 9
      expect(validate('0281234567'), isNotNull);
    });

    test('rejects all-zeros', () {
      expect(validate('00000000000'), isNotNull);
    });

    test('returns null (valid) when number passes', () {
      expect(validate('09991234567'), isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 3. Email — local shape + disposable-domain check
  // ─────────────────────────────────────────────────────────────────────────

  group('TabbyApiServices.isEmailAcceptable', () {
    test('rejects empty and whitespace-only input', () {
      expect(TabbyApiServices.isEmailAcceptable(''), isFalse);
      expect(TabbyApiServices.isEmailAcceptable('   '), isFalse);
    });

    test('rejects malformed addresses', () {
      expect(TabbyApiServices.isEmailAcceptable('juan'), isFalse);
      expect(TabbyApiServices.isEmailAcceptable('juan@'), isFalse);
      expect(TabbyApiServices.isEmailAcceptable('juan@example'), isFalse);
      expect(TabbyApiServices.isEmailAcceptable('juan @example.com'), isFalse);
    });

    test('accepts ordinary addresses', () {
      expect(TabbyApiServices.isEmailAcceptable('juan@example.com'), isTrue);
      expect(
        TabbyApiServices.isEmailAcceptable('  Maria.Clara+tabby@yahoo.com  '),
        isTrue,
      );
    });

    test('flags known disposable domains case-insensitively', () {
      expect(
        TabbyApiServices.isEmailAcceptable('burner@Mailinator.com'),
        isFalse,
      );
      expect(TabbyApiServices.isEmailAcceptable('x@yopmail.com'), isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 4. Currency-api — PHP/USD rate and display string
  // ─────────────────────────────────────────────────────────────────────────

  group('TabbyApiServices.centavosToUsdDisplay', () {
    setUp(() => TabbyApiServices.clearRateCache());

    test('returns null for zero centavos', () async {
      final result = await TabbyApiServices.centavosToUsdDisplay(0);
      expect(result, isNull);
    });

    test('does not throw on network failure (returns null or stale)', () async {
      // In unit tests there is no real network. The method must not throw.
      final result = await TabbyApiServices.centavosToUsdDisplay(10000).timeout(
        const Duration(seconds: 10),
        onTimeout: () => null,
      );
      // null is acceptable (no rate available); a formatted string is also valid.
      expect(result == null || result.startsWith('≈ \$'), isTrue);
    });

    test('returns null on error without crashing', () async {
      // Verify clearRateCache works and method handles cache miss gracefully.
      TabbyApiServices.clearRateCache();
      // No exception expected:
      await expectLater(
        TabbyApiServices.centavosToUsdDisplay(50000),
        completes,
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 5. PaymentMethodDraft — QR payload carried as bytes
  // ─────────────────────────────────────────────────────────────────────────

  group('PaymentMethodDraft.hasQr', () {
    test('is true when PNG bytes are present', () {
      final draft = PaymentMethodDraft(
        provider: 'gcash',
        displayName: 'My GCash QR',
        accountLabel: '09171234567',
        qrBytes: Uint8List.fromList([1, 2, 3]),
      );
      expect(draft.hasQr, isTrue);
    });

    test('is false without bytes', () {
      const draft = PaymentMethodDraft(
        provider: 'gcash',
        displayName: 'My GCash',
        accountLabel: '09171234567',
      );
      expect(draft.hasQr, isFalse);
    });
  });
}
