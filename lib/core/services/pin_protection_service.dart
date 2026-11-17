import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as legacy;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PinLockedException implements Exception {
  const PinLockedException(this.retryAfter);
  final Duration retryAfter;
}

/// All derivation runs away from the native UI isolate. Web uses WebCrypto
/// where supported by package:cryptography.
Future<String> derivePinVerifier(Map<String, dynamic> input) async {
  final key = await Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: input['iterations'] as int,
    bits: 256,
  ).deriveKeyFromPassword(
    password: input['pin'] as String,
    nonce: base64Url.decode(input['salt'] as String),
  );
  return base64UrlEncode(await key.extractBytes());
}

class PinProtectionService {
  PinProtectionService({
    FlutterSecureStorage? storage,
    DateTime Function()? now,
    Future<String> Function(Map<String, dynamic>)? derive,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _now = now ?? DateTime.now,
        _derive = derive ?? _deriveOffThread;

  static const iterations = 600000;
  final FlutterSecureStorage _storage;
  final DateTime Function() _now;
  final Future<String> Function(Map<String, dynamic>) _derive;
  static final _tails = <String, Future<void>>{};

  static Future<String> _deriveOffThread(Map<String, dynamic> input) =>
      compute(derivePinVerifier, input);

  String _key(String userId, String suffix) {
    final normalized = userId.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return 'tabby_security_${normalized}_$suffix';
  }

  // Serialize across service instances; concurrent taps cannot bypass counters.
  Future<T> _serial<T>(String userId, Future<T> Function() action) {
    final key = _key(userId, 'pin_record');
    final previous = _tails[key] ?? Future<void>.value();
    final result = previous.then((_) => action());
    final tail =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _tails[key] = tail;
    tail.then((_) {
      if (identical(_tails[key], tail)) _tails.remove(key);
    });
    return result;
  }

  Future<Map<String, dynamic>?> _read(String userId) async {
    final raw = await _storage.read(key: _key(userId, 'pin_record'));
    if (raw != null) {
      final r = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final version = r['version'];
      if ((version != 1 && version != 2) ||
          r['salt'] is! String ||
          r['verifier'] is! String ||
          r['failures'] is! int ||
          (r['failures'] as int) < 0 ||
          r['blocked_until'] is! int ||
          (version == 2 &&
              (r['algorithm'] != 'pbkdf2-hmac-sha256' ||
                  r['iterations'] != iterations ||
                  base64Url.decode(r['salt'] as String).length != 16 ||
                  base64Url.decode(r['verifier'] as String).length != 32))) {
        throw const FormatException('Invalid PIN security record.');
      }
      return r;
    }
    final verifier = await _storage.read(key: _key(userId, 'pin_verifier'));
    final salt = await _storage.read(key: _key(userId, 'pin_salt'));
    if (verifier == null && salt == null) return null;
    if (verifier == null || salt == null) {
      throw const FormatException('Incomplete PIN record.');
    }
    return {
      'version': 1,
      'salt': salt,
      'verifier': verifier,
      'failures': 0,
      'blocked_until': 0
    };
  }

  Future<void> _write(String userId, Map<String, dynamic> record) => _storage
      .write(key: _key(userId, 'pin_record'), value: jsonEncode(record));

  Future<bool> hasPin(String userId) =>
      _serial(userId, () async => await _read(userId) != null);

  Future<void> _set(String userId, String pin) async {
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      throw const FormatException('PIN must contain 4 to 6 digits.');
    }
    final salt = generateSalt();
    final verifier =
        await _derive({'pin': pin, 'salt': salt, 'iterations': iterations});
    await _write(userId, {
      'version': 2,
      'algorithm': 'pbkdf2-hmac-sha256',
      'iterations': iterations,
      'salt': salt,
      'verifier': verifier,
      'failures': 0,
      'blocked_until': 0
    });
    // The replacement is durable before removing the old format.
    await _storage.delete(key: _key(userId, 'pin_salt'));
    await _storage.delete(key: _key(userId, 'pin_verifier'));
  }

  Future<void> setPin(String userId, String pin) =>
      _serial(userId, () => _set(userId, pin));

  Future<bool> verifyPin(String userId, String pin) =>
      _serial(userId, () async {
        final record = await _read(userId);
        if (record == null) return false;
        final now = _now().millisecondsSinceEpoch;
        final blockedUntil = record['blocked_until'] as int;
        if (blockedUntil > now) {
          throw PinLockedException(Duration(milliseconds: blockedUntil - now));
        }
        final failures = (record['failures'] as int) + 1;
        // Reserve the attempt before hashing. Restart/failure cannot erase it.
        record['failures'] = failures;
        record['blocked_until'] = failures >= 5
            ? now + min(900, 30 * (1 << min(5, failures - 5))) * 1000
            : 0;
        await _write(userId, record);
        final actual = record['version'] == 1
            ? createVerifier(pin, record['salt'] as String)
            : await _derive(
                {'pin': pin, 'salt': record['salt'], 'iterations': iterations});
        final valid = _equal(actual, record['verifier'] as String);
        if (valid) {
          if (record['version'] == 1) {
            await _set(
                userId, pin); // Upgrade only after a successful legacy match.
          } else {
            record['failures'] = 0;
            record['blocked_until'] = 0;
            await _write(userId, record);
          }
        }
        return valid;
      });

  Future<void> clearPin(String userId) => _serial(userId, () async {
        await _storage.delete(key: _key(userId, 'pin_salt'));
        await _storage.delete(key: _key(userId, 'pin_verifier'));
        await _storage.delete(key: _key(userId, 'pin_record'));
      });

  static String generateSalt() => base64UrlEncode(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)));

  /// Legacy verification only. New records always use PBKDF2.
  static String createVerifier(String pin, String salt) =>
      legacy.sha256.convert(utf8.encode('$salt:$pin')).toString();
  static bool verify(String pin, String salt, String expectedVerifier) =>
      _equal(createVerifier(pin, salt), expectedVerifier);
  static bool _equal(String actual, String expected) {
    if (actual.length != expected.length) return false;
    var difference = 0;
    for (var i = 0; i < actual.length; i++) {
      difference |= actual.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return difference == 0;
  }
}
