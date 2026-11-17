import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tabby/core/services/pin_protection_service.dart';
import 'package:tabby/core/widgets/biometric_gate.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SEC-001 persisted PIN recovers the cold lock gate', (
    tester,
  ) async {
    const account = 'device-matrix-sec001';
    final settings = UserSettingsNotifier(
      userId: account,
      pinProtection: PinProtectionService(),
    );
    await settings.ready;
    expect(settings.state.passcodeEnabled, isTrue);
    expect(settings.state.autoLockEnabled, isTrue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [userSettingsProvider.overrideWith((ref) => settings)],
        child: MaterialApp(
          home: const SizedBox.shrink(),
          builder: (context, child) => const BiometricGate(
            child: Text('Protected synthetic ledger'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 80));
    expect(find.text('Tabby is locked'), findsOneWidget);
    expect(find.text('Protected synthetic ledger'), findsNothing);

    final verified = await PinProtectionService().verifyPin(account, '1234');
    debugPrint('SEC001_REPRO persistedPinValid=$verified');
    expect(verified, isTrue);

    await tester.enterText(find.byType(TextField), '1234');
    await tester.ensureVisible(find.text('Unlock with PIN'));
    await tester.tap(find.text('Unlock with PIN'));
    await tester.pump();
    expect(find.text('Verifying PIN'), findsOneWidget);
    final unlockWatch = Stopwatch()..start();
    while (find.text('Protected synthetic ledger').evaluate().isEmpty &&
        unlockWatch.elapsed < const Duration(seconds: 20)) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    unlockWatch.stop();
    await tester.pumpAndSettle(const Duration(milliseconds: 80));

    final protectedVisible = find.text('Protected synthetic ledger').evaluate().isNotEmpty;
    debugPrint(
      'SEC001_REPRO persistedPinValid=$verified gateUnlockMs=${unlockWatch.elapsedMilliseconds} protectedVisible=$protectedVisible',
    );
    expect(protectedVisible, isTrue);
  });
}
