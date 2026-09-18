import 'package:local_auth/local_auth.dart';

/// Injectable boundary around the platform device-authentication APIs.
abstract interface class DeviceAuthService {
  Future<bool> isSupported();

  Future<List<BiometricType>> availableBiometrics();

  Future<bool> authenticate({
    required String reason,
    bool allowDeviceCredential = true,
  });
}

class LocalDeviceAuthService implements DeviceAuthService {
  LocalDeviceAuthService({LocalAuthentication? authentication})
      : _authentication = authentication ?? LocalAuthentication();

  final LocalAuthentication _authentication;

  @override
  Future<bool> isSupported() async {
    try {
      return await _authentication.canCheckBiometrics ||
          await _authentication.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<BiometricType>> availableBiometrics() async {
    try {
      return await _authentication.getAvailableBiometrics();
    } catch (_) {
      return const <BiometricType>[];
    }
  }

  @override
  Future<bool> authenticate({
    required String reason,
    bool allowDeviceCredential = true,
  }) async {
    try {
      return await _authentication.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: !allowDeviceCredential,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
