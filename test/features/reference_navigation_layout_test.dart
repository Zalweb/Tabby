import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tabby/core/theme/tabby_theme.dart';
import 'package:tabby/features/navigation/presentation/main_scaffold.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/presentation/my_tabs_screen.dart';

import '../support/warm_design_fixture.dart';

const _dockKey = ValueKey('tabby-navigation-dock');
const _searchKey = ValueKey('navigation-search-tabs');

ValueKey<String> _tabKey(String name) =>
    ValueKey('navigation-tab-${name.toLowerCase().replaceAll(' ', '-')}');

ValueKey<String> _labelKey(String name) =>
    ValueKey('navigation-label-${name.toLowerCase().replaceAll(' ', '-')}');

// The old page layouts on this review base have different scroll extents.
const _fixtureHome = ValueKey('dock-fixture-home');
const _fixtureTabs = ValueKey('dock-fixture-tabs');

Widget _scrollablePage({Key? key}) => Scaffold(
  key: key,
  body: ListView(children: const [SizedBox(height: 1200)]),
);

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
                  builder: (_, _) => _scrollablePage(key: _fixtureHome),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/tabs',
                  builder: (_, _) => isolatePages
                      ? _scrollablePage(key: _fixtureTabs)
                      : const MyTabsScreen(),
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
                GoRoute(path: '/profile', builder: (_, _) => _scrollablePage()),
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

