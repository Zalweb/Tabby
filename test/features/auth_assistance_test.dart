import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tabby/core/services/auth_email_assistance.dart';
import 'package:tabby/core/services/auth_link_failure.dart';
import 'package:tabby/core/services/auth_recovery_state.dart';
import 'package:tabby/core/services/recovery_password_update.dart';
import 'package:tabby/features/auth/presentation/auth_help_screen.dart';
import 'package:tabby/features/auth/presentation/reset_password_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  const session = '00000000-0000-4000-8000-000000000001';
  test(
      'valid recovery session persists across restart but never transfers to another session/account',
      () async {
    final state = AuthRecoveryState();
    await state.observe(account: 'a', session: session, recovery: true);
    final restored = AuthRecoveryState();
    await restored.observe(account: 'a', session: session);
    expect(restored.active, isTrue);
    await restored.observe(account: 'b', session: session);
    expect(restored.active, isFalse);
    await restored.observe(account: 'a', session: 'different-session');
    expect(restored.active, isFalse);
    await state.complete('a', session);
    final completed = AuthRecoveryState();
    await completed.observe(account: 'a', session: session);
    expect(completed.active, isFalse);
    await completed.observe(account: 'a', session: null, recovery: true);
    expect(completed.active, isFalse);
    expect(completed.linkError, contains('could not be verified'));
  });
  test(
      'late old restore cannot overwrite a fresh recovery and refresh does not lose the marker',
      () async {
    final state = AuthRecoveryState();
    final old = state.observe(account: 'a', session: session);
    final fresh = state.observe(account: 'b', session: 'new', recovery: true);
    await Future.wait([old, fresh]);
    expect(state.allows('b', 'new'), isTrue);
    await state.observe(account: 'b', session: 'new');
    expect(state.active, isTrue);
    await state.observe(account: null, session: null, signedOut: true);
    expect(state.active, isFalse);
    final restored = AuthRecoveryState();
    await restored.observe(account: 'b', session: 'new');
    expect(restored.active, isFalse);
  });
  test(
      'session parsing stores an opaque session ID and rejects missing/malformed claims',
      () {
    final payload = base64Url
        .encode(utf8.encode(jsonEncode({'session_id': session})))
        .replaceAll('=', '');
    expect(AuthRecoveryState.sessionIdFromToken('synthetic.$payload.signature'),
        session);
    for (final token in ['', 'invalid', 'a.e30.b', 'a.@@.b']) {
      expect(AuthRecoveryState.sessionIdFromToken(token), isNull);
    }
  });
  test(
      'SDK URL status-code errors and PKCE failures are recoverable without treating refresh outages as invalid links',
      () {
    expect(
        isAuthLinkFailure(const AuthException('Synthetic',
            code: 'access_denied', statusCode: 'otp_expired')),
        isTrue);
    expect(isAuthLinkFailure(const AuthPKCEGrantCodeExchangeError('Synthetic')),
        isTrue);
    expect(isAuthLinkFailure(AuthRetryableFetchException()), isFalse);
    expect(
        isAuthLinkFailure(const AuthException('Invalid credentials',
            code: 'invalid_credentials')),
        isFalse);
  });
  test('email validation does not consume cooldown or call transport',
      () async {
    var calls = 0;
    final service = AuthEmailAssistance(request: (_, __) async {
      calls++;
    });
    await expectLater(service.send(AuthEmailKind.recovery, 'bad'),
        throwsA(isA<AuthAssistanceException>()));
    expect(calls, 0);
    expect(await service.remainingSeconds(), 0);
  });
  test(
      'cooldown survives response loss, restarts and switching request kind/email',
      () async {
    var now = DateTime.utc(2026, 11, 1), calls = 0;
    final first = AuthEmailAssistance(
        now: () => now,
        request: (_, __) async {
          calls++;
          throw StateError('Response lost');
        });
    await expectLater(
        first.send(AuthEmailKind.recovery, 'synthetic@example.test'),
        throwsStateError);
    final next = AuthEmailAssistance(
        now: () => now,
        request: (_, __) async {
          calls++;
        });
    expect(await next.remainingSeconds(), 60);
    await expectLater(
        next.send(AuthEmailKind.confirmation, 'different@example.test'),
        throwsA(isA<AuthAssistanceException>()));
    expect(calls, 1);
    now = now.add(const Duration(seconds: 61));
    await next.send(AuthEmailKind.confirmation, 'different@example.test');
    expect(calls, 2);
  });
  test('server email rate limit remains actionable and never claims acceptance',
      () async {
    final service = AuthEmailAssistance(request: (_, __) async {
      throw const AuthException('Synthetic rate limit',
          statusCode: '429', code: 'over_email_send_rate_limit');
    });
    await expectLater(
        service.send(AuthEmailKind.confirmation, 'synthetic@example.test'),
        throwsA(isA<AuthAssistanceException>()
            .having((e) => e.message, 'copy', contains('Too many'))));
    expect(await service.remainingSeconds(), greaterThan(0));
  });
  test(
      'ordinary sessions cannot use password reset and mismatched values never call backend',
      () async {
    var calls = 0;
    final recovery = AuthRecoveryState();
    final update = RecoveryPasswordUpdate(
        recovery: recovery,
        account: () => 'a',
        sessionId: () => session,
        captureCurrent: () => () => true,
        update: (_) async {
          calls++;
        });
    await expectLater(update.save('new-password', 'new-password'),
        throwsA(isA<AuthAssistanceException>()));
    await recovery.observe(account: 'a', session: session, recovery: true);
    await expectLater(update.save('new-password', 'different'),
        throwsA(isA<AuthAssistanceException>()));
    expect(calls, 0);
  });
  test(
      'password update waits for acknowledgment and failed update retains recovery for retry',
      () async {
    final recovery = AuthRecoveryState();
    await recovery.observe(account: 'a', session: session, recovery: true);
    var failed = true;
    final reply = Completer<void>();
    final update = RecoveryPasswordUpdate(
        recovery: recovery,
        account: () => 'a',
        sessionId: () => session,
        captureCurrent: () => () => true,
        update: (_) async {
          if (failed) throw StateError('Offline');
          await reply.future;
        });
    await expectLater(
        update.save('new-password', 'new-password'), throwsStateError);
    expect(recovery.active, isTrue);
    failed = false;
    final saved = update.save('new-password', 'new-password');
    await Future<void>.delayed(Duration.zero);
    expect(recovery.active, isTrue);
    reply.complete();
    await saved;
    expect(recovery.active, isFalse);
  });
  test('old update acknowledgment cannot finish another account recovery',
      () async {
    final recovery = AuthRecoveryState();
    await recovery.observe(account: 'a', session: session, recovery: true);
    final reply = Completer<void>();
    var current = true;
    final update = RecoveryPasswordUpdate(
        recovery: recovery,
        account: () => 'a',
        sessionId: () => session,
        captureCurrent: () => () => current,
        update: (_) => reply.future);
    final saved = update.save('new-password', 'new-password');
    current = false;
    await recovery.observe(account: 'b', session: 'new', recovery: true);
    reply.complete();
    await expectLater(saved, throwsA(isA<AuthAssistanceException>()));
    expect(recovery.allows('b', 'new'), isTrue);
  });
  testWidgets(
      'email help waits for acceptance and then displays generic conditional copy/cooldown',
      (tester) async {
    final reply = Completer<void>();
    final service = AuthEmailAssistance(request: (_, __) => reply.future);
    await tester
        .pumpWidget(MaterialApp(home: AuthHelpScreen(assistance: service)));
    await tester.enterText(find.byType(TextField), 'synthetic@example.test');
    await tester.tap(find.text('Send email'));
    await tester.pump();
    expect(find.textContaining('If this address'), findsNothing);
    reply.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('If this address'), findsOneWidget);
    expect(find.textContaining('Try again in'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'reset form reports validation and clears fields only after accepted update',
      (tester) async {
    final recovery = AuthRecoveryState();
    await recovery.observe(account: 'a', session: session, recovery: true);
    final reply = Completer<void>();
    var calls = 0;
    final service = RecoveryPasswordUpdate(
        recovery: recovery,
        account: () => 'a',
        sessionId: () => session,
        captureCurrent: () => () => true,
        update: (_) {
          calls++;
          return reply.future;
        });
    await tester
        .pumpWidget(MaterialApp(home: ResetPasswordScreen(service: service)));
    await tester.enterText(find.byType(TextField).first, 'new-password');
    await tester.enterText(find.byType(TextField).last, 'different');
    await tester.tap(find.text('Save new password'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.textContaining('same password twice'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'new-password');
    await tester.tap(find.text('Save new password'));
    await tester.pump();
    expect(calls, 1);
    expect(recovery.active, isTrue);
    reply.complete();
    await tester.pumpAndSettle();
    expect(recovery.active, isFalse);
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'changing recovery session clears password draft and discards old form completion',
      (tester) async {
    final recovery = AuthRecoveryState();
    await recovery.observe(account: 'a', session: session, recovery: true);
    final reply = Completer<void>();
    final service = RecoveryPasswordUpdate(
        recovery: recovery,
        account: () => 'a',
        sessionId: () => session,
        captureCurrent: () => () => true,
        update: (_) => reply.future);
    await tester
        .pumpWidget(MaterialApp(home: ResetPasswordScreen(service: service)));
    await tester.enterText(find.byType(TextField).first, 'new-password');
    await tester.enterText(find.byType(TextField).last, 'new-password');
    await tester.tap(find.text('Save new password'));
    await tester.pump();
    await recovery.observe(
        account: 'b', session: 'new-session', recovery: true);
    await tester.pump();
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty);
    expect(find.textContaining('Your account changed'), findsOneWidget);
    reply.complete();
    await tester.pumpAndSettle();
    expect(recovery.allows('b', 'new-session'), isTrue);
    expect(find.textContaining('Your account changed'), findsOneWidget);
    recovery.reportInvalidLink();
    await tester.pump();
    expect(find.textContaining('has expired'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
