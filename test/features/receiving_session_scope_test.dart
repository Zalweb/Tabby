import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/config/supabase_config.dart';
import 'package:tabby/features/payment_methods/application/payment_methods_provider.dart';
import 'package:tabby/features/payment_methods/domain/payment_method.dart';
import 'package:tabby/features/payment_methods/presentation/friend_receiving_methods_sheet.dart';
import 'package:tabby/features/payment_methods/presentation/payment_method_payment_sheet.dart';
import 'package:tabby/features/payment_methods/presentation/payment_methods_sheet.dart';
import 'package:tabby/features/payment_methods/presentation/receiving_qr_image.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/data/supabase_tabby_repository.dart';
import 'package:tabby/features/tabs/domain/models.dart'
    show TabbyUser, BilateralTab;

const _owner = TabbyUser(
  id: 'account-a',
  displayName: 'Owner A',
  email: '',
  phone: '',
);
const _friend = TabbyUser(
  id: 'friend',
  displayName: 'Synthetic friend',
  email: '',
  phone: '',
);
const _method = PaymentMethod(
  id: 'private-method',
  ownerUserId: 'friend',
  provider: 'other',
  displayName: 'Private A receiving method',
  accountLabel: 'Synthetic private receiving details',
);
var _mutatingCalls = 0;

class _Methods extends Fake implements SupabaseTabbyRepository {
  @override
  Future<List<PaymentMethod>> fetchPaymentMethods(String ownerUserId) async => [
    _method,
  ];
  @override
  Future<bool> deletePaymentMethod(String methodId) async {
    _mutatingCalls++;
    return false;
  }

  @override
  Future<bool> setPreferredPaymentMethod(String methodId) async {
    _mutatingCalls++;
    return false;
  }
}

void _invalidate(bool same) {
  SupabaseConfig.debugUserIdOverride = 'account-b';
  SupabaseConfig.captureSession();
  if (same) {
    SupabaseConfig.debugUserIdOverride = _owner.id;
    SupabaseConfig.captureSession();
  }
  SupabaseConfig.sessionRevision.value++;
}

Widget _host(Widget child) => ProviderScope(
  overrides: [
    currentUserProvider.overrideWith(
      (_) => CurrentUserNotifier(initialUser: _owner, autoLoad: false),
    ),
    paymentMethodsProvider('friend').overrideWith(
      (_) =>
          PaymentMethodsNotifier(ownerUserId: 'friend', repository: _Methods()),
    ),
    paymentMethodsProvider(_owner.id).overrideWith(
      (_) => PaymentMethodsNotifier(
        ownerUserId: _owner.id,
        repository: _Methods(),
      ),
    ),
    tabPaymentMethodsProvider.overrideWith((_, _) async => [_method]),
  ],
  child: MaterialApp(home: Scaffold(body: child)),
);

