import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabby/main.dart';
import 'package:tabby/core/config/app_state.dart';

void main() {
  setUp(() {
    AppState.isAuthenticated.value = false;
    AppState.hasSeenOnboarding.value = false;
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
    expect(find.text('Log In'), findsOneWidget);
  });

  testWidgets('Login refuses to authenticate when Supabase is unavailable',
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

    // Should be on Login screen
    expect(find.text('Log In'), findsOneWidget);

    // Tap Log In without typing anything
    await tester.tap(find.text('Log In'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter email and password'), findsOneWidget);
    expect(AppState.isAuthenticated.value, isFalse);

    // Enter email and password
    final textFields = find.byType(TextField);
    await tester.enterText(textFields.at(0), 'frienzal@tabby.ph');
    await tester.enterText(textFields.at(1), 'password123');
    await tester.pumpAndSettle();

    // Tap Log In while the backend is unavailable. Local/mock auth must not unlock the app.
    await tester.tap(find.text('Log In'));
    await tester.pumpAndSettle();

    expect(AppState.isAuthenticated.value, isFalse);
    expect(
        find.text(
            'Authentication service is unavailable. Please try again when online.'),
        findsOneWidget);
  });

  testWidgets('SignUp refuses to authenticate when Supabase is unavailable',
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

    // Tap Sign Up link
    await tester.ensureVisible(find.text('Sign Up'));
    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget);

    // Try submitting empty form
    await tester.ensureVisible(find.text('Create Account'));
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();

    expect(find.text('Please fill in all fields'), findsOneWidget);

    // Fill form fields
    final textFields = find.byType(TextField);
    await tester.enterText(textFields.at(0), 'Frienzal User');
    await tester.enterText(textFields.at(1), 'frienzal@test.com');
    await tester.enterText(textFields.at(2), '+63 917 123 4567');
    await tester.enterText(textFields.at(3), 'pass123');
    await tester.enterText(textFields.at(4), 'pass123');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Create Account'));
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();

    expect(AppState.isAuthenticated.value, isFalse);
    expect(
        find.text(
            'Authentication service is unavailable. Please try again when online.'),
        findsOneWidget);
  });
}
