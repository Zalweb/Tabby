import '../theme/tabby_palette.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/app_state.dart';
import '../config/supabase_config.dart';
import '../../features/home/presentation/home_dashboard_screen.dart';
import '../../features/navigation/presentation/main_scaffold.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/connections/presentation/connections_screen.dart';
import '../../features/tabs/presentation/my_tabs_screen.dart';
import '../../features/tabs/presentation/tab_detail_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/auth/presentation/complete_profile_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/registration_check_screen.dart';
import '../../features/auth/presentation/auth_help_screen.dart';
import '../../features/auth/presentation/reset_password_screen.dart';
import '../services/auth_recovery_state.dart';
import '../services/auth_email_assistance.dart';

import '../../shared/widgets/tabby_button.dart';
import '../../shared/widgets/tabby_mascot_widget.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);
final GlobalKey<NavigatorState> _homeNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'home',
);
final GlobalKey<NavigatorState> _tabsNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'tabs',
);
final GlobalKey<NavigatorState> _profileNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'profile');
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>(debugLabel: 'scaffoldMessenger');

bool _hasAuthenticatedSession() {
  // Always trust the in-memory AppState flag as the single source of truth.
  // AppState.isAuthenticated is set synchronously before signOut() fires,
  // so the router redirects to /login immediately without waiting for the
  // async Supabase token revocation to complete.
  return AppState.isAuthenticated.value;
}

final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/login',
  errorBuilder: (context, state) {
    final isAuthenticated = _hasAuthenticatedSession();
    return Scaffold(
      backgroundColor: TabbyPalette.of(context).canvas,
      appBar: AppBar(
        backgroundColor: TabbyPalette.of(context).canvas,
        title: Text(
          'Tabby',
          style: TextStyle(
            color: TabbyPalette.of(context).text,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const TabbyMascotWidget.art(
                pose: TabbyMascotPose.helpful,
                size: 90,
              ),
              const SizedBox(height: 16),
              Text(
                'Page Not Found',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: TabbyPalette.of(context).text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "The page you're looking for doesn't exist or has been moved.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: TabbyPalette.of(context).secondaryText,
                ),
              ),
              const SizedBox(height: 24),
              TabbyButton(
                label: isAuthenticated ? 'Back to Home' : 'Back to Login',
                variant: TabbyButtonVariant.primary,
                onPressed: () =>
                    context.go(isAuthenticated ? '/home' : '/login'),
              ),
            ],
          ),
        ),
      ),
    );
  },
  refreshListenable: Listenable.merge([
    AppState.isAuthenticated,
    AppState.hasSeenOnboarding,
    AppState.registrationCheckPending,
    AppState.profileCompletionRequired,
    AuthRecoveryState.instance,
    SupabaseConfig.sessionRevision,
  ]),
  redirect: (context, state) {
    final bool auth = _hasAuthenticatedSession();
    final String path = state.uri.path;
    final recovery = AuthRecoveryState.instance;
    if (auth && recovery.active) {
      return path == '/reset-password' || path == '/auth-help'
          ? null
          : '/reset-password';
    }
    if (recovery.linkError != null) {
      return path == '/auth-help' ? null : '/auth-help';
    }
    if (path == '/auth-help' || (!auth && path == '/reset-password')) {
      return null;
    }

    if (!auth) {
      // Fresh installs see the first-launch tour before Google sign-in.
      // Recovery routes above keep precedence; seen installs go straight to
      // the existing Google-only welcome.
      if (!AppState.hasSeenOnboarding.value) {
        return path == '/onboarding' ? null : '/onboarding';
      }
      return path == '/login' ? null : '/login';
    } else {
      if (AppState.registrationCheckPending.value) {
        return path == '/account-check' ? null : '/account-check';
      }
      if (AppState.profileCompletionRequired.value) {
        if (path == '/complete-profile') return null;
        return '/complete-profile';
      }
      if (path == '/account-check') return '/home';

      if (path == '/login' ||
          path == '/signup' ||
          path == '/onboarding' ||
          (path == '/complete-profile' &&
              state.uri.queryParameters['resume'] != 'true')) {
        return '/home';
      }
      if (path == '/reset-password') return '/home';
    }
    return null;
  },
  routes: [
    GoRoute(
      path: '/account-check',
      builder: (_, _) => const RegistrationCheckScreen(),
    ),
    GoRoute(
      path: '/auth-help',
      builder: (context, state) => AuthHelpScreen(
        initialKind: state.uri.queryParameters['kind'] == 'confirmation'
            ? AuthEmailKind.confirmation
            : AuthEmailKind.recovery,
      ),
    ),
    GoRoute(
      path: '/reset-password',
      builder: (context, state) => const ResetPasswordScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/signup', builder: (context, state) => const LoginScreen()),
    GoRoute(
      path: '/complete-profile',
      builder: (context, state) => CompleteProfileScreen(
        key: ValueKey(SupabaseConfig.currentUserId ?? 'offline'),
      ),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return MainScaffold(navigationShell: navigationShell);
      },
      branches: [
        // 1. Home Dashboard Branch
        StatefulShellBranch(
          navigatorKey: _homeNavigatorKey,
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomeDashboardScreen(),
            ),
          ],
        ),

        // 2. My Tabs Branch
        StatefulShellBranch(
          navigatorKey: _tabsNavigatorKey,
          routes: [
            GoRoute(
              path: '/tabs',
              builder: (context, state) => const MyTabsScreen(),
              routes: [
                GoRoute(
                  path: ':tabId',
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) {
                    final tabId = state.pathParameters['tabId'] ?? '';
                    return TabDetailScreen(tabId: tabId);
                  },
                ),
              ],
            ),
          ],
        ),

        // 3. Profile Branch
        StatefulShellBranch(
          navigatorKey: _profileNavigatorKey,
          routes: [
            GoRoute(
              path: '/profile',
              builder: (context, state) => const ProfileScreen(),
              routes: [
                GoRoute(
                  path: 'connections',
                  builder: (context, state) => const ConnectionsScreen(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);
