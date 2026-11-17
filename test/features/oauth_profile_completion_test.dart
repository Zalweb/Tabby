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

  for (final route in ['/login', '/signup', '/onboarding']) {
    testWidgets('unauthenticated $route offers Google only', (tester) async {
      appRouter.go(route);
      await tester.pumpWidget(const ProviderScope(child: TabbyApp(enableUpdateCheck: false)));
      await tester.pumpAndSettle();
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Continue Offline'), findsNothing);
      expect(find.text('Continue with Apple'), findsNothing);
      expect(find.text('Create an account'), findsNothing);
      expect(appRouter.routeInformationProvider.value.uri.path, '/login');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
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
    await tester.ensureVisible(find.text('Save and continue'));
    await tester.tap(find.text('Save and continue'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter a valid mobile number.'), findsOneWidget);
  });

  testWidgets('profile completion rejects an empty full name', (tester) async {
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
      find.widgetWithText(TextField, 'Full name'),
      '',
    );
    await tester.ensureVisible(find.text('Save and continue'));
    await tester.tap(find.text('Save and continue'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter your full name.'), findsOneWidget);
  });
}
