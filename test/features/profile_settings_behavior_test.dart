import 'package:flutter_test/flutter_test.dart';

import 'package:tabby/core/services/pin_protection_service.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';

void main() {
  test('PIN verifier is deterministic for the same salt and rejects changes',
      () {
    const salt = 'fixed-salt';
    final verifier = PinProtectionService.createVerifier('1234', salt);

    expect(PinProtectionService.verify('1234', salt, verifier), isTrue);
    expect(PinProtectionService.verify('4321', salt, verifier), isFalse);
  });

  test('settings include the approved profile preferences', () {
    const settings = UserSettings();

    expect(settings.currencyCode, 'PHP');
    expect(settings.languageCode, 'en');
    expect(settings.motionEnabled, isTrue);
    expect(settings.darkModeEnabled, isFalse);
  });

  test('settings preserve appearance while keeping PHP and English fixed', () {
    final settings = const UserSettings().copyWith(
      currencyCode: 'USD',
      languageCode: 'fil',
      motionEnabled: false,
      darkModeEnabled: true,
    );

    expect(settings.currencyCode, 'PHP');
    expect(settings.languageCode, 'en');
    expect(settings.motionEnabled, isFalse);
    expect(settings.darkModeEnabled, isTrue);
  });
}
