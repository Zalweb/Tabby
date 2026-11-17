import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tabby/core/config/app_state.dart';
import 'package:tabby/core/config/supabase_config.dart';
import 'package:tabby/core/utils/philippine_phone.dart';
import 'package:tabby/features/auth/application/profile_setup_draft.dart';
import 'package:tabby/features/auth/presentation/complete_profile_screen.dart';
import 'package:tabby/features/payment_methods/domain/payment_method.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';

PaymentMethod accepted(PaymentMethodDraft draft) => PaymentMethod(
    id: draft.methodId!,
    ownerUserId: 'user-me',
    provider: draft.provider,
    displayName: draft.displayName,
    accountLabel: draft.accountLabel);
const first = PaymentMethodDraft(
    provider: 'gcash', displayName: 'Fixture one', accountLabel: 'Manual one');
const second = PaymentMethodDraft(
    provider: 'maya', displayName: 'Fixture two', accountLabel: 'Manual two');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('profile metadata changes preserve loaded account security/preferences',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final before = container.read(userSettingsProvider.notifier);
    await before.ready;
    final profile = container.read(currentUserProvider.notifier);
    profile.state = profile.state.copyWith(
        displayName: 'Changed synthetic name', phone: '+639171234567');
    final after = container.read(userSettingsProvider.notifier);
    expect(identical(before, after), isTrue);
    expect(after.state.isLoaded, isTrue);
  });
  test('an auth-session revision reloads preferences even for the same account',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final before = container.read(userSettingsProvider.notifier);
    await before.ready;
    SupabaseConfig.sessionRevision.value++;
    final after = container.read(userSettingsProvider.notifier);
    await after.ready;
    expect(identical(before, after), isFalse);
    expect(after.scopeId, before.scopeId);
  });
  test('removing a staged preferred method promotes an unattempted successor',
      () async {
    final setup = ProfileSetupDraft('a');
    await setup.add(first);
    await setup.add(second);
    final successor = setup.items.last.draft.methodId,
        operation = setup.items.last.draft.operationId;
    await setup.remove(0);
    expect(setup.items.single.isDefault, isTrue);
    expect(setup.items.single.draft.methodId, successor);
    expect(setup.items.single.draft.operationId, isNot(operation));
    final restored = ProfileSetupDraft('a');
    await restored.restore();
    expect(restored.items.single.isDefault, isTrue);
  });
  test(
      'phone forms share one canonical value and invalid prefixes/characters fail',
      () {
    for (final raw in [
      '09171234567',
      '639171234567',
      '+63 917 123 4567',
      '9171234567',
      '(0917) 123-4567'
    ]) {
      expect(normalizePhilippineMobile(raw), '+639171234567');
    }
    for (final raw in [
      '',
      '08171234567',
      '+1 917 123 4567',
      '0917abc1234567',
      '++639171234567',
      '091712345678',
      '09171234567 ext 1'
    ]) {
      expect(normalizePhilippineMobile(raw), isNull);
    }
  });
  test(
      'partial results survive restart and only unsaved methods retry with frozen IDs',
      () async {
    final setup = ProfileSetupDraft('user-me');
    await setup.add(first);
    await setup.add(second);
    final operations =
        setup.items.map((item) => item.draft.operationId).toList();
    final methodIds = setup.items.map((item) => item.draft.methodId).toList();
    final calls = <String>[];
    expect(
        await setup.saveMethods((draft, _) async {
          calls.add(draft.methodId!);
          return draft.displayName == 'Fixture one' ? accepted(draft) : null;
        }, current: () => true),
        isFalse);
    expect(setup.items.map((item) => item.saved), [true, false]);
    expect(await ProfileSetupDraft.requiresCompletion('user-me'), isTrue);
    final restored = ProfileSetupDraft('user-me');
    await restored.restore();
    expect(restored.items.last.error, isNotNull);
    expect(restored.items.map((item) => item.draft.operationId), operations);
    expect(
        await restored.saveMethods((draft, _) async {
          calls.add(draft.methodId!);
          return accepted(draft);
        }, current: () => true),
        isTrue);
    expect(calls, [methodIds[0], methodIds[1], methodIds[1]]);
  });
  test('lost acknowledgment reuses the same method and operation after restart',
      () async {
    final setup = ProfileSetupDraft('user-me');
    await setup.add(first);
    final server = <String, PaymentMethod>{};
    final commands = <String>[];
    await setup.saveMethods((draft, _) async {
      server[draft.operationId!] = accepted(draft);
      commands.add(draft.operationId!);
      throw StateError('Response lost');
    }, current: () => true);
    final next = ProfileSetupDraft('user-me');
    await next.restore();
    expect(
        await next.saveMethods((draft, _) async {
          commands.add(draft.operationId!);
          return server[draft.operationId];
        }, current: () => true),
        isTrue);
    expect(commands[0], commands[1]);
    expect(server.length, 1);
  });
  test('pending QR bytes are owned and account-scoped', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final setup = ProfileSetupDraft('a');
    await setup.add(PaymentMethodDraft(
        provider: 'other',
        displayName: 'Synthetic owned bytes',
        accountLabel: '',
        qrBytes: bytes));
    bytes[0] = 9;
    final next = ProfileSetupDraft('a');
    expect(await next.restore(), isTrue);
    expect(next.items.single.qrBytes, [1, 2, 3]);
    expect(await ProfileSetupDraft('b').restore(), isFalse);
  });
  test(
      'attempted methods freeze payload-changing preference/removal and reentrant saves do not duplicate',
      () async {
    final setup = ProfileSetupDraft('a');
    await setup.add(first);
    await setup.add(second);
    final reply = Completer<PaymentMethod?>(), entered = Completer<void>();
    var calls = 0;
    final saving = setup.saveMethods((draft, _) async {
      calls++;
      if (calls == 1) {
        entered.complete();
        return reply.future;
      }
      return null;
    }, current: () => true);
    await entered.future;
    expect(
        await setup.saveMethods((draft, _) async => accepted(draft),
            current: () => true),
        isFalse);
    await expectLater(setup.prefer(setup.items.last), throwsStateError);
    await expectLater(setup.remove(0), throwsStateError);
    reply.complete(accepted(setup.items.first.draft));
    expect(await saving, isFalse);
    expect(calls, 2);
  });
  test('deferred methods remain resumable without forcing setup at startup',
      () async {
    final setup = ProfileSetupDraft('a');
    await setup.add(first);
    await setup.defer();
    expect(await ProfileSetupDraft.requiresCompletion('a'), isFalse);
    expect(await ProfileSetupDraft.hasRetainedMethods('a'), isTrue);
    final next = ProfileSetupDraft('a');
    await next.restore();
    expect(next.items.single.draft.methodId, setup.items.single.draft.methodId);
  });
  test(
      'intent persistence failure prevents transport and preference failure rolls back its draft',
      () async {
    final storage = ToggleStorage();
    final setup = ProfileSetupDraft('a', storage: storage);
    await setup.add(first);
    await setup.add(second);
    final ids = setup.items.map((item) => item.draft.operationId).toList();
    storage.fail = true;
    var calls = 0;
    await expectLater(setup.prefer(setup.items.last), throwsStateError);
    expect(setup.items.map((item) => item.draft.operationId), ids);
    expect(setup.items.first.isDefault, isTrue);
    await expectLater(
        setup.saveMethods((draft, _) async {
          calls++;
          return accepted(draft);
        }, current: () => true),
        throwsStateError);
    expect(calls, 0);
    expect(setup.isSaving, isFalse);
  });
  test(
      'session change/disposal discards a late result without clearing the pending intent',
      () async {
    final setup = ProfileSetupDraft('a');
    await setup.add(first);
    var current = true;
    final reply = Completer<PaymentMethod?>(), entered = Completer<void>();
    final saving = setup.saveMethods((draft, _) {
      entered.complete();
      return reply.future;
    }, current: () => current);
    await entered.future;
    current = false;
    setup.dispose();
    reply.complete(accepted(setup.items.single.draft));
    expect(await saving, isFalse);
    final restored = ProfileSetupDraft('a');
    await restored.restore();
    expect(restored.items.single.saved, isFalse);
  });
  test('corrupt draft remains untouched rather than silently starting over',
      () async {
    const storage = FlutterSecureStorage();
    await storage.write(key: ProfileSetupDraft.key('a'), value: 'broken');
    await expectLater(ProfileSetupDraft('a').restore(), throwsFormatException);
    expect(await storage.read(key: ProfileSetupDraft.key('a')), 'broken');
  });
  testWidgets(
      'setup remains open on one failed method and completes only after retry acknowledgment',
      (tester) async {
    AppState.profileCompletionRequired.value = true;
    final setup = ProfileSetupDraft('user-me')
      ..name = 'Synthetic owner'
      ..phone = '+639171234567'
      ..step = 1;
    await setup.add(first);
    await setup.add(second);
    final calls = <String, int>{};
    final router = GoRouter(initialLocation: '/complete-profile', routes: [
      GoRoute(
          path: '/complete-profile',
          builder: (_, __) =>
              CompleteProfileScreen(saveMethod: (draft, _) async {
                calls.update(draft.displayName, (n) => n + 1,
                    ifAbsent: () => 1);
                return draft.displayName == 'Fixture two' &&
                        calls[draft.displayName] == 1
                    ? null
                    : accepted(draft);
              })),
      GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Text('Finished setup')))
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Complete Setup and Start'));
    await tester.tap(find.text('Complete Setup and Start'));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);
    expect(find.textContaining('Some receiving methods'), findsOneWidget);
    expect(AppState.profileCompletionRequired.value, isTrue);
    await tester.ensureVisible(find.text('Retry Unsaved Methods'));
    await tester.tap(find.text('Retry Unsaved Methods'));
    await tester.pumpAndSettle();
    expect(find.text('Finished setup'), findsOneWidget);
    expect(calls, {'Fixture one': 1, 'Fixture two': 2});
    expect(AppState.profileCompletionRequired.value, isFalse);
    expect(
        await const FlutterSecureStorage()
            .read(key: ProfileSetupDraft.key('user-me')),
        isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class ToggleStorage extends FlutterSecureStorage {
  bool fail = false;
  @override
  Future<void> write(
      {required String key,
      required String? value,
      IOSOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      MacOsOptions? mOptions,
      WindowsOptions? wOptions}) async {
    if (fail) throw StateError('Synthetic persistence failure');
    await super.write(
        key: key,
        value: value,
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions);
  }
}
