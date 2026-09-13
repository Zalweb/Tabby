import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabby/main.dart';
import 'package:tabby/core/router/app_router.dart';
import 'package:tabby/core/theme/tabby_theme.dart';
import 'package:tabby/features/tabs/presentation/add_expense_modal.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:tabby/shared/widgets/currency_card.dart';
import 'package:tabby/shared/widgets/tabby_mascot_widget.dart';
import 'package:tabby/core/config/app_state.dart';

void main() {
  group('Web & Responsive Viewport Rendering', () {
    testWidgets('TabbyApp renders flawlessly on mobile viewport (390x844) without any white screen or overflow', (tester) async {
      AppState.isAuthenticated.value = true;
      appRouter.go('/home');
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: TabbyApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Home Dashboard loaded without emojis
      expect(find.text('Frienzal'), findsOneWidget);
      expect(find.text('YOU OWE'), findsOneWidget);
      expect(find.text("YOU'RE OWED"), findsOneWidget);
      expect(find.text('Upcoming & Reminders'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Recent Activity'), 300);
      expect(find.text('Recent Activity'), findsOneWidget);
      expect(find.text('Log Expense'), findsOneWidget);

      // Navigate to My Tabs
      await tester.tap(find.text('My Tabs'));
      await tester.pumpAndSettle();
      expect(find.text('My Tabs'), findsNWidgets(2));
      expect(find.text('No Active Tabs'), findsOneWidget);

      // Navigate to Profile
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('Profile & Settings'), findsOneWidget);
      expect(find.text('My Payment QR Ph'), findsOneWidget);

      // Reset route
      appRouter.go('/home');
      await tester.pumpAndSettle();
    });

    testWidgets('TabbyApp renders flawlessly on desktop browser viewport (1200x800) inside IPhoneDeviceFrameWrapper', (tester) async {
      AppState.isAuthenticated.value = true;
      appRouter.go('/home');
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Pump MaterialApp.router with IPhoneDeviceFrameWrapper simulating desktop web
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            title: 'Tabby',
            theme: TabbyTheme.lightTheme,
            routerConfig: appRouter,
            builder: (context, child) {
              return IPhoneDeviceFrameWrapper(child: child!);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify frame elements and content
      expect(find.byType(IPhoneDeviceFrameWrapper), findsOneWidget);
      expect(find.byType(DynamicIslandWidget), findsOneWidget);
      expect(find.byType(IPhoneHomeIndicator), findsOneWidget);
      expect(find.text('Frienzal'), findsOneWidget);
      expect(find.text('YOU OWE'), findsOneWidget);
      expect(find.text("YOU'RE OWED"), findsOneWidget);

      // Interactivity within desktop frame: tap My Tabs
      await tester.tap(find.text('My Tabs'));
      await tester.pumpAndSettle();
      expect(find.text('My Tabs'), findsNWidgets(2));

      // Tap Profile
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('Profile & Settings'), findsOneWidget);

      // Reset route
      appRouter.go('/home');
      await tester.pumpAndSettle();
    });

    testWidgets('TabbyApp renders on compact mobile viewport (360x640)', (tester) async {
      AppState.isAuthenticated.value = true;
      appRouter.go('/home');
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: TabbyApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Frienzal'), findsOneWidget);
    });
  });

  group('Standalone Widget Architectural Integrity', () {
    testWidgets('CurrencyCard builds standalone without ParentDataWidget crash', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CurrencyCard(
              title: 'YOU OWE',
              centavos: 125050,
              subtitle: 'Active tabs to settle',
              isDebt: true,
              icon: Icons.arrow_outward_rounded,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('YOU OWE'), findsOneWidget);
      expect(find.textContaining('1,250.50'), findsOneWidget);
      expect(find.text('To Pay'), findsOneWidget);
    });

    testWidgets('CurrencyCard handles zero balance and positive balance correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Expanded(
                  child: CurrencyCard(
                    title: "YOU'RE OWED",
                    centavos: 0,
                    subtitle: 'Zero pending credits',
                    isDebt: false,
                    icon: Icons.arrow_downward_rounded,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("YOU'RE OWED"), findsOneWidget);
      expect(find.text('Settled'), findsOneWidget);
    });

    testWidgets('TabbyMascotWidget renders all 9 emotions without errors', (tester) async {
      for (final emotion in MascotEmotion.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TabbyMascotWidget(
                emotion: emotion,
                customMessage: 'Custom emotion message for ${emotion.name}',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Tabby'), findsOneWidget);
        expect(find.text('Custom emotion message for ${emotion.name}'), findsOneWidget);
      }
    });

    testWidgets('AddExpenseModal opens and renders cleanly', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => AddExpenseModal.show(context),
                    child: const Text('Open Modal'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Quick Log Expense'), findsOneWidget);
      expect(find.text('Save Tab'), findsOneWidget);
    });
  });
}
