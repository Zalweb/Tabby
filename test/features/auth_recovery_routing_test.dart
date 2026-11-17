import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/config/app_state.dart';
import 'package:tabby/core/router/app_router.dart';
import 'package:tabby/core/services/auth_recovery_state.dart';
import 'package:tabby/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await AuthRecoveryState.instance
        .observe(account: null, session: null, signedOut: true);
    AuthRecoveryState.instance.clearLinkError();
    AppState.hasSeenOnboarding.value = true;
    AppState.profileCompletionRequired.value = false;
  });
  testWidgets(
      'recovery event routes to reset before profile/home and completion releases gate',
      (tester) async {
    AppState.isAuthenticated.value = true;
    await AuthRecoveryState.instance.observe(
        account: 'synthetic', session: 'synthetic-session', recovery: true);
    appRouter.go('/home');
    await tester.pumpWidget(
        const ProviderScope(child: TabbyApp(enableUpdateCheck: false)));
    await tester.pumpAndSettle();
    expect(find.text('Reset password'), findsOneWidget);
    expect(find.text('Save new password'), findsOneWidget);
    await AuthRecoveryState.instance.complete('synthetic', 'synthetic-session');
    await tester.pumpAndSettle();
    expect(find.text('Save new password'), findsNothing);
    expect(appRouter.routeInformationProvider.value.uri.path, '/home');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'expired callback routes to actionable help and can return to sign in',
      (tester) async {
    AppState.isAuthenticated.value = false;
    AuthRecoveryState.instance.reportInvalidLink();
    appRouter.go('/login');
    await tester.pumpWidget(
        const ProviderScope(child: TabbyApp(enableUpdateCheck: false)));
    await tester.pumpAndSettle();
    expect(find.text('Account help'), findsOneWidget);
    expect(find.textContaining('has expired'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(AuthRecoveryState.instance.linkError, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
