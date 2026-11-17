import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/services/pin_protection_service.dart';
import 'package:tabby/core/widgets/biometric_gate.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';

class _Pin extends PinProtectionService {
  _Pin(this.enabled, {this.verification});
  final bool enabled;
  final Completer<bool>? verification;
  @override
  Future<bool> hasPin(String userId) async => enabled;
  @override
  Future<bool> verifyPin(String userId, String pin) =>
      verification?.future ?? Future<bool>.value(pin == '1234');
}

class _ControlledStorage extends FlutterSecureStorage {
  _ControlledStorage({this.fail = false});
  final bool fail;
  final first = Completer<String?>();
  bool readOnce = false;
  @override
  Future<String?> read(
      {required String key,
      IOSOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      MacOsOptions? mOptions,
      WindowsOptions? wOptions}) async {
    if (fail) throw StateError('Unavailable secure storage');
    if (!readOnce) {
      readOnce = true;
      return first.future;
    }
    return null;
  }
}

Widget _app(UserSettingsNotifier settings) => ProviderScope(
    overrides: [userSettingsProvider.overrideWith((ref) => settings)],
    child: MaterialApp(
        home: const SizedBox(),
        builder: (_, __) =>
            const BiometricGate(child: Text('Private ledger'))));

void main() {
  testWidgets(
      'cold launch hides sensitive descendants until settings are loaded',
      (tester) async {
    final storage = _ControlledStorage();
    final settings = UserSettingsNotifier(
        userId: 'A', pinProtection: _Pin(false), storage: storage);
    await tester.pumpWidget(_app(settings));
    expect(find.text('Private ledger'), findsNothing);
    storage.first.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Private ledger'), findsOneWidget);
  });
  testWidgets('security read failure fails closed with recoverable UI',
      (tester) async {
    final settings = UserSettingsNotifier(
        userId: 'A',
        pinProtection: _Pin(false),
        storage: _ControlledStorage(fail: true));
    await tester.pumpWidget(_app(settings));
    await tester.pumpAndSettle();
    expect(find.text('Private ledger'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
  });
  testWidgets(
      'cold and resumed PIN entry works above the router and cancellation keeps lock',
      (tester) async {
    final settings =
        UserSettingsNotifier(userId: 'A', pinProtection: _Pin(true));
    await tester.pumpWidget(_app(settings));
    await tester.pumpAndSettle();
    expect(find.text('Private ledger'), findsNothing);
    await tester.tap(find.text('Cancel'));
    expect(find.text('Private ledger'), findsNothing);
    await tester.enterText(find.byType(TextField), '0000');
    await tester.tap(find.text('Unlock with PIN'));
    await tester.pumpAndSettle();
    expect(find.text('Private ledger'), findsNothing);
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('Unlock with PIN'));
    await tester.pumpAndSettle();
    expect(find.text('Private ledger'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Private ledger'), findsNothing);
    expect(find.text('Unlock with PIN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('valid PIN shows verification progress until gate unlocks', (
    tester,
  ) async {
    final verification = Completer<bool>();
    final settings = UserSettingsNotifier(
      userId: 'A',
      pinProtection: _Pin(true, verification: verification),
    );
    await tester.pumpWidget(_app(settings));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('Unlock with PIN'));
    await tester.pump();

    expect(find.text('Verifying PIN'), findsOneWidget);
    expect(find.text('Private ledger'), findsNothing);

    verification.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Verifying PIN'), findsNothing);
    expect(find.text('Private ledger'), findsOneWidget);
  });
}
