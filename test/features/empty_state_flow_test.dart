import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabby/main.dart';
import 'package:tabby/core/config/app_state.dart';
import 'package:tabby/core/router/app_router.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/shared/widgets/tabby_button.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets(
      'End-to-End flow: zero sample data, log new expense with custom friend, verify tab and balance',
      (tester) async {
    AppState.isAuthenticated.value = true;
    AppState.hasSeenOnboarding.value = true;
    appRouter.go('/home');

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final notifier = TabbyNotifier(loadInitialData: false);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [tabbyProvider.overrideWith((_) => notifier)],
        child: const TabbyApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Verify Home empty state
    expect(find.text('Total Balance'), findsOneWidget);
    expect(find.text('No pending dues. All caught up!'), findsOneWidget);
    expect(find.text('No recent activity yet. Log an expense to get started!'),
        findsOneWidget);

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
    final createTabButton = find.widgetWithText(ElevatedButton, 'Create a Tab');
    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();
    await tester.tap(createTabButton);
    await tester.pumpAndSettle();

    expect(find.text('Create Tab'), findsOneWidget);
    expect(find.text('Add People'), findsNWidgets(2));

    // Enter friend name 'Alex'
    await tester.enterText(
      find.byKey(const ValueKey('create-tab-unregistered-name')),
      'Alex',
    );
    await tester.tap(find.text('Add Person'));
    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    // Enter amount '500.00'
    await tester.enterText(
      find.byKey(const ValueKey('create-tab-amount')),
      '500.00',
    );
    await tester.pumpAndSettle();

    // Create Tab
    final createAction = find.widgetWithText(TabbyButton, 'Create Tab');
    await tester.ensureVisible(createAction);
    await tester.pumpAndSettle();
    await tester.tap(createAction);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TabbyButton, 'Done'));
    await tester.pumpAndSettle();

    // 5. Verify Home dashboard updated with new tab
    expect(find.text('YOU OWE'), findsOneWidget);
    expect(find.text("YOU'RE OWED"), findsOneWidget);
    expect(find.textContaining('250.00'), findsWidgets);

    // 6. Navigate to My Tabs and verify Alex tab exists
    await tester.tap(find.text('My Tabs'));
    await tester.pumpAndSettle();
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);

    // 7. Navigate to Profile and verify an unregistered participant is not a Friend
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Alex'), findsNothing);
    expect(find.text('No friends added yet'), findsOneWidget);
  });
}
