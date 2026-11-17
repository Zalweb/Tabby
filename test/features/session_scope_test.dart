import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/config/session_scope.dart';
import 'package:tabby/features/payment_methods/application/payment_methods_provider.dart';
import 'package:tabby/features/payment_methods/domain/payment_method.dart';
import 'package:tabby/features/tabs/data/supabase_tabby_repository.dart';

class _DelayedMethods extends Fake implements SupabaseTabbyRepository {
  final result = Completer<List<PaymentMethod>>();
  @override
  Future<List<PaymentMethod>> fetchPaymentMethods(String ownerUserId) =>
      result.future;
}

void main() {
  for (final nextAccount in ['B', 'A']) {
    test(
        'late payment-method result is discarded after transition A to $nextAccount',
        () async {
      final scope = SessionScope();
      String? account = 'A';
      scope.advance(account);
      final repository = _DelayedMethods();
      final notifier = PaymentMethodsNotifier(
          ownerUserId: 'A',
          repository: repository,
          captureSession: () => scope.capture(account),
          sessionIsCurrent: (stamp) => scope.isCurrent(stamp, account));
      addTearDown(notifier.dispose);
      scope.advance(null);
      account = nextAccount;
      scope.advance(account);
      repository.result.complete(const [
        PaymentMethod(
            id: 'private-A',
            ownerUserId: 'A',
            provider: 'gcash',
            displayName: 'Private A QR',
            accountLabel: 'fixture',
            isDefault: true)
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.methods, isEmpty);
    });
  }
  test('active session result remains eligible', () {
    final scope = SessionScope();
    final stamp = scope.capture('A');
    expect(scope.isCurrent(stamp, 'A'), isTrue);
    expect(scope.isCurrent(stamp, 'B'), isFalse);
    scope.advance('A');
    expect(scope.isCurrent(stamp, 'A'), isFalse);
  });
}
