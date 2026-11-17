import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabby/main.dart';
import 'package:tabby/core/config/app_state.dart';
import 'package:tabby/core/router/app_router.dart';

void main() {
  setUp(() {
    AppState.isAuthenticated.value = false;
    AppState.hasSeenOnboarding.value = false;
    AppState.profileCompletionRequired.value = false;
  });

  testWidgets('First launch opens Google welcome before any introduction', (tester) async {
    appRouter.go('/onboarding');
    await tester.pumpWidget(const ProviderScope(child: TabbyApp(enableUpdateCheck: false)));
    await tester.pumpAndSettle();
    expect(find.text('Tabby'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Next'), findsNothing);
    expect(appRouter.routeInformationProvider.value.uri.path, '/login');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'Google OAuth refuses to authenticate when Supabase is unavailable',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    AppState.hasSeenOnboarding.value = true;
    AppState.isAuthenticated.value = false;

    await tester.pumpWidget(
      const ProviderScope(
        child: TabbyApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Should be on the Google OAuth screen.
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Email'), findsNothing);
    expect(find.widgetWithText(TextField, 'Password'), findsNothing);

    // Tap Google OAuth while the backend is unavailable. Local/mock auth must
    // not unlock the app.
    await tester.ensureVisible(find.text('Continue with Google'));
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(AppState.isAuthenticated.value, isFalse);
    expect(
        find.text(
            'Authentication service is unavailable. Please try again when online.'),
        findsOneWidget);
  });

  testWidgets('Profile completion is gated behind an authenticated session',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    AppState.hasSeenOnboarding.value = true;
    AppState.isAuthenticated.value = false;

    await tester.pumpWidget(
      const ProviderScope(
        child: TabbyApp(),
      ),
    );
    await tester.pumpAndSettle();

    AppState.isAuthenticated.value = true;
    AppState.profileCompletionRequired.value = true;
    appRouter.go('/complete-profile');
    await tester.pumpAndSettle();

    expect(find.text('Complete your profile'), findsOneWidget);
    expect(find.text('Mobile number'), findsOneWidget);
  });
}
