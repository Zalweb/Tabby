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

  testWidgets('login exposes Google OAuth without local credentials form',
      (tester) async {
    appRouter.go('/login');

    await tester.pumpWidget(
      const ProviderScope(
        child: TabbyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Forgot password?'), findsNothing);
    expect(find.text('Sign Up'), findsNothing);
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
