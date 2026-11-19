import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tabby/core/theme/tabby_theme.dart';
import 'package:tabby/features/home/presentation/home_dashboard_screen.dart';
import 'package:tabby/features/navigation/presentation/main_scaffold.dart';
import 'package:tabby/features/profile/presentation/profile_screen.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/presentation/my_tabs_screen.dart';

import '../support/warm_design_fixture.dart';

const _dockKey = ValueKey('tabby-navigation-dock');
const _searchKey = ValueKey('navigation-search-tabs');

ValueKey<String> _tabKey(String name) =>
    ValueKey('navigation-tab-${name.toLowerCase().replaceAll(' ', '-')}');

ValueKey<String> _labelKey(String name) =>
    ValueKey('navigation-label-${name.toLowerCase().replaceAll(' ', '-')}');

// These pages keep shell geometry independent of the page layouts on main.
Widget _scrollablePage() =>
    Scaffold(body: ListView(children: const [SizedBox(height: 1200)]));

GoRouter _router({String initial = '/home', bool isolatePages = true}) =>
    GoRouter(
      initialLocation: initial,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => MainScaffold(navigationShell: shell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/home',
                  builder: (_, _) => isolatePages
                      ? _scrollablePage()
                      : const HomeDashboardScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/tabs',
                  builder: (_, _) =>
                      isolatePages ? _scrollablePage() : const MyTabsScreen(),
                  routes: [
                    GoRoute(
                      path: ':tabId',
                      builder: (_, state) => Scaffold(
                        body: Text(
                          'Tab detail ${state.pathParameters['tabId']}',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/profile',
                  builder: (_, _) =>
                      isolatePages ? _scrollablePage() : const ProfileScreen(),
                ),
              ],
            ),
          ],
        ),
      ],
    );

Widget _host(
  Widget screen, {
  required bool animate,
  bool dark = false,
  double scale = 1,
  EdgeInsets safeInsets = EdgeInsets.zero,
}) => ProviderScope(
  overrides: [
    currentUserProvider.overrideWith(
      (_) => CurrentUserNotifier(initialUser: warmOwner, autoLoad: false),
    ),
    tabbyProvider.overrideWith((_) => warmLedger()),
    userSettingsProvider.overrideWith(
      (_) => UserSettingsNotifier(
        userId: warmOwner.id,
        notificationsChanged: () async => false,
      ),
    ),
  ],
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: dark ? TabbyTheme.darkTheme : TabbyTheme.lightTheme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: !animate,
        textScaler: TextScaler.linear(scale),
        padding: safeInsets,
        viewPadding: safeInsets,
      ),
      child: child!,
    ),
    home: screen,
  ),
);

Finder _dockLabel(String label) =>
    find.descendant(of: find.byKey(_dockKey), matching: find.text(label));

