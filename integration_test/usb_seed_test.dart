import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tabby/core/services/form_draft_store.dart';
import 'package:tabby/core/services/pin_protection_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('seed encrypted state for a separate USB process', (
    tester,
  ) async {
    expect(const bool.fromEnvironment('TABBY_USB_TEST'), isTrue);
    final pin = PinProtectionService();
    await pin.clearPin('usb-smoke');
    await pin.setPin('usb-smoke', '7391');
    await const FormDraftStore().write('usb-smoke', 'payment:fixture', {
      'amount': '12.34',
      'operation': 'usb-smoke-stable-operation',
    });
  });
}
