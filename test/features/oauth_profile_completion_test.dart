import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabby/core/config/app_state.dart';
import 'package:tabby/core/router/app_router.dart';
import 'package:tabby/features/tabs/data/supabase_tabby_repository.dart';
import 'package:tabby/main.dart';

void main() {
  setUp(() {
    AppState.isAuthenticated.value = false;
    AppState.hasSeenOnboarding.value = true;
    AppState.profileCompletionRequired.value = false;
  });

  test('profile completion is required when an OAuth profile has no phone', () {
    expect(
      SupabaseTabbyRepository.profileNeedsCompletion({
        'display_name': 'Google User',
        'phone': '',
      }),
      isTrue,
    );
  });

  test('profile completion is not required when name and phone are present',
      () {
    expect(
      SupabaseTabbyRepository.profileNeedsCompletion({
        'display_name': 'Google User',
        'phone': '+63 917 123 4567',
      }),
      isFalse,
    );
  });

  testWidgets('login exposes Google OAuth and email credentials',
      (tester) async {
    appRouter.go('/login');

    await tester.pumpWidget(
      const ProviderScope(
        child: TabbyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Create an account'), findsOneWidget);
  });

  testWidgets('signup collects profile details and password confirmation',
      (tester) async {
    appRouter.go('/signup');

    await tester.pumpWidget(
      const ProviderScope(
        child: TabbyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create your Tabby account'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Full name'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Mobile number'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Confirm password'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
  });

  testWidgets('signup rejects mismatched passwords before contacting Supabase',
      (tester) async {
    appRouter.go('/signup');

    await tester.pumpWidget(
      const ProviderScope(
        child: TabbyApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Full name'),
      'Alex User',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'alex@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Mobile number'),
      '09171234567',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'Password123',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm password'),
      'Password321',
    );
    final createAccountButton = find.text('Create account');
    await tester.ensureVisible(createAccountButton);
    await tester.tap(createAccountButton);
    await tester.pumpAndSettle();

    expect(find.text('Passwords do not match.'), findsOneWidget);
  });

  testWidgets('authenticated users can open the profile completion screen',
      (tester) async {
    AppState.isAuthenticated.value = true;
    AppState.profileCompletionRequired.value = true;
    appRouter.go('/complete-profile');

    await tester.pumpWidget(
      const ProviderScope(
        child: TabbyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Complete your profile'), findsOneWidget);
    expect(find.text('Mobile number'), findsOneWidget);
  });

  testWidgets('profile completion rejects an invalid mobile number',
      (tester) async {
    AppState.isAuthenticated.value = true;
    AppState.profileCompletionRequired.value = true;
    appRouter.go('/complete-profile');

    await tester.pumpWidget(
      const ProviderScope(
        child: TabbyApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Mobile number'),
      '123',
    );
    await tester.tap(find.text('Save and continue'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter a valid mobile number.'), findsOneWidget);
  });
}