Future<void> _setSurface(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void _expectBalancedTargets(WidgetTester tester) {
  final targets = [
    for (final label in ['Home', 'My Tabs', 'Profile'])
      tester.getRect(find.byKey(_tabKey(label))),
  ];
  expect(targets[0].width, closeTo(targets[1].width, 0.1));
  expect(targets[1].width, closeTo(targets[2].width, 0.1));
  expect(targets[0].height, greaterThanOrEqualTo(48));
  expect(targets[1].height, greaterThanOrEqualTo(48));
  expect(targets[2].height, greaterThanOrEqualTo(48));
  final firstGap = targets[1].center.dx - targets[0].center.dx;
  final secondGap = targets[2].center.dx - targets[1].center.dx;
  expect(firstGap, closeTo(secondGap, 0.1));
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final dark in [false, true]) {
    for (final size in [
      const Size(320, 568),
      const Size(568, 320),
      const Size(1280, 800),
    ]) {
      testWidgets(
        'expanded bottom row fills safe width and balances destinations at $size dark$dark with 200% text',
        (tester) async {
          await _setSurface(tester, size);
          final router = _router();
          addTearDown(router.dispose);
          await tester.pumpWidget(
            _host(
              Router.withConfig(config: router),
              animate: false,
              dark: dark,
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();

          final dockFinder = find.byKey(_dockKey);
          final addFinder = find.byKey(const ValueKey('navigation-create-tab'));
          final dock = tester.getRect(dockFinder);
          expect(tester.widget<Material>(dockFinder).color, Colors.transparent);
          final add = tester.getRect(addFinder);
          expect(addFinder, findsOneWidget);
          expect(find.byType(FloatingActionButton), findsOneWidget);
          expect(find.byTooltip('Add tab'), findsOneWidget);
          expect(dock.left, closeTo(16, 0.1));
          expect(add.right, closeTo(size.width - 16, 0.1));
          expect(add.left - dock.right, closeTo(8, 0.1));
          expect(add.center.dy, closeTo(dock.center.dy, 0.1));
          expect(add.overlaps(dock), isFalse);
          expect(_dockLabel('Home'), findsOneWidget);
          expect(_dockLabel('My Tabs'), findsNothing);
          expect(_dockLabel('Profile'), findsNothing);
          _expectBalancedTargets(tester);

          for (final label in ['My Tabs', 'Profile', 'Home']) {
            final target = find.byKey(_tabKey(label));
            expect(target.hitTestable(), findsOneWidget);
            await tester.tap(target);
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('navigation-create-tab')),
              label == 'Profile' ? findsNothing : findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }

  testWidgets('safe area insets anchor the dock left and Add right', (
    tester,
  ) async {
    const size = Size(400, 800);
    const safeInsets = EdgeInsets.fromLTRB(24, 0, 32, 20);
    await _setSurface(tester, size);
    final router = _router(initial: '/tabs');
    addTearDown(router.dispose);
    await tester.pumpWidget(
      _host(
        Router.withConfig(config: router),
        animate: false,
        safeInsets: safeInsets,
      ),
    );
    await tester.pumpAndSettle();

    final add = tester.getRect(
      find.byKey(const ValueKey('navigation-create-tab')),
    );
    final dock = tester.getRect(find.byKey(_dockKey));
    expect(dock.left, closeTo(safeInsets.left, 0.1));
    expect(add.right, closeTo(size.width - safeInsets.right, 0.1));
    expect(add.left - dock.right, closeTo(8, 0.1));
    expect(add.center.dy, closeTo(dock.center.dy, 0.1));
    expect(add.center.dy, closeTo(size.height - safeInsets.bottom - 28, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selection label animates while destination slots stay balanced',
    (tester) async {
      await _setSurface(tester, const Size(400, 420));
      final router = _router(initial: '/home');
      addTearDown(router.dispose);
      await tester.pumpWidget(
        _host(Router.withConfig(config: router), animate: true),
      );
      await tester.pumpAndSettle();
      expect(_dockLabel('Home'), findsOneWidget);
      final homeItemWidths = [
        for (final label in ['Home', 'My Tabs', 'Profile'])
          tester.getSize(find.byKey(_tabKey(label))).width,
      ];

      await tester.tap(find.byKey(_tabKey('My Tabs')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      final labelMidWidth = tester
          .getSize(find.byKey(_labelKey('My Tabs')))
          .width;
      expect(labelMidWidth, greaterThan(0));
      _expectBalancedTargets(tester);

      await tester.pumpAndSettle();
      expect(_dockLabel('My Tabs'), findsOneWidget);
      expect(_dockLabel('Home'), findsNothing);
      final fullLabelWidth = tester
          .getSize(find.byKey(_labelKey('My Tabs')))
          .width;
      expect(fullLabelWidth, greaterThan(labelMidWidth));
      for (final width in homeItemWidths) {
        expect(width, greaterThanOrEqualTo(48));
      }

      final dock = find.byKey(_dockKey);
      final expandedDockWidth = tester.getRect(dock).width;
      await tester.dragFrom(const Offset(200, 260), const Offset(0, -160));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      final midDockWidth = tester.getRect(dock).width;
      expect(midDockWidth, greaterThan(64));
      expect(midDockWidth, lessThan(expandedDockWidth));
      await tester.pumpAndSettle();
      expect(tester.getRect(dock).width, closeTo(64, 0.1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scroll collapse keeps only the left-aligned current icon; tap and upward swipe expand',
    (tester) async {
      const size = Size(320, 420);
      const safeInsets = EdgeInsets.fromLTRB(24, 0, 32, 0);
      await _setSurface(tester, size);
      final router = _router(initial: '/tabs');
      addTearDown(router.dispose);
      await tester.pumpWidget(
        _host(
          Router.withConfig(config: router),
          animate: true,
          safeInsets: safeInsets,
        ),
      );
      await tester.pumpAndSettle();

      final dockFinder = find.byKey(_dockKey);
      final addFinder = find.byKey(const ValueKey('navigation-create-tab'));
      final expandedDock = tester.getRect(dockFinder);
      final expandedWidth = expandedDock.width;
      final addRight = tester.getRect(addFinder).right;
      expect(expandedDock.left, closeTo(safeInsets.left, 0.1));
      expect(addRight, closeTo(size.width - safeInsets.right, 0.1));
      expect(
        tester.getRect(addFinder).left - expandedDock.right,
        closeTo(8, 0.1),
      );
      expect(expandedWidth, greaterThan(180));
      expect(find.byKey(_searchKey), findsNothing);
      expect(
        find.descendant(
          of: dockFinder,
          matching: find.byIcon(Icons.search_rounded),
        ),
        findsNothing,
      );

      await tester.dragFrom(const Offset(160, 260), const Offset(0, -160));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 12));
      final collapsingDock = tester.getRect(dockFinder);
      final collapsingActive = tester.getRect(find.byKey(_tabKey('My Tabs')));
      expect(collapsingDock.width, greaterThan(64));
      expect(collapsingDock.width, lessThan(expandedWidth));
      expect(collapsingDock.left, closeTo(expandedDock.left, 0.1));
      expect(
        collapsingActive.center.dx,
        closeTo(collapsingDock.left + 32, 0.1),
      );
      expect(tester.getRect(addFinder).right, closeTo(addRight, 0.1));
      expect(
        find.descendant(of: dockFinder, matching: find.byType(Icon)),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      final compactDock = tester.getRect(dockFinder);
      expect(tester.widget<Material>(dockFinder).color, Colors.transparent);
      final active = find.byKey(_tabKey('My Tabs'));
      final activeRect = tester.getRect(active);
      expect(compactDock.width, lessThan(expandedWidth - 40));
      expect(compactDock.left, closeTo(expandedDock.left, 0.1));
      expect(activeRect.center.dx, closeTo(compactDock.left + 32, 0.1));
      expect(active.hitTestable(), findsOneWidget);
      expect(activeRect.width, greaterThanOrEqualTo(48));
      expect(activeRect.height, greaterThanOrEqualTo(48));
      expect(find.byKey(_tabKey('Home')).hitTestable(), findsNothing);
      expect(find.byKey(_tabKey('Profile')).hitTestable(), findsNothing);
      expect(_dockLabel('My Tabs'), findsNothing);
      expect(
        find.descendant(
          of: dockFinder,
          matching: find.byIcon(Icons.search_rounded),
        ),
        findsNothing,
      );
      expect(find.byKey(_searchKey), findsNothing);
      expect(
        find.descendant(of: dockFinder, matching: find.byType(Icon)),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.receipt_long_rounded), findsOneWidget);
      expect(find.byTooltip('Show tabs'), findsOneWidget);
      expect(addFinder.hitTestable(), findsOneWidget);
      expect(tester.getRect(addFinder).right, closeTo(addRight, 0.1));
      expect(
        tester.getRect(addFinder).center.dy,
        closeTo(compactDock.center.dy, 0.1),
      );

      await tester.tap(active);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 12));
      final expandingDock = tester.getRect(dockFinder);
      final expandingActive = tester.getRect(active);
      expect(expandingDock.width, greaterThan(compactDock.width));
      expect(expandingDock.width, lessThan(expandedWidth));
      expect(expandingDock.left, closeTo(compactDock.left, 0.1));
      expect(expandingActive.center.dx, closeTo(activeRect.center.dx, 0.1));
      expect(tester.getRect(addFinder).right, closeTo(addRight, 0.1));
      expect(
        find.descendant(of: dockFinder, matching: find.byType(Icon)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      final restoredDock = tester.getRect(dockFinder);
      expect(restoredDock.width, closeTo(expandedWidth, 0.1));
      expect(restoredDock.left, closeTo(expandedDock.left, 0.1));
      expect(tester.getRect(addFinder).right, closeTo(addRight, 0.1));
      expect(
        tester.getRect(addFinder).left - restoredDock.right,
        closeTo(8, 0.1),
      );
      expect(_dockLabel('My Tabs'), findsOneWidget);

      await tester.dragFrom(const Offset(160, 260), const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(find.byKey(_tabKey('My Tabs')).hitTestable(), findsOneWidget);
      await tester.dragFrom(const Offset(160, 170), const Offset(0, 150));
      await tester.pumpAndSettle();
      expect(tester.getRect(dockFinder).width, closeTo(expandedWidth, 0.1));
      expect(_dockLabel('My Tabs'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('My Tabs filter and controller survive a branch round trip', (
    tester,
  ) async {
    await _setSurface(tester, const Size(400, 800));
    final router = _router(initial: '/tabs', isolatePages: false);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      _host(Router.withConfig(config: router), animate: false),
    );
    await tester.pumpAndSettle();

    final field = find.byType(TextField).first;
    expect(find.text('Alex'), findsOneWidget);
    await tester.enterText(field, 'no matching friend');
    await tester.pumpAndSettle();
    expect(find.text('Alex'), findsNothing);
    expect(find.text('No Active Tabs'), findsOneWidget);
    expect(find.byKey(_searchKey), findsNothing);

    await tester.tap(find.byKey(_tabKey('Home')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_tabKey('My Tabs')));
    await tester.pumpAndSettle();
    final restoredField = find.byType(TextField).first;
    expect(
      tester.widget<TextField>(restoredField).controller!.text,
      'no matching friend',
    );
    expect(find.text('Alex'), findsNothing);

    await tester.enterText(restoredField, 'alex');
    await tester.pumpAndSettle();
    expect(find.text('Alex'), findsOneWidget);
    expect(find.byKey(_tabKey('My Tabs')).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Add stays on Home and My Tabs and is hidden on Profile and details',
    (tester) async {
      await _setSurface(tester, const Size(400, 800));
      final router = _router(initial: '/tabs');
      addTearDown(router.dispose);
      await tester.pumpWidget(
        _host(Router.withConfig(config: router), animate: false),
      );
      await tester.pumpAndSettle();
      const addKey = ValueKey('navigation-create-tab');
      expect(find.byKey(addKey), findsOneWidget);

      router.go('/tabs/warm-tab');
      await tester.pumpAndSettle();
      expect(find.text('Tab detail warm-tab'), findsOneWidget);
      expect(find.byKey(addKey), findsNothing);

      router.go('/profile');
      await tester.pumpAndSettle();
      expect(find.byKey(addKey), findsNothing);
      router.go('/home');
      await tester.pumpAndSettle();
      expect(find.byKey(addKey), findsOneWidget);
      router.go('/tabs');
      await tester.pumpAndSettle();
      expect(find.byKey(addKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion applies selection and collapse immediately', (
    tester,
  ) async {
    await _setSurface(tester, const Size(400, 420));
    final router = _router(initial: '/tabs');
    addTearDown(router.dispose);
    await tester.pumpWidget(
      _host(Router.withConfig(config: router), animate: false),
    );
    await tester.pumpAndSettle();

    final dockFinder = find.byKey(_dockKey);
    final expandedWidth = tester.getRect(dockFinder).width;
    await tester.dragFrom(const Offset(200, 260), const Offset(0, -160));
    await tester.pump();
    expect(tester.getRect(dockFinder).width, closeTo(64, 0.1));
    expect(_dockLabel('My Tabs'), findsNothing);
    expect(find.byKey(_tabKey('My Tabs')).hitTestable(), findsOneWidget);

    await tester.tap(find.byKey(_tabKey('My Tabs')));
    await tester.pump();
    expect(tester.getRect(dockFinder).width, closeTo(expandedWidth, 0.1));
    expect(_dockLabel('My Tabs'), findsOneWidget);

    await tester.tap(find.byKey(_tabKey('Profile')));
    await tester.pump();
    expect(_dockLabel('Profile'), findsOneWidget);
    expect(_dockLabel('My Tabs'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
