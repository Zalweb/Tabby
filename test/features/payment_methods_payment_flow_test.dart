import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/payment_methods/application/payment_methods_provider.dart';

void main() {
  test('tab payment method request carries the authorization scope', () {
    const request = TabPaymentMethodRequest('tab-1', 'payee-1');

    expect(request.tabId, 'tab-1');
    expect(request.payeeUserId, 'payee-1');
  });
}
