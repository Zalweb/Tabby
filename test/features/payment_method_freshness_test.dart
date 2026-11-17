import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/config/session_scope.dart';
import 'package:tabby/features/payment_methods/application/payment_methods_provider.dart';
import 'package:tabby/features/payment_methods/domain/payment_method.dart';
import 'package:tabby/features/payment_methods/presentation/payment_methods_sheet.dart';
import 'package:tabby/features/payment_methods/presentation/receiving_qr_image.dart';
import 'package:tabby/features/tabs/data/supabase_tabby_repository.dart';

const method = PaymentMethod(
    id: 'method',
    ownerUserId: 'owner',
    provider: 'other',
    displayName: 'Synthetic receiving method',
    accountLabel: 'Manual details',
    qrStoragePath: 'owner/qr.png');

class _Methods extends Fake implements SupabaseTabbyRepository {
  List<PaymentMethod> rows = [method];
  bool fail = false;
  int calls = 0;
  final requests = <Completer<List<PaymentMethod>>>[];
  bool deferred = false;
  @override
  Future<List<PaymentMethod>> fetchPaymentMethods(String ownerUserId) async {
    calls++;
    if (fail) throw StateError('synthetic read failure');
    if (deferred) {
      final c = Completer<List<PaymentMethod>>();
      requests.add(c);
      return c.future;
    }
    return List.of(rows);
  }
}

void main() {
  test('newer method load wins when earlier request completes last', () async {
    final repo = _Methods()..deferred = true;
    final n = PaymentMethodsNotifier(ownerUserId: 'owner', repository: repo);
    addTearDown(n.dispose);
    final latest = n.load();
    repo.requests[1]
        .complete([method.copyWith(revision: 2, displayName: 'New method')]);
    expect(await latest, isTrue);
    repo.requests[0].complete([method]);
    await Future<void>.delayed(Duration.zero);
    expect(n.state.methods.single.revision, 2);
  });
  test(
      'failed refresh hides stale QR and is distinct from an empty server list',
      () async {
    final repo = _Methods();
    final n = PaymentMethodsNotifier(ownerUserId: 'owner', repository: repo);
    addTearDown(n.dispose);
    await Future<void>.delayed(Duration.zero);
    expect(n.state.methods, isNotEmpty);
    repo.fail = true;
    expect(await n.load(), isFalse);
    expect(n.state.methods, isEmpty);
    expect(n.state.errorMessage, contains('Could not refresh'));
    repo.fail = false;
    repo.rows = [];
    expect(await n.load(), isTrue);
    expect(n.state.errorMessage, isNull);
  });
  testWidgets('missing signed URL refreshes once then requires explicit retry',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ReceivingQrImage(
                method: method,
                reload: () async {
                  calls++;
                  return method;
                }))));
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 10));
    expect(calls, 1);
    await tester.tap(find.text('Retry QR'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed network image gets only one automatic fresh URL',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ReceivingQrImage(
                method: method.copyWith(
                    qrUrl: 'https://example.invalid/expired-qr'),
                reload: () async {
                  calls++;
                  return method.copyWith(
                      qrUrl: 'https://example.invalid/new-qr');
                }))));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Retry QR'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('removed method cannot retain the previous image',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ReceivingQrImage(method: method, reload: () async => null))));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.text('Receiving QR unavailable.'), findsOneWidget);
  });
  testWidgets('late QR refresh discards prior session destination',
      (tester) async {
    final scope = SessionScope();
    final result = Completer<PaymentMethod?>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ReceivingQrImage(
                method: method,
                reload: () => result.future,
                captureSession: () => scope.capture('owner'),
                sessionIsCurrent: (stamp) =>
                    scope.isCurrent(stamp, 'owner')))));
    await tester.pump();
    scope.advance('owner');
    result.complete(
        method.copyWith(qrUrl: 'https://example.invalid/private-old-account'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.text('Receiving QR unavailable. Reopen receiving methods.'), findsOneWidget);
    expect(find.text('Retry QR'), findsNothing);
  });
  testWidgets('reopening owner sheet and resuming reload current methods',
      (tester) async {
    final repo = _Methods();
    final n = PaymentMethodsNotifier(ownerUserId: 'owner', repository: repo);
    await tester.pumpWidget(ProviderScope(
        overrides: [paymentMethodsProvider('owner').overrideWith((ref) => n)],
        child: const MaterialApp(
            home: Scaffold(body: PaymentMethodsSheet(ownerUserId: 'owner')))));
    await tester.pumpAndSettle();
    final prior = repo.calls;
    repo.rows = [
      method.copyWith(displayName: 'Changed on another session', revision: 2)
    ];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(repo.calls, greaterThan(prior));
    expect(find.text('Changed on another session'), findsOneWidget);
    repo.rows = [];
    await tester.tap(find.byTooltip('Refresh payment methods'));
    await tester.pumpAndSettle();
    expect(find.text('No payment methods yet'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
