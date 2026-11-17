import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:tabby/core/services/device_auth_service.dart';
import 'package:tabby/core/services/storage_recovery_service.dart';
import 'package:tabby/core/widgets/startup_gate.dart';

class RecoveryAuth implements DeviceAuthService {
  bool allowed = false;
  int calls = 0;
  @override
  Future<bool> isSupported() async => true;
  @override
  Future<List<BiometricType>> availableBiometrics() async => [];
  @override
  Future<bool> authenticate({
    required String reason,
    bool allowDeviceCredential = true,
  }) async {
    expect(allowDeviceCredential, isTrue);
    calls++;
    return allowed;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/storage-recovery');
  late RecoveryAuth auth;
  late StorageRecoveryService recovery;
  late List<String> calls;
  setUp(() {
    auth = RecoveryAuth();
    recovery = StorageRecoveryService(auth: auth, channel: channel);
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return call.method == 'close' ? null : true;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('cancelled device authentication never resets storage', () async {
    expect(await recovery.preserveAndReset(), isFalse);
    expect(auth.calls, 1);
    expect(calls, isEmpty);
    auth.allowed = true;
    expect(await recovery.preserveAndReset(), isTrue);
    expect(auth.calls, 2);
    expect(calls, ['preserveAndReset']);
  });

  test(
    'native failure or absent acknowledgement never reports recovery',
    () async {
      auth.allowed = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => false);
      await expectLater(
        recovery.preserveAndReset(),
        throwsA(isA<LocalStorageUnavailable>()),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => throw PlatformException(code: 'copy_failed'),
          );
      await expectLater(
        recovery.preserveAndReset(),
        throwsA(isA<PlatformException>()),
      );
    },
  );

  testWidgets(
    'storage error stays blocked; confirmation and authentication precede reset',
    (tester) async {
      auth.allowed = true;
      await tester.pumpWidget(
        StartupGate(
          initialize: () async => throw const LocalStorageUnavailable(),
          recovery: recovery,
          child: const MaterialApp(home: Text('private dashboard')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('private dashboard'), findsNothing);
      expect(find.text('Continue'), findsNothing);
      await tester.tap(find.text('Recover local storage'));
      await tester.pumpAndSettle();
      expect(find.text('Recover local storage?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(auth.calls, 0);
      expect(calls, isEmpty);
      await tester.tap(find.text('Recover local storage'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preserve and reset'));
      await tester.pumpAndSettle();
      expect(calls, ['preserveAndReset']);
      expect(find.text('Try again'), findsNothing);
      expect(find.text('private dashboard'), findsNothing);
      await tester.tap(find.text('Close Tabby'));
      await tester.pumpAndSettle();
      expect(calls, ['preserveAndReset', 'close']);
    },
  );

  testWidgets('retry after restored key unlocks without any reset', (
    tester,
  ) async {
    var broken = true;
    await tester.pumpWidget(
      StartupGate(
        initialize: () async {
          if (broken) throw const LocalStorageUnavailable();
          return [];
        },
        recovery: recovery,
        child: const MaterialApp(home: Text('recovered dashboard')),
      ),
    );
    await tester.pumpAndSettle();
    broken = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('recovered dashboard'), findsOneWidget);
    expect(calls, isEmpty);
  });
}
