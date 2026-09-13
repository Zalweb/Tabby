import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabby/main.dart';
import 'package:tabby/core/config/app_state.dart';
import 'package:tabby/core/router/app_router.dart';

void main() {
  testWidgets('End-to-End flow: zero sample data, log new expense with custom friend, verify tab and balance', (tester) async {
    AppState.isAuthenticated.value = true;
    AppState.hasSeenOnboarding.value = true;
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

    // 1. Verify Home empty state
    expect(find.text('Total Balance'), findsOneWidget);
    expect(find.text('No pending dues. All caught up!'), findsOneWidget);
    expect(find.text('No recent activity yet. Log an expense to get started!'), findsOneWidget);

    // 2. Verify My Tabs empty state
    await tester.tap(find.text('My Tabs'));
    await tester.pumpAndSettle();
    expect(find.text('No Active Tabs'), findsOneWidget);

    // 3. Verify Profile empty state
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('No friends added yet'), findsOneWidget);

    // 4. Open Add Expense Modal
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log Expense'));
    await tester.pumpAndSettle();

    expect(find.text('Quick Log Expense'), findsOneWidget);
    expect(find.text('Friend or Group Name'), findsOneWidget);

    // Enter friend name 'Alex'
    final textFields = find.byType(TextField);
    await tester.enterText(textFields.at(0), 'Alex');
    // Enter amount '500.00'
    await tester.enterText(textFields.at(1), '500.00');
    await tester.pumpAndSettle();

    // Save Tab
    await tester.ensureVisible(find.text('Save Tab'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Tab'));
    await tester.pumpAndSettle();

    // 5. Verify Home dashboard updated with new tab
    expect(find.text('YOU OWE'), findsOneWidget);
    expect(find.text("YOU'RE OWED"), findsOneWidget);
    expect(find.textContaining('250.00'), findsWidgets);

    // 6. Navigate to My Tabs and verify Alex tab exists
    await tester.tap(find.text('My Tabs'));
    await tester.pumpAndSettle();
    expect(find.text('Alex'), findsOneWidget);
    expect(find.textContaining('THEY OWE YOU'), findsOneWidget);

    // 7. Navigate to Profile and verify Alex is in Friends list
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('1 friend'), findsOneWidget);
  });
}
