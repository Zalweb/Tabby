import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabby/core/config/app_state.dart';
import 'package:tabby/core/router/app_router.dart';
import 'package:tabby/main.dart';
import 'package:tabby/shared/widgets/tabby_mascot_widget.dart';

void main() {
  testWidgets(
    'Home replaces the mascot message and floating action with the split promo card',
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
        const ProviderScope(
          child: TabbyApp(enableUpdateCheck: false),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TabbyMascotWidget), findsNothing);
      expect(find.text('Split with friends,\nmade easy.'), findsOneWidget);
      expect(find.text('Create a Tab'), findsOneWidget);
      expect(find.text('Log Expense'), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);

      final createTabButton = find.text('Create a Tab');
      await tester.ensureVisible(createTabButton);
      await tester.tap(createTabButton);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('create-tab-add-people')),
        findsOneWidget,
      );
    },
  );
}
