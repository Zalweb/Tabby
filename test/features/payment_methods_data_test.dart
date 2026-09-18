import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/payment_methods/domain/payment_method.dart';

void main() {
  test('round trips a payment method with a QR path', () {
    const method = PaymentMethod(
      id: 'method-1',
      ownerUserId: 'owner-1',
      provider: 'gcash',
      displayName: 'GCash QR',
      accountLabel: '09171234567',
      qrStoragePath: 'owner-1/method-1.png',
      isDefault: true,
    );

    expect(PaymentMethod.fromMap(method.toMap()), method);
  });

  test('legacy fields create one preferred method', () {
    final methods = PaymentMethod.fromLegacyUser({
      'id': 'owner-1',
      'gcash_number': '09171234567',
      'maya_number': '',
      'qr_code_url': 'legacy/owner-1.png',
    });

    expect(methods, hasLength(1));
    expect(methods.single.provider, 'gcash');
    expect(methods.single.isDefault, isTrue);
  });
}
