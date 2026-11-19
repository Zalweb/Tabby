import 'package:tabby/shared/widgets/tabby_mascot_widget.dart';
import 'package:tabby/shared/widgets/tabby_mascot_sprite.dart';
import 'package:tabby/shared/widgets/tabby_mascot_frame_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tabby/core/config/app_state.dart';
import 'package:tabby/core/config/supabase_config.dart';
import 'package:tabby/core/theme/tabby_theme.dart';
import 'package:tabby/features/auth/application/registration_flow.dart';
import 'package:tabby/features/auth/presentation/auth_welcome_widgets.dart';
import 'package:tabby/features/auth/presentation/login_screen.dart';
import 'package:tabby/features/onboarding/presentation/onboarding_screen.dart';
import 'package:tabby/core/theme/tabby_palette.dart';
import 'package:tabby/features/home/presentation/home_dashboard_screen.dart';
import 'package:tabby/features/tabs/presentation/my_tabs_screen.dart';
import 'package:tabby/features/tabs/presentation/tab_detail_screen.dart';
import 'package:tabby/features/connections/presentation/connections_screen.dart';
import 'package:tabby/features/profile/presentation/profile_screen.dart';
import 'package:tabby/features/profile/presentation/privacy_controls_screen.dart';

import '../test/support/warm_design_fixture.dart';
import '../test/support/daily_home_fixture.dart';

