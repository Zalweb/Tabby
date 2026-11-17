import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/services/pin_protection_service.dart';

Future<String> _testDerive(Map<String, dynamic> input) async => base64UrlEncode(
    sha256.convert(utf8.encode('${input['salt']}:${input['pin']}')).bytes);

void main() {
  const storage = FlutterSecureStorage();
  var now = DateTime.utc(2026, 10, 31);
  PinProtectionService service() => PinProtectionService(
      storage: storage, now: () => now, derive: _testDerive);
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    now = DateTime.utc(2026, 10, 31);
  });

  test('production PBKDF2 verifies a PIN and never stores plaintext', () async {
    final real = PinProtectionService(storage: storage);
    await real.setPin('actual-kdf', '931846');
    final record = jsonDecode(
            (await storage.read(key: 'tabby_security_actual-kdf_pin_record'))!)
        as Map;
    expect(record['algorithm'], 'pbkdf2-hmac-sha256');
    expect(record['iterations'], 600000);
    expect(record['version'], 2);
    expect(record.values, isNot(contains('931846')));
    expect(await real.verifyPin('actual-kdf', '931846'), isTrue);
    expect(await real.verifyPin('actual-kdf', '931845'), isFalse);
  });

  test('PBKDF2 agrees with the published SHA256 test vector', () async {
    final result = await derivePinVerifier({
      'pin': 'password',
      'salt': base64UrlEncode(utf8.encode('salt')),
      'iterations': 1
    });
    expect(
        base64Url
            .decode(result)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b');
  });

  test('five failed attempts persist delay across new service instances',
      () async {
    await service().setPin('alice', '1234');
    for (var i = 0; i < 5; i++) {
      expect(await service().verifyPin('alice', '0000'), isFalse);
    }
    await expectLater(service().verifyPin('alice', '1234'),
        throwsA(isA<PinLockedException>()));
    // Another user has an independent attempt budget.
    await service().setPin('bob', '9876');
    expect(await service().verifyPin('bob', '9876'), isTrue);
    now = now.add(const Duration(seconds: 31));
    expect(await service().verifyPin('alice', '1234'), isTrue);
    final record = jsonDecode(
        (await storage.read(key: 'tabby_security_alice_pin_record'))!);
    expect(record['failures'], 0);
    expect(record['blocked_until'], 0);
  });

  test('concurrent instances cannot skip attempt accounting', () async {
    await service().setPin('alice', '1234');
    final results = await Future.wait(List.generate(8, (_) async {
      try {
        await service().verifyPin('alice', '0000');
        return 'failed';
      } on PinLockedException {
        return 'locked';
      }
    }));
    expect(results.where((r) => r == 'failed').length, 5);
    expect(results.where((r) => r == 'locked').length, 3);
  });

  test(
      'legacy failure is throttled without upgrading; success upgrades atomically',
      () async {
    final salt = PinProtectionService.generateSalt();
    await storage.write(key: 'tabby_security_legacy_pin_salt', value: salt);
    await storage.write(
        key: 'tabby_security_legacy_pin_verifier',
        value: PinProtectionService.createVerifier('1234', salt));
    expect(await service().verifyPin('legacy', '0000'), isFalse);
    var record = jsonDecode(
        (await storage.read(key: 'tabby_security_legacy_pin_record'))!);
    expect(record['version'], 1);
    expect(record['failures'], 1);
    expect(await storage.read(key: 'tabby_security_legacy_pin_verifier'),
        isNotNull);
    expect(await service().verifyPin('legacy', '1234'), isTrue);
    record = jsonDecode(
        (await storage.read(key: 'tabby_security_legacy_pin_record'))!);
    expect(record['version'], 2);
    expect(record['failures'], 0);
    expect(
        await storage.read(key: 'tabby_security_legacy_pin_verifier'), isNull);
    expect(await storage.read(key: 'tabby_security_legacy_pin_salt'), isNull);
  });

  test('corrupt records fail closed and cannot look like disabled protection',
      () async {
    await storage.write(
        key: 'tabby_security_alice_pin_record', value: '{broken');
    await expectLater(service().hasPin('alice'), throwsFormatException);
    await expectLater(
        service().verifyPin('alice', '1234'), throwsFormatException);
  });
}
