import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tabby/features/onboarding/application/first_launch_tour.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabby/main.dart';
import 'package:tabby/core/config/app_state.dart';
import 'package:tabby/core/router/app_router.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    AppState.isAuthenticated.value = false;
    AppState.hasSeenOnboarding.value = false;
    AppState.profileCompletionRequired.value = false;
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: TabbyApp(enableUpdateCheck: false)));
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, String label) async {
    final button = find.text(label);
    await tester.ensureVisible(button);
    expect(button.hitTestable(), findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('fresh launch shows the mascot tour before Google login', (tester) async {
    appRouter.go('/login');
    await mount(tester);
    expect(find.text('One tab for every friend.'), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing);
    await press(tester, 'Next');
    expect(find.text('Balances and receipts, together.'), findsOneWidget);
    await press(tester, 'Back');
    expect(find.text('One tab for every friend.'), findsOneWidget);
    await press(tester, 'Next');
    await press(tester, 'Next');
    expect(find.text('Settle up, stay friends.'), findsOneWidget);
    await press(tester, 'Continue to sign in');
    expect(appRouter.routeInformationProvider.value.uri.path, '/login');
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(FirstLaunchTour.storageKey), isTrue);
  });

  testWidgets('skipping persists locally and a later launch goes to login', (tester) async {
    appRouter.go('/login');
    await mount(tester);
    await press(tester, 'Next');
    await press(tester, 'Skip');
    expect(find.text('Continue with Google'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    AppState.hasSeenOnboarding.value = false;
    await FirstLaunchTour.restore();
    appRouter.go('/onboarding');
    await mount(tester);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(appRouter.routeInformationProvider.value.uri.path, '/login');
  });

  testWidgets('restored authenticated account bypasses the fresh launch tour', (tester) async {
    AppState.isAuthenticated.value = true;
    appRouter.go('/login');
    await mount(tester);
    expect(appRouter.routeInformationProvider.value.uri.path, '/home');
    expect(find.text('One tab for every friend.'), findsNothing);
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
