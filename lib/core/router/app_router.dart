import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../config/app_state.dart';
import '../../features/home/presentation/home_dashboard_screen.dart';
import '../../features/navigation/presentation/main_scaffold.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/connections/presentation/connections_screen.dart';
import '../../features/tabs/presentation/my_tabs_screen.dart';
import '../../features/tabs/presentation/tab_detail_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/auth/presentation/complete_profile_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/classroom/presentation/classroom_tasks_screen.dart';

import '../theme/tabby_colors.dart';
import '../../features/tabs/domain/models.dart';
import '../../shared/widgets/tabby_button.dart';
import '../../shared/widgets/tabby_mascot_widget.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');
final GlobalKey<NavigatorState> _homeNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'home');
final GlobalKey<NavigatorState> _tabsNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'tabs');
final GlobalKey<NavigatorState> _profileNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'profile');
final GlobalKey<NavigatorState> _classroomNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'classroom');
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
  initialLocation: '/onboarding',
  errorBuilder: (context, state) {
    final isAuthenticated = _hasAuthenticatedSession();
    return Scaffold(
      backgroundColor: TabbyColors.bgCanvas,
      appBar: AppBar(
        backgroundColor: TabbyColors.brandEmerald,
        title: const Text(
          'Tabby',
          style: TextStyle(
            color: TabbyColors.brandDarkTeal,
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
              const TabbyMascotWidget(
                emotion: MascotEmotion.idleNeutral,
                size: 90,
                showBubble: false,
              ),
              const SizedBox(height: 16),
              const Text(
                'Page Not Found',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: TabbyColors.brandDarkTeal,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "The page you're looking for doesn't exist or has been moved.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: TabbyColors.textSecondary,
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
    AppState.profileCompletionRequired,
  ]),
  redirect: (context, state) {
    final bool auth = _hasAuthenticatedSession();
    final bool seenOnboarding = AppState.hasSeenOnboarding.value;
    final String path = state.uri.path;

    if (!auth) {
      if (!seenOnboarding) {
        if (path == '/onboarding') return null;
        return '/onboarding';
      } else {
        if (path == '/login' || path == '/signup') return null;
        return '/login';
      }
    } else {
      if (AppState.profileCompletionRequired.value) {
        if (path == '/complete-profile') return null;
        return '/complete-profile';
      }

      if (path == '/login' ||
          path == '/signup' ||
          path == '/onboarding' ||
          path == '/complete-profile') {
        return '/home';
      }
    }
    return null;
  },
  routes: [
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/signup',
      builder: (context, state) => const SignUpScreen(),
    ),
    GoRoute(
      path: '/complete-profile',
      builder: (context, state) => const CompleteProfileScreen(),
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

        // 3. Classroom Tasks Branch
        StatefulShellBranch(
          navigatorKey: _classroomNavigatorKey,
          routes: [
            GoRoute(
              path: '/tasks',
              builder: (context, state) => const ClassroomTasksScreen(),
            ),
          ],
        ),

        // 4. Profile Branch
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
