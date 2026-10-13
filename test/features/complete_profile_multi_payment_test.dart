import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabby/core/config/app_state.dart';
import 'package:tabby/core/router/app_router.dart';
import 'package:tabby/main.dart';

void main() {
  setUp(() {
    AppState.isAuthenticated.value = true;
    AppState.hasSeenOnboarding.value = true;
    AppState.profileCompletionRequired.value = true;
  });

  testWidgets(
      'Complete profile wizard transitions to Step 2 and allows multiple payment methods',
      (tester) async {
    appRouter.go('/complete-profile');

    await tester.pumpWidget(
      const ProviderScope(
        child: TabbyApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Step 1: Social Identity
    expect(find.text('Complete your profile'), findsOneWidget);
    expect(find.text('Step 1 of 2: Social Identity'), findsOneWidget);
    expect(find.text('CHOOSE PROFILE ICON'), findsOneWidget);

    // Enter full name and valid Philippine mobile number
    await tester.enterText(
      find.widgetWithText(TextField, 'Full name'),
      'Maria Santos',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Mobile number'),
      '09181234567',
    );

    // Tap "Save and continue"
    final continueButton = find.text('Save and continue');
    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);
    await tester.pumpAndSettle();

    // Step 2: Payment Rails
    expect(find.text('How friends pay you'), findsOneWidget);
    expect(find.text('Step 2 of 2: Payment Rails'), findsOneWidget);
    expect(find.text('Add your payment methods. When someone settles a tab, Tabby will show your details or auto-cropped QR instantly.'), findsOneWidget);

    // Initial default GCash method is present
    expect(find.text('GCash'), findsWidgets);
    expect(find.text('09181234567'), findsOneWidget);
    expect(find.text('Preferred'), findsOneWidget);

    // Tap "+ Add Another Payment Method"
    final addMethodButton = find.text('+ Add Another Payment Method');
    await tester.ensureVisible(addMethodButton);
    await tester.tap(addMethodButton);
    await tester.pumpAndSettle();

    // The add payment method sheet opens
    expect(find.text('Add Payment Method'), findsWidgets);
    expect(find.text('Maya'), findsOneWidget);
    expect(find.text('Bank Transfer'), findsOneWidget);

    // Select Maya provider chip
    await tester.tap(find.text('Maya'));
    await tester.pumpAndSettle();

    // Enter Maya account details
    final accountInput = find.widgetWithText(TextField, 'Account number or mobile');
    expect(accountInput, findsOneWidget);
    await tester.enterText(accountInput, '09998887766');

    // Tap "Add Payment Method" inside sheet
    final saveMethodButton = find.widgetWithText(InkWell, 'Add Payment Method').last;
    await tester.ensureVisible(saveMethodButton);
    await tester.tap(saveMethodButton);
    await tester.pumpAndSettle();

    // Verify both GCash and Maya are now visible in the list
    expect(find.text('GCash'), findsWidgets);
    expect(find.text('Maya'), findsWidgets);
    expect(find.text('09998887766'), findsOneWidget);

    // Verify "Complete Setup and Start" and "Skip for now" are available
    expect(find.text('Complete Setup and Start'), findsOneWidget);
    expect(find.text('Skip for now'), findsOneWidget);

    // Tap "Complete Setup and Start"
    final finishButton = find.text('Complete Setup and Start');
    await tester.ensureVisible(finishButton);
    await tester.tap(finishButton);
    await tester.pumpAndSettle();
  });
}
