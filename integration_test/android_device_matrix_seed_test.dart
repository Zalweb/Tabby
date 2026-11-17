import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tabby/core/services/pin_protection_service.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('persist a synthetic PIN for force-stop cold-launch check', (
    tester,
  ) async {
    const account = 'device-matrix-sec001';
    final pin = PinProtectionService();
    await pin.clearPin(account);
    final settings = UserSettingsNotifier(userId: account, pinProtection: pin);
    await settings.ready;
    expect(await settings.setPin('1234'), isTrue);
    await settings.update(autoLockEnabled: true);
    expect(await pin.hasPin(account), isTrue);
    debugPrint('DEVICE_MATRIX_SEC001 seedPersisted=true account=$account');
    settings.dispose();
  });
}
