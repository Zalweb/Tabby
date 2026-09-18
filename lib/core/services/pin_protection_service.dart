import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Creates verifiers for the optional app PIN without storing the PIN itself.
/// The salt and verifier are kept in the platform secure-storage layer by the
/// settings notifier.
class PinProtectionService {
  PinProtectionService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(String userId, String suffix) {
    final normalized = userId.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return 'tabby_security_${normalized}_$suffix';
  }

  Future<bool> hasPin(String userId) async {
    return (await _storage.read(key: _key(userId, 'pin_verifier'))) != null;
  }

  Future<void> setPin(String userId, String pin) async {
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      throw const FormatException('PIN must contain 4 to 6 digits.');
    }
    final salt = generateSalt();
    await _storage.write(key: _key(userId, 'pin_salt'), value: salt);
    await _storage.write(
      key: _key(userId, 'pin_verifier'),
      value: createVerifier(pin, salt),
    );
  }

  Future<bool> verifyPin(String userId, String pin) async {
    final salt = await _storage.read(key: _key(userId, 'pin_salt'));
    final verifier = await _storage.read(key: _key(userId, 'pin_verifier'));
    if (salt == null || verifier == null) return false;
    return verify(pin, salt, verifier);
  }

  Future<void> clearPin(String userId) async {
    await _storage.delete(key: _key(userId, 'pin_salt'));
    await _storage.delete(key: _key(userId, 'pin_verifier'));
  }

  static String generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  static String createVerifier(String pin, String salt) {
    return sha256.convert(utf8.encode('$salt:$pin')).toString();
  }

  static bool verify(String pin, String salt, String expectedVerifier) {
    final actual = createVerifier(pin, salt);
    if (actual.length != expectedVerifier.length) return false;

    var difference = 0;
    for (var index = 0; index < actual.length; index++) {
      difference |=
          actual.codeUnitAt(index) ^ expectedVerifier.codeUnitAt(index);
    }
    return difference == 0;
  }
}
