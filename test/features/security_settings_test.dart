import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

import 'package:tabby/core/services/device_auth_service.dart';
import 'package:tabby/core/services/pin_protection_service.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cancelled biometric challenge does not enable security', () async {
    final notifier = UserSettingsNotifier(
      userId: 'user-a',
      auth: FakeDeviceAuthService(supported: true, result: false),
      pinProtection: FakePinProtectionService(),
    );

    expect(await notifier.enableBiometric(), isFalse);
    expect(notifier.state.securityMethod, SecurityMethod.none);
    notifier.dispose();
  });

  test('PIN setup and verification are scoped through the service', () async {
    final pinProtection = FakePinProtectionService();
    final notifier = UserSettingsNotifier(
      userId: 'user-a',
      auth: FakeDeviceAuthService(supported: false, result: false),
      pinProtection: pinProtection,
    );

    expect(await notifier.setPin('1234'), isTrue);
    expect(notifier.state.securityMethod, SecurityMethod.pin);
    expect(await notifier.verifyPin('1234'), isTrue);
    expect(await notifier.verifyPin('4321'), isFalse);
    expect(pinProtection.lastUserId, 'user-a');
    notifier.dispose();
  });
}

class FakeDeviceAuthService implements DeviceAuthService {
  FakeDeviceAuthService({required this.supported, required this.result});

  final bool supported;
  final bool result;

  @override
  Future<List<BiometricType>> availableBiometrics() async =>
      const [BiometricType.fingerprint];

  @override
  Future<bool> authenticate({
    required String reason,
    bool allowDeviceCredential = true,
  }) async =>
      result;

  @override
  Future<bool> isSupported() async => supported;
}

class FakePinProtectionService extends PinProtectionService {
  FakePinProtectionService() : super();

  String? _pin;
  String? lastUserId;

  @override
  Future<bool> hasPin(String userId) async => _pin != null;

  @override
  Future<void> setPin(String userId, String pin) async {
    lastUserId = userId;
    _pin = pin;
  }

  @override
  Future<bool> verifyPin(String userId, String pin) async {
    lastUserId = userId;
    return userId == 'user-a' && _pin == pin;
  }

  @override
  Future<void> clearPin(String userId) async {
    lastUserId = userId;
    _pin = null;
  }
}