import 'package:tabby/main.dart';
import 'package:tabby/core/router/app_router.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/shared/widgets/tabby_button.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('TABBY_USB_TEST')) {
    throw StateError('Google entry fixtures require isolated test package');
  }
  const actor = 'synthetic-qa025-entry';
  const storage = FlutterSecureStorage();
  setUp(() {
    RegistrationFlow.reset();
    SupabaseConfig.debugUserIdOverride = actor;
  });
  tearDown(() {
    SupabaseConfig.debugUserIdOverride = null;
    RegistrationFlow.reset();
  });

  testWidgets(
    'native Google welcome has one sign-in action and real transparent artwork',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: TabbyTheme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: const LoginScreen(),
          ),
        ),
      );
      await precacheImage(
        const AssetImage('assets/branding/tabby-welcome-v3.png'),
        tester.element(find.byType(WelcomeMascot)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(WelcomeMascot), findsOneWidget);
      expect(find.text('Continue Offline'), findsNothing);
      expect(find.text('Continue with Apple'), findsNothing);
      await tester.ensureVisible(find.text('Continue with Google'));
      expect(find.text('Continue with Google').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'native introduction back next and encrypted account acknowledgment',
    (tester) async {
      await storage.delete(key: RegistrationFlow.key(actor));
      await RegistrationFlow.refresh(profileCheck: (_) async => true);
      final router = GoRouter(
        initialLocation: '/onboarding',
        routes: [
          GoRoute(
            path: '/onboarding',
            builder: (_, _) => const OnboardingScreen(),
          ),
          GoRoute(
            path: '/complete-profile',
            builder: (_, _) =>
                const Scaffold(body: Text('Required profile setup')),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(
          theme: TabbyTheme.lightTheme,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Next'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('One tab for every friend.'), findsOneWidget);
      await tester.ensureVisible(find.text('Back'));
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text("Hi, I'm Tabby."), findsOneWidget);
      await tester.ensureVisible(find.text('Skip'));
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.text('Required profile setup'), findsOneWidget);
      expect(await storage.read(key: RegistrationFlow.key(actor)), 'true');
      expect(AppState.profileCompletionRequired.value, isTrue);
      RegistrationFlow.reset();
      await RegistrationFlow.refresh(profileCheck: (_) async => true);
      expect(AppState.introductionRequired.value, isFalse);
      expect(
        await storage.read(
          key: RegistrationFlow.key('synthetic-other-account'),
        ),
        isNull,
      );
      await storage.delete(key: RegistrationFlow.key(actor));
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'native registration lookup failure is retryable without home bypass',
    (tester) async {
      await expectLater(
        RegistrationFlow.refresh(profileCheck: (_) async => null),
        throwsStateError,
      );
      expect(AppState.registrationCheckPending.value, isTrue);
      expect(AppState.registrationError.value, isNotNull);
      await RegistrationFlow.refresh(profileCheck: (_) async => false);
      expect(AppState.registrationCheckPending.value, isFalse);
      expect(AppState.introductionRequired.value, isFalse);
    },
  );
  testWidgets(
    'native main pages and settings share warm light and dark surfaces',
    (tester) async {
      for (final dark in [false, true]) {
        final palette = dark ? TabbyPalette.dark : TabbyPalette.light;
        for (final screen in const <Widget>[
          HomeDashboardScreen(),
          MyTabsScreen(),
          TabDetailScreen(tabId: 'warm-tab'),
          ConnectionsScreen(),
          ProfileScreen(),
          PrivacyControlsScreen(),
        ]) {
          await tester.pumpWidget(warmHost(screen, dark: dark));
          await tester.pumpAndSettle();
          final scaffold = find.byType(Scaffold).first;
          expect(
            tester.widget<Scaffold>(scaffold).backgroundColor ??
                Theme.of(tester.element(scaffold)).scaffoldBackgroundColor,
            palette.canvas,
          );
          expect(
            Theme.of(tester.element(scaffold)).colorScheme.onPrimary,
            TabbyPalette.light.text,
          );
          expect(tester.takeException(), isNull);
          if (screen is HomeDashboardScreen) {
            expect(
              tester.widget<Text>(find.text('This month')).style?.color,
              TabbyPalette.light.text,
            );
          }
          if (screen is ProfileScreen) {
            await tester.ensureVisible(find.text('Appearance'));
            await tester.tap(find.text('Appearance'));
            await tester.pumpAndSettle();
            expect(find.text('Dark mode'), findsOneWidget);
            final heading = find.descendant(
              of: find.byType(BottomSheet),
              matching: find.text('Appearance'),
            );
            final surface = find
                .ancestor(of: heading, matching: find.byType(Material))
                .first;
            expect(tester.getRect(surface).left, closeTo(0, 0.1));
            expect(
              tester.getSize(surface).width,
              closeTo(
                tester.view.physicalSize.width / tester.view.devicePixelRatio,
                0.1,
              ),
            );
            final sheetTheme = Theme.of(tester.element(find.text('Dark mode')));
            final choice = tester.widget<ListTile>(
              find.ancestor(
                of: find.text('Light mode'),
                matching: find.byType(ListTile),
              ),
            );
            expect(
              (choice.shape! as RoundedRectangleBorder).borderRadius,
              BorderRadius.circular(16),
            );
            expect(
              sheetTheme.bottomSheetTheme.backgroundColor,
              palette.surface,
            );
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      }
    },
  );
  testWidgets(
    'native daily debt dashboard add action opens the real creation wizard',
    (tester) async {
      SupabaseConfig.debugUserIdOverride = warmOwner.id;
      AppState.isAuthenticated.value = true;
      AppState.hasSeenOnboarding.value = true;
      AppState.profileCompletionRequired.value = false;
      appRouter.go('/home');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith(
              (_) =>
                  CurrentUserNotifier(initialUser: warmOwner, autoLoad: false),
            ),
            tabbyProvider.overrideWith((_) => dailyHomeLedger()),
            userSettingsProvider.overrideWith(
              (_) => UserSettingsNotifier(
                userId: warmOwner.id,
                notificationsChanged: () async => false,
              ),
            ),
          ],
          child: const TabbyApp(enableUpdateCheck: false),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('NET BALANCE'), findsOneWidget);
      expect(find.text('2 of 3 clear for you'), findsOneWidget);
      final add = find.byKey(const ValueKey('navigation-create-tab'));
      expect(add.hitTestable(), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      final screenWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(tester.getCenter(add).dx, greaterThan(screenWidth / 2));
      final dock = tester.getRect(
        find.byKey(const ValueKey('tabby-navigation-dock')),
      );
      final addRect = tester.getRect(add);
      expect(dock.left, closeTo(16, 1));
      expect(addRect.right, closeTo(screenWidth - 16, 1));
      expect(addRect.left, closeTo(dock.right + 8, 1));
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('create-tab-add-people')),
        findsOneWidget,
      );
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        tester.getSize(find.byKey(const ValueKey('tabby-fullscreen-form'))),
        Size(
          tester.view.physicalSize.width / tester.view.devicePixelRatio,
          tester.view.physicalSize.height / tester.view.devicePixelRatio,
        ),
      );
      expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
      await tester.ensureVisible(find.text('Add Person'));
      await tester.tap(find.text('Add Person'));
      await tester.pumpAndSettle();
      final error = find.text('Enter a name for the unregistered person.');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('tabby-fullscreen-form')),
          matching: error,
        ),
        findsOneWidget,
      );
      expect(error.hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('Dismiss message'));
      await tester.pumpAndSettle();
      expect(error, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      AppState.isAuthenticated.value = false;
      await const FlutterSecureStorage().delete(
        key: 'tabby_${warmOwner.id}_appearance_v1',
      );
      expect(find.byType(TabbyButton), findsNothing);
    },
  );
  testWidgets(
    'native situation mascot artwork animates and reduced motion stays static',
    (tester) async {
      Widget scene(TabbyMascotPose pose, {bool reduced = false}) => MaterialApp(
        theme: TabbyTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: TabbyMascotWidget.art(
              pose: pose,
              size: 128,
              animateAmbient: true,
            ),
          ),
        ),
      );
      for (final pose in TabbyMascotPose.values) {
        await tester.pumpWidget(scene(pose));
        final sprite = tester.widget<TabbyMascotSprite>(
          find.byType(TabbyMascotSprite).last,
        );
        await precacheImage(
          ResizeImage.resizeIfNeeded(
            sprite.decodeWidth,
            null,
            AssetImage(sprite.asset),
          ),
          tester.element(find.byType(TabbyMascotSprite).last),
        );
        await tester.pump(const Duration(milliseconds: 250));
        final sheet = mascotFrameSheets[pose.name];
        if (sheet != null) {
          await precacheImage(
            ResizeImage.resizeIfNeeded(
              sprite.sheetDecodeWidth,
              null,
              AssetImage(sheet.asset),
            ),
            tester.element(find.byType(TabbyMascotSprite).last),
          );
          await tester.pump();
          TabbyMascotSpritePainter framePainter() => tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .map((w) => w.painter)
              .whereType<TabbyMascotSpritePainter>()
              .last;
          expect(sheet.sources, contains(framePainter().normalizedSource));
          if (!sheet.finite) {
            final before = framePainter().normalizedSource;
            // Actual native clock/timer: sample past the quiet hold and
            // observe an eye-frame change rather than infer it from text.
            var changed = false;
            for (var i = 0; i < 45; i++) {
              await tester.pump(const Duration(milliseconds: 80));
              if (framePainter().normalizedSource != before) {
                changed = true;
                break;
              }
            }
            expect(changed, isTrue);
          }
        }
        expect(find.byKey(ValueKey('mascot-art-${pose.name}')), findsOneWidget);
        final painters = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((w) => w.painter)
            .whereType<TabbyMascotSpritePainter>();
        expect(painters, isNotEmpty);
        expect(painters.last.image.width, greaterThan(0));
        if (pose == TabbyMascotPose.thinking) {
          final before = tester
              .widget<Transform>(find.byKey(const ValueKey('mascot-motion')))
              .transform
              .storage
              .toList();
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            tester
                .widget<Transform>(find.byKey(const ValueKey('mascot-motion')))
                .transform
                .storage
                .toList(),
            isNot(before),
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
      await tester.pumpWidget(scene(TabbyMascotPose.thinking, reduced: true));
      await tester.pump(const Duration(milliseconds: 500));
      final before = tester
          .widget<Transform>(find.byKey(const ValueKey('mascot-motion')))
          .transform
          .storage
          .toList();
      await tester.pump(const Duration(seconds: 2));
      expect(
        tester
            .widget<Transform>(find.byKey(const ValueKey('mascot-motion')))
            .transform
            .storage
            .toList(),
        before,
      );
      expect(before[13], 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
