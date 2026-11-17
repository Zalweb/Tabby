import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabby/core/config/app_state.dart';
import 'package:tabby/core/router/app_router.dart';
import 'package:tabby/main.dart';
import 'package:tabby/shared/widgets/tabby_mascot_widget.dart';

void main() {
  testWidgets(
    'Home shows the debt summary and opens the real creation flow from navigation',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      AppState.isAuthenticated.value = true;
      AppState.hasSeenOnboarding.value = true;
      appRouter.go('/home');

      await tester.pumpWidget(
        const ProviderScope(child: TabbyApp(enableUpdateCheck: false)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TabbyMascotWidget), findsOneWidget);
      final mascot = tester.widget<TabbyMascotWidget>(
        find.byType(TabbyMascotWidget),
      );
      expect(mascot.pose, TabbyMascotPose.notebook);
      expect(
        mascot.showBubble || mascot.showBackdrop || mascot.showStatusBadge,
        isFalse,
      );
      expect(find.text('Split with friends,\nmade easy.'), findsNothing);
      expect(find.text('NET BALANCE'), findsOneWidget);
      expect(find.text('Your tabs'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('navigation-create-tab')),
        findsOneWidget,
      );
      expect(find.text('Log Expense'), findsNothing);
      expect(find.byType(FloatingActionButton), findsOneWidget);

      final createTabButton = find.byKey(
        const ValueKey('navigation-create-tab'),
      );
      final homeX = tester.getCenter(find.text('Home')).dx;
      final tabsX = tester.getCenter(find.text('My Tabs')).dx;
      final profileX = tester.getCenter(find.text('Profile')).dx;
      expect(tabsX - homeX, closeTo(profileX - tabsX, 1));
      expect(tabsX, closeTo(270, 1));
      expect(tester.getCenter(createTabButton).dx, greaterThan(460));
      expect(
        tester.getBottomRight(createTabButton).dy,
        lessThan(tester.getTopLeft(find.text('Profile')).dy),
      );
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing);
      await tester.tap(find.text('My Tabs'));
      await tester.pumpAndSettle();
      expect(createTabButton.hitTestable(), findsOneWidget);
      await tester.ensureVisible(createTabButton);
      await tester.tap(createTabButton);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('create-tab-add-people')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      AppState.isAuthenticated.value = false;
    },
  );
}