void _dispatchScrollUpdate(
  WidgetTester tester,
  Finder source, {
  ScrollDirection? direction,
  required double delta,
  double pixels = 100,
  int depth = 0,
  AxisDirection axisDirection = AxisDirection.down,
}) {
  final context = tester.element(source);
  final metrics = FixedScrollMetrics(
    minScrollExtent: 0,
    maxScrollExtent: 500,
    pixels: pixels,
    viewportDimension: 400,
    axisDirection: axisDirection,
    devicePixelRatio: tester.view.devicePixelRatio,
  );
  if (direction != null) {
    UserScrollNotification(
      metrics: metrics,
      context: context,
      direction: direction,
    ).dispatch(context);
  }
  ScrollUpdateNotification(
    metrics: metrics,
    context: context,
    scrollDelta: delta,
    depth: depth,
  ).dispatch(context);
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
          final bodyFinder = find.byKey(
            const ValueKey('tabby-navigation-body'),
          );
          final body = tester.getRect(bodyFinder);
          final scrollableFinder = find
              .descendant(
                of: find.byKey(_fixtureHome),
                matching: find.byType(Scrollable),
              )
              .first;
          final scrollable = tester.getRect(scrollableFinder);
          final dock = tester.getRect(dockFinder);
          final dockMaterial = tester.widget<Material>(dockFinder);
          expect(body, Offset.zero & size);
          expect(scrollable.top, closeTo(body.top, 0.1));
          expect(scrollable.height, closeTo(body.height, 0.1));
          expect(dockMaterial.color, Colors.transparent);
          expect(dockMaterial.shape, isNull);
          expect(dockMaterial.elevation, 0);
          final add = tester.getRect(addFinder);
          expect(addFinder, findsOneWidget);
          expect(find.byType(FloatingActionButton), findsOneWidget);
          expect(find.byType(BottomNavigationBar), findsNothing);
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
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dock slides out at 12 downward pixels and restores on the first upward delta',
    (tester) async {
      const size = Size(400, 420);
      const safeInsets = EdgeInsets.fromLTRB(24, 0, 32, 20);
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

      final dock = find.byKey(_dockKey);
      final add = find.byKey(const ValueKey('navigation-create-tab'));
      final source = find.byKey(_fixtureTabs);
      final expandedRect = tester.getRect(dock);
      final expandedWidth = expandedRect.width;
      final addRect = tester.getRect(add);

      _dispatchScrollUpdate(
        tester,
        source,
        direction: ScrollDirection.reverse,
        delta: 6,
      );
      _dispatchScrollUpdate(
        tester,
        source,
        direction: ScrollDirection.reverse,
        delta: 5,
      );
      await tester.pump();
      expect(tester.getRect(dock).top, closeTo(expandedRect.top, 0.1));
      expect(dock.hitTestable(), findsOneWidget);

      _dispatchScrollUpdate(
        tester,
        source,
        direction: ScrollDirection.reverse,
        delta: 1,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      final slidingRect = tester.getRect(dock);
      expect(slidingRect.top, greaterThan(expandedRect.top));
      expect(slidingRect.top, lessThan(size.height));
      expect(slidingRect.width, closeTo(expandedWidth, 0.1));
      expect(tester.getRect(add), addRect);
      expect(add.hitTestable(), findsOneWidget);
      expect(dock.hitTestable(), findsNothing);
      expect(
        find.descendant(of: dock, matching: find.byType(Icon)),
        findsNWidgets(3),
      );
      expect(
        find.descendant(of: dock, matching: find.byIcon(Icons.search_rounded)),
        findsNothing,
      );
      expect(find.byTooltip('Show tabs'), findsNothing);
      expect(
        find
            .ancestor(of: dock, matching: find.byType(ExcludeSemantics))
            .evaluate()
            .map((element) => (element.widget as ExcludeSemantics).excluding)
            .any((excluded) => excluded),
        isTrue,
      );
      expect(
        find
            .ancestor(of: dock, matching: find.byType(IgnorePointer))
            .evaluate()
            .map((element) => (element.widget as IgnorePointer).ignoring)
            .any((ignored) => ignored),
        isTrue,
      );
      expect(
        find
            .ancestor(of: dock, matching: find.byType(ExcludeFocus))
            .evaluate()
            .map((element) => (element.widget as ExcludeFocus).excluding)
            .any((excluded) => excluded),
        isTrue,
      );

      await tester.pumpAndSettle();
      final hiddenRect = tester.getRect(dock);
      expect(hiddenRect.top, greaterThanOrEqualTo(size.height));
      expect(hiddenRect.width, closeTo(expandedWidth, 0.1));
      expect(tester.getRect(add), addRect);
      expect(add.hitTestable(), findsOneWidget);
      for (final label in ['Home', 'My Tabs', 'Profile']) {
        expect(find.byKey(_tabKey(label)).hitTestable(), findsNothing);
      }

      _dispatchScrollUpdate(
        tester,
        source,
        direction: ScrollDirection.forward,
        delta: -0.5,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      final restoringRect = tester.getRect(dock);
      expect(restoringRect.top, lessThan(hiddenRect.top));
      expect(restoringRect.width, closeTo(expandedWidth, 0.1));
      expect(
        find
            .ancestor(of: dock, matching: find.byType(ExcludeSemantics))
            .evaluate()
            .map((element) => (element.widget as ExcludeSemantics).excluding)
            .any((excluded) => excluded),
        isFalse,
      );
      expect(
        find
            .ancestor(of: dock, matching: find.byType(ExcludeFocus))
            .evaluate()
            .map((element) => (element.widget as ExcludeFocus).excluding)
            .any((excluded) => excluded),
        isFalse,
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(dock).top, closeTo(expandedRect.top, 0.1));
      expect(tester.getRect(add), addRect);

      final scrollable = find
          .descendant(
            of: find.byKey(_fixtureTabs),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.drag(scrollable, const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(tester.getRect(dock).top, greaterThanOrEqualTo(size.height));
      expect(add.hitTestable(), findsOneWidget);
      await tester.drag(scrollable, const Offset(0, 80));
      await tester.pumpAndSettle();
      expect(tester.getRect(dock).top, closeTo(expandedRect.top, 0.1));

      _dispatchScrollUpdate(
        tester,
        find.byKey(_fixtureTabs),
        direction: ScrollDirection.reverse,
        delta: 12,
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(dock).top, greaterThanOrEqualTo(size.height));
      router.go('/home');
      await tester.pumpAndSettle();
      expect(tester.getRect(dock).top, closeTo(expandedRect.top, 0.1));
      expect(
        find.byKey(const ValueKey('navigation-create-tab')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'programmatic, nested, overscroll and offstage notifications do not hide the dock',
    (tester) async {
      await _setSurface(tester, const Size(400, 800));
      final router = _router();
      addTearDown(router.dispose);
      await tester.pumpWidget(
        _host(Router.withConfig(config: router), animate: false),
      );
      await tester.pumpAndSettle();

      router.go('/tabs');
      await tester.pumpAndSettle();
      final source = find.byKey(_fixtureTabs);
      final dock = find.byKey(_dockKey);
      final expandedTop = tester.getRect(dock).top;

      _dispatchScrollUpdate(tester, source, delta: 12);
      _dispatchScrollUpdate(
        tester,
        source,
        direction: ScrollDirection.reverse,
        delta: 12,
        axisDirection: AxisDirection.right,
      );
      _dispatchScrollUpdate(
        tester,
        source,
        direction: ScrollDirection.reverse,
        delta: 12,
        depth: 1,
      );
      _dispatchScrollUpdate(
        tester,
        source,
        direction: ScrollDirection.reverse,
        delta: 12,
        pixels: 501,
      );
      _dispatchScrollUpdate(
        tester,
        find.byKey(_fixtureHome, skipOffstage: false),
        direction: ScrollDirection.reverse,
        delta: 12,
      );
      await tester.pump();
      expect(tester.getRect(dock).top, closeTo(expandedTop, 0.1));
      expect(dock.hitTestable(), findsOneWidget);

      _dispatchScrollUpdate(
        tester,
        source,
        direction: ScrollDirection.reverse,
        delta: 12,
      );
      await tester.pump();
      expect(tester.getRect(dock).top, greaterThan(expandedTop));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'keyboard hides the overlay while reduced motion skips the slide',
    (tester) async {
      const size = Size(400, 800);
      await _setSurface(tester, size);
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetViewInsets);
      final router = _router(initial: '/tabs');
      addTearDown(router.dispose);
      await tester.pumpWidget(
        _host(Router.withConfig(config: router), animate: false),
      );
      await tester.pumpAndSettle();

      final dock = find.byKey(_dockKey);
      final add = find.byKey(const ValueKey('navigation-create-tab'));
      expect(dock, findsNothing);
      expect(add, findsNothing);

      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(dock.hitTestable(), findsOneWidget);
      expect(add.hitTestable(), findsOneWidget);

      _dispatchScrollUpdate(
        tester,
        find.byKey(_fixtureTabs),
        direction: ScrollDirection.reverse,
        delta: 12,
      );
      await tester.pump();
      expect(tester.getRect(dock).top, greaterThanOrEqualTo(size.height));
      expect(add.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'tab controls yield to a branch bottom sheet and return on close',
    (tester) async {
      await _setSurface(tester, const Size(400, 800));
      final router = _router(initial: '/tabs');
      addTearDown(router.dispose);
      await tester.pumpWidget(
        _host(Router.withConfig(config: router), animate: false),
      );
      await tester.pumpAndSettle();

      final dock = find.byKey(_dockKey);
      final add = find.byKey(const ValueKey('navigation-create-tab'));
      expect(dock.hitTestable(), findsOneWidget);
      expect(add.hitTestable(), findsOneWidget);

      final page = tester.element(find.byKey(_fixtureTabs));
      unawaited(
        showModalBottomSheet<void>(
          context: page,
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close branch sheet'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(dock, findsNothing);
      expect(add, findsNothing);
      final close = find.text('Close branch sheet');
      expect(close.hitTestable(), findsOneWidget);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(dock.hitTestable(), findsOneWidget);
      expect(add.hitTestable(), findsOneWidget);
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

  testWidgets('reduced motion skips the dock slide and selection animations', (
    tester,
  ) async {
    const size = Size(400, 420);
    await _setSurface(tester, size);
    final router = _router(initial: '/tabs');
    addTearDown(router.dispose);
    await tester.pumpWidget(
      _host(Router.withConfig(config: router), animate: false),
    );
    await tester.pumpAndSettle();

    final dockFinder = find.byKey(_dockKey);
    final expandedRect = tester.getRect(dockFinder);
    _dispatchScrollUpdate(
      tester,
      find.byKey(_fixtureTabs),
      direction: ScrollDirection.reverse,
      delta: 12,
    );
    await tester.pump();
    final hiddenRect = tester.getRect(dockFinder);
    expect(hiddenRect.top, greaterThanOrEqualTo(size.height));
    expect(hiddenRect.width, closeTo(expandedRect.width, 0.1));
    expect(_dockLabel('My Tabs'), findsOneWidget);
    expect(find.byKey(_tabKey('My Tabs')).hitTestable(), findsNothing);
    expect(
      find.byKey(const ValueKey('navigation-create-tab')).hitTestable(),
      findsOneWidget,
    );

    router.go('/home');
    await tester.pump();
    expect(tester.getRect(dockFinder).top, closeTo(expandedRect.top, 0.1));
    expect(_dockLabel('Home'), findsOneWidget);
    expect(_dockLabel('My Tabs'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
