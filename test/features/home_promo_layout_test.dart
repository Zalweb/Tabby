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
      final dock = tester.getRect(
        find.byKey(const ValueKey('tabby-navigation-dock')),
      );
      final addRect = tester.getRect(createTabButton);
      expect(dock.left, closeTo(16, 1));
      expect(addRect.right, closeTo(540 - 16, 1));
      expect(addRect.left, closeTo(dock.right + 8, 1));
      expect(addRect.center.dy, closeTo(dock.center.dy, 1));
      await tester.tap(find.byKey(const ValueKey('navigation-tab-profile')));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing);
      await tester.tap(find.byKey(const ValueKey('navigation-tab-my-tabs')));
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
