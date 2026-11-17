import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/config/session_scope.dart';
import 'package:tabby/features/payment_methods/application/payment_methods_provider.dart';
import 'package:tabby/features/payment_methods/domain/payment_method.dart';
import 'package:tabby/features/payment_methods/presentation/payment_methods_sheet.dart';
import 'package:tabby/features/tabs/data/supabase_tabby_repository.dart';

const first = PaymentMethod(
    id: 'first',
    ownerUserId: 'owner',
    provider: 'gcash',
    displayName: 'Original',
    accountLabel: 'Manual details',
    isDefault: true,
    qrStoragePath: 'owner/original.png');
const second = PaymentMethod(
    id: 'second',
    ownerUserId: 'owner',
    provider: 'maya',
    displayName: 'Second',
    accountLabel: 'Other details');
const draft = PaymentMethodDraft(
    provider: 'gcash', displayName: 'Updated', accountLabel: 'Details');

class _Methods extends Fake implements SupabaseTabbyRepository {
  List<PaymentMethod> rows = [first];
  PaymentMethod? saved;
  bool fail = false;
  Completer<List<PaymentMethod>>? nextLoad;
  Completer<PaymentMethod?>? delayedSave;
  int preferredCalls = 0;
  @override
  Future<List<PaymentMethod>> fetchPaymentMethods(String ownerUserId) async =>
      nextLoad?.future ?? List.of(rows);
  @override
  Future<PaymentMethod?> createPaymentMethod(
      {required String ownerUserId,
      required PaymentMethodDraft draft,
      required bool makeDefault}) async {
    if (fail || saved == null) return null;
    rows = [...rows, saved!];
    return saved;
  }

  @override
  Future<PaymentMethod?> updatePaymentMethod(
      {required PaymentMethod current,
      required PaymentMethodDraft draft}) async {
    if (delayedSave != null) return delayedSave!.future;
    if (fail) return null;
    final updated = current.copyWith(
        displayName: draft.displayName,
        qrStoragePath: 'owner/replacement.png',
        revision: current.revision + 1);
    rows = [updated];
    return updated;
  }

  @override
  Future<bool> deletePaymentMethod(String methodId) async {
    if (fail) return false;
    rows = rows
        .where((m) => m.id != methodId)
        .map((m) => m.copyWith(isDefault: true))
        .toList();
    return true;
  }

  @override
  Future<bool> setPreferredPaymentMethod(String methodId) async {
    preferredCalls++;
    return !fail;
  }
}

Future<PaymentMethodsNotifier> _notifier(_Methods repository) async {
  final n =
      PaymentMethodsNotifier(ownerUserId: 'owner', repository: repository);
  await Future<void>.delayed(Duration.zero);
  return n;
}

void main() {
  test('adding a nondefault method preserves the existing preference',
      () async {
    final repo = _Methods()..saved = second;
    final n = await _notifier(repo);
    addTearDown(n.dispose);
    expect(await n.saveDraft(draft, makeDefault: false), isTrue);
    expect(n.state.methods.map((m) => m.id), ['first', 'second']);
    expect(n.state.methods.where((m) => m.isDefault).single.id, 'first');
  });
  test('failed replacement preserves old QR, revision and preference',
      () async {
    final n = await _notifier(_Methods()..fail = true);
    addTearDown(n.dispose);
    expect(await n.updateDraft(first, draft), isFalse);
    expect(n.state.methods.single, first);
    expect(n.state.isSaving, isFalse);
    expect(n.state.errorMessage, contains('draft is kept'));
  });
  test('acknowledged replacement keeps method identity and changes revision',
      () async {
    final n = await _notifier(_Methods());
    addTearDown(n.dispose);
    expect(await n.updateDraft(first, draft), isTrue);
    expect(n.state.methods.single.id, first.id);
    expect(n.state.methods.single.qrStoragePath, 'owner/replacement.png');
    expect(n.state.methods.single.revision, 2);
    expect(n.state.methods.single.isDefault, isTrue);
  });
  test('removal hides acknowledged old method before loading atomic successor',
      () async {
    final repo = _Methods()..rows = [first, second];
    final n = await _notifier(repo);
    addTearDown(n.dispose);
    repo.nextLoad = Completer();
    final result = n.remove(first.id);
    await Future<void>.delayed(Duration.zero);
    expect(n.state.methods.map((m) => m.id), ['second']);
    expect(repo.preferredCalls, 0);
    repo.nextLoad!.complete([second.copyWith(isDefault: true)]);
    expect(await result, isTrue);
    expect(n.state.methods.single.isDefault, isTrue);
  });
  test('failed removal retains current methods and reports error', () async {
    final n = await _notifier(_Methods()..fail = true);
    addTearDown(n.dispose);
    expect(await n.remove(first.id), isFalse);
    expect(n.state.methods.single, first);
    expect(n.state.errorMessage, isNotNull);
  });
  test('late replacement cannot commit after account generation changes',
      () async {
    final scope = SessionScope();
    final repo = _Methods()..delayedSave = Completer();
    final n = PaymentMethodsNotifier(
        ownerUserId: 'owner',
        repository: repo,
        captureSession: () => scope.capture('owner'),
        sessionIsCurrent: (stamp) => scope.isCurrent(stamp, 'owner'));
    addTearDown(n.dispose);
    await Future<void>.delayed(Duration.zero);
    final result = n.updateDraft(first, draft);
    scope.advance('owner');
    repo.delayedSave!
        .complete(first.copyWith(displayName: 'Late private result'));
    expect(await result, isFalse);
    expect(n.state.methods.single, first);
  });
  testWidgets(
      'edit keeps form on failure and closes only after acknowledged save',
      (tester) async {
    final repo = _Methods()..fail = true;
    await tester.pumpWidget(ProviderScope(
        overrides: [
          paymentMethodsProvider('owner').overrideWith((ref) =>
              PaymentMethodsNotifier(ownerUserId: 'owner', repository: repo))
        ],
        child: const MaterialApp(
            home: Scaffold(body: PaymentMethodsSheet(ownerUserId: 'owner')))));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit or replace QR'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Payment Method'), findsOneWidget);
    expect(find.textContaining('saved QR will be kept'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Updated');
    final save = find.text('Save Payment Method');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Could not verify the save. Your draft is kept. Refresh and try again.'),
        findsOneWidget);
    expect(find.text('Edit Payment Method'), findsOneWidget);
    repo.fail = false;
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Edit Payment Method'), findsNothing);
    expect(find.text('Updated'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
