import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/config/session_scope.dart';
import 'package:tabby/core/services/receiving_qr_export.dart';
import 'package:tabby/core/utils/qr_code_renderer.dart';
import 'package:tabby/features/connections/presentation/connections_screen.dart';
import 'package:tabby/features/payment_methods/application/payment_methods_provider.dart';
import 'package:tabby/features/payment_methods/domain/payment_method.dart';
import 'package:tabby/features/payment_methods/presentation/friend_receiving_methods_sheet.dart';
import 'package:tabby/features/payment_methods/presentation/receiving_qr_image.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/data/supabase_tabby_repository.dart';
import 'package:tabby/features/tabs/domain/models.dart' show TabbyUser;

const method = PaymentMethod(
  id: 'method',
  ownerUserId: 'friend',
  provider: 'other',
  displayName: 'Synthetic receiving method',
  accountLabel: 'Manual account details',
);

class _Methods extends Fake implements SupabaseTabbyRepository {
  List<PaymentMethod> rows = [method];
  @override
  Future<List<PaymentMethod>> fetchPaymentMethods(String ownerUserId) async =>
      List.of(rows);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List png;
  final calls = <MethodCall>[];
  setUpAll(() async {
    png = (await renderQrPng('https://example.com/synthetic-receiving-qr'))!;
  });
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('tabby/receiving_qr'), (
          call,
        ) async {
          calls.add(call);
          return true;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('tabby/receiving_qr'),
          null,
        );
  });
  test('save/share pass validated PNG bytes to native action without payment commands', () async {
    for (final share in [false, true]) {
      expect(
        await ReceivingQrExport.export(share: share, download: () async => png),
        isTrue,
      );
    }
    expect(calls.map((c) => c.method), ['save', 'share']);
    for (final call in calls) {
      final bytes = (call.arguments as Map)['bytes'] as Uint8List;
      expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect((call.arguments as Map).keys, ['bytes']);
    }
  });
  test(
    'cancelled save is false and native failure is not reported as success',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('tabby/receiving_qr'),
            (_) async => false,
          );
      expect(
        await ReceivingQrExport.export(share: false, download: () async => png),
        isFalse,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('tabby/receiving_qr'),
            (_) async => throw PlatformException(code: 'save_failed'),
          );
      await expectLater(
        ReceivingQrExport.export(share: false, download: () async => png),
        throwsA(isA<PlatformException>()),
      );
    },
  );
  test(
    'invalid image and failed authorization never reach native sharing',
    () async {
      await expectLater(
        ReceivingQrExport.export(
          share: true,
          download: () async => Uint8List.fromList([1, 2]),
        ),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        ReceivingQrExport.export(
          share: true,
          download: () async => throw StateError('denied'),
        ),
        throwsStateError,
      );
      expect(calls, isEmpty);
    },
  );
  test(
    'account change while downloading discards prior account image',
    () async {
      final scope = SessionScope(), result = Completer<Uint8List>();
      final exported = ReceivingQrExport.export(
        share: true,
        download: () => result.future,
        captureSession: () => scope.capture('owner'),
        sessionIsCurrent: (stamp) => scope.isCurrent(stamp, 'owner'),
      );
      scope.advance('owner');
      result.complete(png);
      await expectLater(exported, throwsStateError);
      expect(calls, isEmpty);
    },
  );
  test(
    'iOS save and share use validated PNG bytes and current-account scope',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(ReceivingQrExport.supported, isTrue);
      final scope = SessionScope();
      for (final share in [false, true]) {
        expect(
          await ReceivingQrExport.export(
            share: share,
            download: () async => png,
            captureSession: () => scope.capture('owner'),
            sessionIsCurrent: (stamp) => scope.isCurrent(stamp, 'owner'),
          ),
          isTrue,
        );
      }
      expect(calls.map((c) => c.method), ['save', 'share']);
      expect((calls.first.arguments as Map)['bytes'], isA<Uint8List>());
    },
  );
  test(
    'unsupported desktop platforms do not invoke the mobile export channel',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await expectLater(
        ReceivingQrExport.export(share: true, download: () async => png),
        throwsUnsupportedError,
      );
      expect(calls, isEmpty);
    },
  );
  testWidgets(
    'fullscreen QR is zoomable and keeps payment confirmation separate',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReceivingQrImage(
              method: method.copyWith(qrUrl: 'https://example.invalid/qr'),
              reload: () async =>
                  method.copyWith(qrUrl: 'https://example.invalid/qr'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fullscreen QR'));
      await tester.pumpAndSettle();
      expect(find.text('Receiving QR'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsWidgets);
      expect(find.text('Save QR image'), findsWidgets);
      expect(find.text('Share QR image'), findsWidgets);
      expect(find.text('Confirm Payment'), findsNothing);
      expect(
        find.text('Pay in your wallet, then submit payment separately.'),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'friend profile entry opens read-only methods and handles revoked access',
    (tester) async {
      const friend = TabbyUser(
        id: 'friend',
        displayName: 'Friend',
        email: '',
        phone: '',
      );
      final repo = _Methods();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            friendsProvider.overrideWith((ref) => [friend]),
            paymentMethodsProvider('friend').overrideWith(
              (ref) => PaymentMethodsNotifier(
                ownerUserId: 'friend',
                repository: repo,
              ),
            ),
          ],
          child: const MaterialApp(home: ConnectionsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Friend options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View receiving methods'));
      await tester.pumpAndSettle();
      expect(find.byType(FriendReceivingMethodsSheet), findsOneWidget);
      expect(find.textContaining("Friend's receiving methods"), findsOneWidget);
      expect(find.textContaining('Manual account details'), findsWidgets);
      expect(find.text('Edit or replace QR'), findsNothing);
      expect(find.text('Save Payment Method'), findsNothing);
      repo.rows = [];
      await tester.tap(find.byTooltip('Refresh receiving methods'));
      await tester.pumpAndSettle();
      expect(
        find.text('No active receiving methods are available to you.'),
        findsOneWidget,
      );
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  test('Android sharing provider exposes only receiving export cache', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final paths = File('android/app/src/main/res/xml/receiving_qr_paths.xml')
        .readAsStringSync();
    expect(
      RegExp(
        r'<provider[^>]*android:name=".ReceivingQrFileProvider"[^>]*android:exported="false"[^>]*android:grantUriPermissions="true"',
        dotAll: true,
      ).hasMatch(manifest),
      isTrue,
    );
    expect(paths, contains('path="receiving-qr/"'));
    expect(paths, isNot(contains('<root-path')));
    expect(paths, isNot(contains('<external-path')));
    expect(manifest, isNot(contains('WRITE_EXTERNAL_STORAGE')));
  });
}
