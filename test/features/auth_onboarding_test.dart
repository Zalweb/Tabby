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

  testWidgets('App opens Onboarding by default on first launch',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const ProviderScope(
        child: TabbyApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Onboarding slide 1 content
    expect(find.text('Keep tabs on every shared expense'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);

    // Tap Next to advance to slide 2
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Always know who owes who'), findsOneWidget);

    // Tap Next to advance to slide 3
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Settle up without the awkwardness'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);

    // Tap Get Started -> should land on Login screen
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    expect(AppState.hasSeenOnboarding.value, isTrue);
    expect(find.text('Tabby'), findsOneWidget);
    expect(find.text('Keep tabs. Settle up.'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
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
    expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);

    // Tap Google OAuth while the backend is unavailable. Local/mock auth must
    // not unlock the app.
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