void main({
  bool includeProviderUnitTests = true,
  String qrUrl = 'https://example.invalid/synthetic-qr',
  String Function()? qrUrlBuilder,
}) {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    _mutatingCalls = 0;
    SupabaseConfig.debugUserIdOverride = _owner.id;
    SupabaseConfig.captureSession();
  });
  tearDown(() => SupabaseConfig.debugUserIdOverride = null);
  for (final action in ['preferred', 'delete', 'edit', 'preview']) {
    testWidgets('cached owner $action callback cannot act in another account', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => FilledButton(
              onPressed: () =>
                  PaymentMethodsSheet.show(context, ownerUserId: _owner.id),
              child: const Text('Open owner methods'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open owner methods'));
      await tester.pumpAndSettle();
      final menu = tester.widget<PopupMenuButton<String>>(
        find.byType(PopupMenuButton<String>),
      );
      final tile = tester.widget<ListTile>(find.byType(ListTile));
      _invalidate(false);
      if (action == 'preview') {
        tile.onTap!();
      } else {
        menu.onSelected!(action);
      }
      await tester.pumpAndSettle();
      expect(_mutatingCalls, 0);
      expect(find.byType(ReceivingMethodEditor), findsNothing);
      expect(find.text('Receiving QR'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  for (final same in [false, true]) {
    for (final preview in [false, true]) {
      testWidgets(
        'owner methods ${preview ? 'preview' : 'list'} close after ${same ? 'relogin' : 'account switch'}',
        (tester) async {
          await tester.pumpWidget(
            _host(
              Builder(
                builder: (context) => FilledButton(
                  onPressed: () =>
                      PaymentMethodsSheet.show(context, ownerUserId: _owner.id),
                  child: const Text('Open owner methods'),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open owner methods'));
          await tester.pumpAndSettle();
          expect(find.text(_method.displayName), findsOneWidget);
          if (preview) {
            await tester.tap(find.text(_method.displayName));
            await tester.pumpAndSettle();
            expect(find.text('Receiving QR'), findsOneWidget);
          }
          _invalidate(same);
          await tester.pumpAndSettle();
          expect(
            find.byType(PaymentMethodsSheet, skipOffstage: false),
            findsNothing,
          );
          expect(find.text('Receiving QR', skipOffstage: false), findsNothing);
          expect(
            find.text(_method.accountLabel, skipOffstage: false),
            findsNothing,
          );
          expect(find.text('Open owner methods'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
    if (includeProviderUnitTests) {
      test(
        'cached provider resets after ${same ? 'same-account relogin' : 'account switch'} even before profile changes',
        () async {
          const legacy = TabbyUser(
            id: 'account-a',
            displayName: 'Synthetic',
            email: '',
            phone: '',
            gcashNumber: 'Synthetic receiving fixture',
          );
          final container = ProviderContainer(
            overrides: [
              currentUserProvider.overrideWith(
                (_) =>
                    CurrentUserNotifier(initialUser: legacy, autoLoad: false),
              ),
            ],
          );
          addTearDown(container.dispose);
          final provider = paymentMethodsProvider(legacy.id);
          container.read(provider);
          await Future<void>.delayed(Duration.zero);
          expect(container.read(provider).methods, isNotEmpty);
          _invalidate(same);
          expect(container.read(provider).methods, isEmpty);
          expect(container.read(provider).isLoading, isTrue);
        },
      );
    }
  }
  for (final fail in [false, true]) {
    testWidgets(
      'pending clipboard ${fail ? 'error' : 'success'} cannot acknowledge a later account',
      (tester) async {
        final reply = Completer<Object?>();
        var writes = 0;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              writes++;
              return reply.future;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.pumpWidget(
          _host(
            ReceivingMethodCard(method: _method, reload: () async => _method),
          ),
        );
        await tester.tap(find.byIcon(Icons.copy_rounded));
        await tester.pump();
        expect(writes, 1);
        _invalidate(false);
        if (fail) {
          reply.completeError(
            PlatformException(code: 'synthetic_late_failure'),
          );
        } else {
          reply.complete(null);
        }
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);
        expect(find.text(_method.accountLabel), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final fail in [false, true]) {
    testWidgets(
      'copy ${fail ? 'failure is actionable' : 'success acknowledges clipboard'}',
      (tester) async {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData' && fail) {
              throw PlatformException(code: 'synthetic_clipboard_failure');
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.pumpWidget(
          _host(
            ReceivingMethodCard(method: _method, reload: () async => _method),
          ),
        );
        await tester.tap(find.byIcon(Icons.copy_rounded));
        await tester.pumpAndSettle();
        expect(
          find.text('Payment details copied.'),
          fail ? findsNothing : findsOneWidget,
        );
        if (fail) {
          expect(
            find.text('Could not copy payment details. Please try again.'),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final same in [false, true]) {
    for (final payment in [false, true]) {
      testWidgets(
        '${payment ? 'payment' : 'friend'} methods close after ${same ? 'relogin' : 'account switch'}',
        (tester) async {
          final tab = BilateralTab(
            id: 'tab',
            counterpart: _friend,
            netBalanceCentavos: -100,
            itemCount: 0,
            entries: const [],
            lastUpdated: DateTime(2026),
          );
          await tester.pumpWidget(
            _host(
              Builder(
                builder: (context) => FilledButton(
                  onPressed: () => payment
                      ? PaymentMethodPaymentSheet.show(context, tab)
                      : FriendReceivingMethodsSheet.show(
                          context,
                          userId: 'friend',
                          displayName: 'Synthetic friend',
                        ),
                  child: const Text('Open methods'),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open methods'));
          await tester.pumpAndSettle();
          expect(find.text(_method.displayName), findsOneWidget);
          _invalidate(same);
          await tester.pumpAndSettle();
          expect(find.text(_method.displayName), findsNothing);
          expect(
            find.byType(
              payment ? PaymentMethodPaymentSheet : FriendReceivingMethodsSheet,
            ),
            findsNothing,
          );
          expect(find.text('Open methods'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
    for (final stacked in [false, true]) {
      testWidgets(
        'QR fullscreen clears after ${same ? 'relogin' : 'account switch'} with stacked=$stacked',
        (tester) async {
          final qr = _method.copyWith(qrUrl: qrUrlBuilder?.call() ?? qrUrl);
          await tester.pumpWidget(
            _host(ReceivingQrImage(method: qr, reload: () async => qr)),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Fullscreen QR'));
          await tester.pumpAndSettle();
          expect(find.text('Receiving QR'), findsOneWidget);
          if (stacked) {
            final context = tester.element(find.text('Receiving QR'));
            showDialog<void>(
              context: context,
              builder: (_) =>
                  const AlertDialog(content: Text('Newer unrelated dialog')),
            );
            await tester.pumpAndSettle();
          }
          _invalidate(same);
          await tester.pumpAndSettle();
          expect(find.text('Receiving QR', skipOffstage: false), findsNothing);
          expect(
            find.text(_method.displayName, skipOffstage: false),
            findsNothing,
          );
          if (stacked) {
            expect(find.text('Newer unrelated dialog'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets(
      'cached copy callback refuses ${same ? 'relogin' : 'other account'} details',
      (tester) async {
        final writes = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') writes.add(call);
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.pumpWidget(
          _host(
            ReceivingMethodCard(method: _method, reload: () async => _method),
          ),
        );
        final button = tester.widget<IconButton>(
          find.byWidgetPredicate(
            (widget) =>
                widget is IconButton &&
                widget.icon is Icon &&
                (widget.icon as Icon).icon == Icons.copy_rounded,
          ),
        );
        _invalidate(same);
        button.onPressed!();
        await tester.pumpAndSettle();
        expect(writes, isEmpty);
        expect(find.text('Payment details copied.'), findsNothing);
        expect(find.text(_method.accountLabel), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
