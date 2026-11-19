import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/config/app_state.dart';
import 'package:tabby/core/config/supabase_config.dart';
import 'package:tabby/core/router/app_router.dart';
import 'package:tabby/features/auth/application/registration_flow.dart';
import 'package:tabby/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    RegistrationFlow.reset();
    SupabaseConfig.debugUserIdOverride = 'synthetic-registration';
    FlutterSecureStorage.setMockInitialValues({});
    AppState.isAuthenticated.value = true;
    AppState.hasSeenOnboarding.value = true;
  });
  tearDown(() { RegistrationFlow.reset(); SupabaseConfig.debugUserIdOverride = null; AppState.isAuthenticated.value = false; });
  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: TabbyApp(enableUpdateCheck: false)));
    await tester.pumpAndSettle();
  }
  testWidgets('first Google session reaches required profile setup directly', (tester) async {
    AppState.hasSeenOnboarding.value = false;
    AppState.profileCompletionRequired.value = true;
    appRouter.go('/home');
    await mount(tester);
    expect(appRouter.routeInformationProvider.value.uri.path, '/complete-profile');
    expect(find.text('Full name'), findsOneWidget);
    expect(await const FlutterSecureStorage().read(key: RegistrationFlow.key('synthetic-registration')), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('incomplete returning registration goes to profile while completed users skip intro', (tester) async {
    AppState.profileCompletionRequired.value = true;
    appRouter.go('/onboarding');
    await mount(tester);
    expect(appRouter.routeInformationProvider.value.uri.path, '/complete-profile');
    AppState.profileCompletionRequired.value = false;
    appRouter.go('/login');
    await tester.pumpAndSettle();
    expect(appRouter.routeInformationProvider.value.uri.path, '/home');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('unknown registration remains in retry gate with no home bypass', (tester) async {
    AppState.registrationCheckPending.value = true;
    AppState.registrationError.value = 'Your account setup could not be checked. Please try again.';
    appRouter.go('/home');
    await mount(tester);
    expect(appRouter.routeInformationProvider.value.uri.path, '/account-check');
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('could not be checked'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
