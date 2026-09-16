import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabby/main.dart';
import 'package:tabby/core/config/app_state.dart';
import 'package:tabby/core/router/app_router.dart';
import 'package:tabby/features/tabs/presentation/add_expense_modal.dart';
import 'package:tabby/features/profile/presentation/profile_screen.dart';
import 'package:tabby/shared/widgets/notification_center_sheet.dart';
import 'package:tabby/shared/widgets/tabby_button.dart';
import 'package:tabby/shared/widgets/tabby_mascot_widget.dart';

void main() {
  setUp(() {
    AppState.isAuthenticated.value = true;
    AppState.hasSeenOnboarding.value = true;
  });

  group('E2E All Screens & Buttons Comprehensive Test Suite', () {
    testWidgets('Home Dashboard: Every button and interactive control works without failure', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      AppState.isAuthenticated.value = true;
      appRouter.go('/home');

      await tester.pumpWidget(
        const ProviderScope(
          child: TabbyApp(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Notification Center Bell Button
      final notifBtn = find.byIcon(Icons.notifications_none_rounded);
      expect(notifBtn, findsWidgets);
      await tester.tap(notifBtn.first);
      await tester.pumpAndSettle();

      expect(find.text('Notifications'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsNothing);

      // 2. Tabby Mascot Speech Bubble / Avatar Tap
      final mascotFinder = find.byType(TabbyMascotWidget).first;
      await tester.tap(mascotFinder);
      await tester.pumpAndSettle();

      // 3. Segmented Filter Buttons (Daily, Weekly, Monthly)
      final weeklyBtn = find.text('Weekly');
      await tester.ensureVisible(weeklyBtn);
      await tester.tap(weeklyBtn);
      await tester.pumpAndSettle();

      final dailyBtn = find.text('Daily');
      await tester.ensureVisible(dailyBtn);
      await tester.tap(dailyBtn);
      await tester.pumpAndSettle();

      final monthlyBtn = find.text('Monthly');
      await tester.ensureVisible(monthlyBtn);
      await tester.tap(monthlyBtn);
      await tester.pumpAndSettle();

      // 4. Currency Card "YOU OWE" navigation to /tabs
      final youOweCard = find.text('YOU OWE');
      await tester.ensureVisible(youOweCard);
      await tester.tap(youOweCard);
      await tester.pumpAndSettle();
      expect(find.text('My Tabs'), findsWidgets);

      // Return to Home
      appRouter.go('/home');
      await tester.pumpAndSettle();

      // 5. Currency Card "YOU'RE OWED" navigation to /tabs
      final youAreOwedCard = find.text("YOU'RE OWED");
      await tester.ensureVisible(youAreOwedCard);
      await tester.tap(youAreOwedCard);
      await tester.pumpAndSettle();
      expect(find.text('My Tabs'), findsWidgets);

      // Return to Home
      appRouter.go('/home');
      await tester.pumpAndSettle();

      // 6. FAB "Log Expense" button
      final fab = find.byType(FloatingActionButton);
      expect(fab, findsOneWidget);
      await tester.tap(fab);
      await tester.pumpAndSettle();
      expect(find.text('Quick Log Expense'), findsOneWidget);

      // Close modal
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
    });

    testWidgets('Add Expense Modal: Presets, Categories, Payer/Split toggles, Date picker, and Validations', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      AppState.isAuthenticated.value = true;
      appRouter.go('/home');

      await tester.pumpWidget(
        const ProviderScope(
          child: TabbyApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Open Add Expense modal
      final fab = find.byType(FloatingActionButton);
      await tester.tap(fab);
      await tester.pumpAndSettle();

      // 1. Validation: Clear name and tap Save Tab with empty fields
      final nameField = find.widgetWithText(TextField, 'Enter name (e.g. Alex, Maria, Weekend Group)');
      await tester.ensureVisible(nameField);
      await tester.enterText(nameField, '');
      await tester.pumpAndSettle();

      final saveBtn1 = find.text('Save Tab');
      await tester.ensureVisible(saveBtn1);
      await tester.tap(saveBtn1);
      await tester.pumpAndSettle();
      expect(find.text('Please enter a friend or group name'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(AddExpenseModal))).clearSnackBars();
      await tester.pumpAndSettle();

      // Enter Name
      await tester.enterText(nameField, 'Samantha Perez');
      await tester.pumpAndSettle();

      // 2. Validation: Tap Save Tab with 0.00 amount
      final saveBtn2 = find.text('Save Tab');
      await tester.ensureVisible(saveBtn2);
      await tester.tap(saveBtn2);
      await tester.pumpAndSettle();
      expect(find.text('Please enter an amount greater than PHP 0.00'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(AddExpenseModal))).clearSnackBars();
      await tester.pumpAndSettle();

      // Test Quick Amount Preset Chips (+₱500, +₱250)
      final preset500 = find.text('+₱500');
      await tester.ensureVisible(preset500);
      await tester.tap(preset500);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '500.00'), findsOneWidget);

      final preset250 = find.text('+₱250');
      await tester.ensureVisible(preset250);
      await tester.tap(preset250);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '750.00'), findsOneWidget);

      // 3. Category selection: Transportation, Groceries
      final transportChip = find.widgetWithText(ChoiceChip, 'Transportation');
      await tester.ensureVisible(transportChip);
      await tester.tap(transportChip);
      await tester.pumpAndSettle();

      final groceriesChip = find.widgetWithText(ChoiceChip, 'Groceries');
      await tester.ensureVisible(groceriesChip);
      await tester.tap(groceriesChip);
      await tester.pumpAndSettle();

      // 4. Description and Note inputs
      final descField = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.widgetWithText(TextField, 'Dinner, Grocery run, Taxi fare'),
      );
      await tester.ensureVisible(descField);
      await tester.enterText(descField, 'Supermarket run');
      await tester.pumpAndSettle();

      final noteField = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.widgetWithText(TextField, 'Enter Message or notes...'),
      );
      await tester.ensureVisible(noteField);
      await tester.enterText(noteField, 'Puregold supplies');
      await tester.pumpAndSettle();

      // 5. Payer toggle: "They paid" then back to "You paid"
      final theyPaidBtn = find.text('They paid');
      await tester.ensureVisible(theyPaidBtn);
      await tester.tap(theyPaidBtn);
      await tester.pumpAndSettle();

      final youPaidBtn = find.text('You paid');
      await tester.ensureVisible(youPaidBtn);
      await tester.tap(youPaidBtn);
      await tester.pumpAndSettle();

      // 6. Split mode toggle: "Full Share" then back to "50/50 Split"
      final fullShareBtn = find.text('Full Share');
      await tester.ensureVisible(fullShareBtn);
      await tester.tap(fullShareBtn);
      await tester.pumpAndSettle();

      final split5050Btn = find.text('50/50 Split');
      await tester.ensureVisible(split5050Btn);
      await tester.tap(split5050Btn);
      await tester.pumpAndSettle();

      // 7. Due Date picker
      final setDateBtn = find.text('Set Date');
      await tester.ensureVisible(setDateBtn);
      await tester.tap(setDateBtn);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Change'), findsOneWidget);

      // 8. Attach / Remove receipt
      final attachBtn = find.text('Attach');
      await tester.ensureVisible(attachBtn);
      await tester.tap(attachBtn);
      await tester.pumpAndSettle();
      expect(find.text('Receipt: Attached'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(AddExpenseModal))).clearSnackBars();
      await tester.pumpAndSettle();

      // 9. Save Tab successfully
      final saveBtn3 = find.text('Save Tab');
      await tester.ensureVisible(saveBtn3);
      await tester.tap(saveBtn3);
      await tester.pumpAndSettle();

      expect(find.textContaining('Logged ₱750.00 with Samantha Perez!'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('Tab Detail: Full Remind nudge, Payment settlement, and QR/Receipt interaction flows', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      AppState.isAuthenticated.value = true;
      appRouter.go('/home');

      await tester.pumpWidget(
        const ProviderScope(
          child: TabbyApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Create a tab with Mateo
      final fab = find.byType(FloatingActionButton);
      await tester.tap(fab);
      await tester.pumpAndSettle();

      final nameField = find.widgetWithText(TextField, 'Enter name (e.g. Alex, Maria, Weekend Group)');
      await tester.enterText(nameField, 'Mateo Cruz');
      await tester.pumpAndSettle();

      final amountField = find.widgetWithText(TextField, '0.00');
      await tester.enterText(amountField, '1000.00');
      await tester.pumpAndSettle();

      final descField = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.widgetWithText(TextField, 'Dinner, Grocery run, Taxi fare'),
      );
      await tester.enterText(descField, 'Samgyupsal Feast');
      await tester.pumpAndSettle();

      // Save tab (50/50 split -> Mateo owes ₱500.00)
      final saveBtn = find.text('Save Tab');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // Go to My Tabs
      appRouter.go('/tabs');
      await tester.pumpAndSettle();

      // Verify Mateo Cruz appears under THEY OWE YOU
      final mateoTile = find.text('Mateo Cruz');
      expect(mateoTile, findsOneWidget);
      await tester.tap(mateoTile);
      await tester.pumpAndSettle();

      // 1. In Tab Detail: Header Back Button
      final backBtn = find.byIcon(Icons.arrow_back);
      expect(backBtn, findsOneWidget);
      await tester.tap(backBtn);
      await tester.pumpAndSettle();
      expect(find.text('My Tabs'), findsWidgets);

      // Re-enter Mateo's tab
      await tester.tap(find.text('Mateo Cruz'));
      await tester.pumpAndSettle();

      // 2. Header QR / Payment Info button
      final qrBtn = find.byIcon(Icons.qr_code_2_rounded);
      expect(qrBtn, findsWidgets);
      await tester.tap(qrBtn.first);
      await tester.pumpAndSettle();

      expect(find.textContaining('Payment Info'), findsOneWidget);
      // Copy GCash number
      final gcashTile = find.text('GCash');
      await tester.tap(gcashTile);
      await tester.pumpAndSettle();
      expect(find.textContaining('copied to clipboard'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // Copy Maya number
      final mayaTile = find.text('Maya');
      await tester.tap(mayaTile);
      await tester.pumpAndSettle();
      expect(find.textContaining('copied to clipboard'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // Enlarge QR code modal
      await tester.tap(find.text('Tap to enlarge'));
      await tester.pumpAndSettle();
      expect(find.text('QR Ph Official'), findsOneWidget);

      // Copy QR string
      await tester.tap(find.text('Copy QR String'));
      await tester.pumpAndSettle();
      expect(find.text('QR Ph payload copied to clipboard!'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // Save QR Image button
      await tester.tap(find.text('Save QR Image'));
      await tester.pumpAndSettle();
      expect(find.text('QR code image saved to gallery!'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // Close QR enlargement sheet
      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // Close Payment Info sheet using the Close button
      await tester.tap(find.text('Close'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // 3. Header Receipts button
      final receiptBtn = find.byIcon(Icons.receipt_long_rounded);
      expect(receiptBtn, findsWidgets);
      await tester.tap(receiptBtn.first);
      await tester.pumpAndSettle();

      expect(find.text('Shared Media & Receipts'), findsOneWidget);
      // Attach to Latest Transaction button
      final attachLatestBtn = find.text('Attach to Latest Transaction');
      if (attachLatestBtn.evaluate().isNotEmpty) {
        await tester.tap(attachLatestBtn);
        await tester.pumpAndSettle();
        expect(find.textContaining('Receipt attached to'), findsOneWidget);
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      } else {
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();
      }

      // 4. Remind Button -> Friendly Reminder Nudge Modal
      final remindBtn = find.text('Remind Mateo Cruz');
      expect(remindBtn, findsOneWidget);
      await tester.tap(remindBtn);
      await tester.pumpAndSettle();

      expect(find.text('Send Friendly Reminder'), findsOneWidget);
      expect(find.text('Share Reminder Link'), findsOneWidget);
      await tester.tap(find.text('Share Reminder Link'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Reminder link copied to clipboard and sent to Mateo Cruz!'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // 5. Confirm Payment Button -> Settlement Modal
      final confirmPayBtn = find.text('Confirm Payment');
      expect(confirmPayBtn, findsOneWidget);
      await tester.tap(confirmPayBtn);
      await tester.pumpAndSettle();

      expect(find.text('Confirm Payment Received'), findsOneWidget);

      // Select Maya payment method chip
      await tester.tap(find.widgetWithText(ChoiceChip, 'Maya'));
      await tester.pumpAndSettle();

      // Confirm payment of ₱500.00
      await tester.tap(find.text('Confirm Payment').last);
      await tester.pumpAndSettle();

      expect(find.text('Settlement recorded successfully!'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // 6. Verify tab is now fully settled!
      expect(find.text('All settled up'), findsOneWidget);
      expect(find.text('₱0.00'), findsWidgets);
      expect(find.text('Log New Expense'), findsOneWidget);
    });

    testWidgets('My Tabs: Search bar filtering, clear query, and group tabs handling', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      AppState.isAuthenticated.value = true;
      appRouter.go('/tabs');

      await tester.pumpWidget(
        const ProviderScope(
          child: TabbyApp(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Header Add Tab button (+)
      final addTabHeaderBtn = find.byIcon(Icons.add_rounded).first;
      await tester.tap(addTabHeaderBtn);
      await tester.pumpAndSettle();
      expect(find.text('Quick Log Expense'), findsOneWidget);

      // Log a quick tab with "Jessica"
      final nameField = find.widgetWithText(TextField, 'Enter name (e.g. Alex, Maria, Weekend Group)');
      await tester.enterText(nameField, 'Jessica Tan');
      await tester.pumpAndSettle();

      final amountField = find.widgetWithText(TextField, '0.00');
      await tester.enterText(amountField, '300.00');
      await tester.pumpAndSettle();

      final saveBtn = find.text('Save Tab');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // Verify Jessica Tan exists in My Tabs
      expect(find.text('Jessica Tan'), findsOneWidget);

      // 2. Header Notification Bell
      final notifHeaderBtn = find.byIcon(Icons.notifications_none_rounded).first;
      await tester.tap(notifHeaderBtn);
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // 3. Search Bar: Enter non-existent query
      final searchField = find.byType(TextField).first;
      await tester.enterText(searchField, 'NonExistentName123');
      await tester.pumpAndSettle();

      // Jessica should be filtered out
      expect(find.text('Jessica Tan'), findsNothing);
      expect(find.text('No Active Tabs'), findsOneWidget);

      // Clear search query via clear icon
      final clearBtn = find.byIcon(Icons.clear);
      expect(clearBtn, findsOneWidget);
      await tester.tap(clearBtn);
      await tester.pumpAndSettle();

      // Jessica should reappear
      expect(find.text('Jessica Tan'), findsOneWidget);
      expect(find.text('No Active Tabs'), findsNothing);
    });

    testWidgets('Onboarding & Authentication: Complete button, validation, and navigation flows', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      AppState.isAuthenticated.value = false;
      AppState.hasSeenOnboarding.value = false;
      appRouter.go('/onboarding');

      await tester.pumpWidget(
        const ProviderScope(
          child: TabbyApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Onboarding Screen is active
      expect(find.text('Keep tabs on every shared expense'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);

      // Tap Skip button -> routes to /login
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(AppState.hasSeenOnboarding.value, isTrue);
      expect(find.text('Log In'), findsOneWidget);

      // 1. Login form validation: tap Log In with empty fields
      await tester.tap(find.widgetWithText(TabbyButton, 'Log In'));
      await tester.pumpAndSettle();
      expect(find.text('Please enter email and password'), findsOneWidget);

      // 2. Test password obscure toggle
      final obscureToggle = find.byIcon(Icons.visibility_off_outlined);
      expect(obscureToggle, findsOneWidget);
      await tester.tap(obscureToggle);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

      // 3. Navigate to Sign Up: "Don't have an account? Sign Up"
      final toSignUpBtn = find.text('Sign Up');
      expect(toSignUpBtn, findsOneWidget);
      await tester.tap(toSignUpBtn);
      await tester.pumpAndSettle();

      // Verify Sign Up Screen is active
      expect(find.text('Create your account'), findsOneWidget);

      // 4. SignUp validation: tap Create Account with empty fields
      await tester.tap(find.widgetWithText(TabbyButton, 'Create Account'));
      await tester.pumpAndSettle();
      expect(find.text('Please fill in all fields'), findsOneWidget);

      // 5. SignUp password mismatch validation
      final nameField = find.widgetWithText(TextField, 'Full Name');
      final emailField = find.widgetWithText(TextField, 'Email');
      final phoneField = find.widgetWithText(TextField, '+63 9XX XXX XXXX');
      final passField = find.widgetWithText(TextField, 'Password');
      final confirmPassField = find.widgetWithText(TextField, 'Confirm Password');

      await tester.enterText(nameField, 'Juan Dela Cruz');
      await tester.enterText(emailField, 'juan@tabby.ph');
      await tester.enterText(phoneField, '+63 917 123 4567');
      await tester.enterText(passField, 'Secret123');
      await tester.enterText(confirmPassField, 'DifferentPass456');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TabbyButton, 'Create Account'));
      await tester.pumpAndSettle();
      expect(find.text('Passwords do not match'), findsOneWidget);

      // 6. SignUp password obscure toggles
      final signUpToggles = find.byIcon(Icons.visibility_off_outlined);
      expect(signUpToggles, findsNWidgets(2));
      await tester.tap(signUpToggles.first);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

      // 7. Test "Already have an account? Log In" navigation
      final toLoginLink = find.text('Log In');
      expect(toLoginLink, findsOneWidget);
      await tester.tap(toLoginLink);
      await tester.pumpAndSettle();
      expect(find.text('Keep tabs. Settle up.'), findsOneWidget);

      // 8. Go back to Sign Up and test AppBar back button
      await tester.tap(find.text('Sign Up'));
      await tester.pumpAndSettle();
      expect(find.text('Create your account'), findsOneWidget);

      final backBtn = find.byIcon(Icons.arrow_back_rounded);
      expect(backBtn, findsOneWidget);
      await tester.tap(backBtn);
      await tester.pumpAndSettle();
      expect(find.text('Keep tabs. Settle up.'), findsOneWidget);

      // 9. Test Continue with Google button on Login screen
      final googleBtn = find.widgetWithText(TabbyButton, 'Continue with Google');
      expect(googleBtn, findsOneWidget);
      await tester.tap(googleBtn);
      await tester.pumpAndSettle();
      expect(AppState.isAuthenticated.value, isTrue);
      expect(find.text('Recent Activity'), findsOneWidget);

      // 10. Test Sign Up account creation flow
      AppState.isAuthenticated.value = false;
      appRouter.go('/signup');
      await tester.pumpAndSettle();
      expect(find.text('Create your account'), findsOneWidget);

      // Verify empty fields validation
      await tester.tap(find.widgetWithText(TabbyButton, 'Create Account'));
      await tester.pumpAndSettle();
      expect(find.text('Please fill in all fields'), findsOneWidget);

      // Verify invalid email validation
      await tester.enterText(find.widgetWithText(TextField, 'Full Name'), 'Juan Dela Cruz');
      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'not-an-email');
      await tester.enterText(find.widgetWithText(TextField, '+63 9XX XXX XXXX'), '+63 917 123 4567');
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'Password123!');
      await tester.enterText(find.widgetWithText(TextField, 'Confirm Password'), 'Password123!');
      await tester.tap(find.widgetWithText(TabbyButton, 'Create Account'));
      await tester.pumpAndSettle();
      expect(find.text('Please enter a valid email address'), findsOneWidget);

      // Verify short password validation
      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'juan@tabby.ph');
      await tester.enterText(find.widgetWithText(TextField, 'Password'), '123');
      await tester.enterText(find.widgetWithText(TextField, 'Confirm Password'), '123');
      await tester.tap(find.widgetWithText(TabbyButton, 'Create Account'));
      await tester.pumpAndSettle();
      expect(find.text('Password must be at least 6 characters'), findsOneWidget);

      // Verify password mismatch validation
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'Password123!');
      await tester.enterText(find.widgetWithText(TextField, 'Confirm Password'), 'DifferentPassword!');
      await tester.tap(find.widgetWithText(TabbyButton, 'Create Account'));
      await tester.pumpAndSettle();
      expect(find.text('Passwords do not match'), findsOneWidget);

      // Verify successful account creation with valid credentials
      await tester.enterText(find.widgetWithText(TextField, 'Confirm Password'), 'Password123!');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TabbyButton, 'Create Account'));
      await tester.pumpAndSettle();

      // Verified routed to Home Dashboard
      expect(AppState.isAuthenticated.value, isTrue);
      expect(find.text('Recent Activity'), findsOneWidget);
    });

    testWidgets('Home Dashboard: Upcoming dues action buttons and Activity details sheet', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      AppState.isAuthenticated.value = true;
      appRouter.go('/home');

      await tester.pumpWidget(
        const ProviderScope(
          child: TabbyApp(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Test Upcoming Reminder Nudge / Remind button
      final remindBtn = find.widgetWithText(InkWell, 'Remind');
      if (remindBtn.evaluate().isNotEmpty) {
        await tester.ensureVisible(remindBtn.first);
        await tester.tap(remindBtn.first);
        await tester.pumpAndSettle();
        expect(find.textContaining('Friendly reminder sent to'), findsOneWidget);
        ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first)).clearSnackBars();
        await tester.pumpAndSettle();
      }

      // 2. Test Recent Activity Tile Tap -> Activity Details Sheet
      final activityTitle = find.text('Team Lunch');
      if (activityTitle.evaluate().isNotEmpty) {
        await tester.ensureVisible(activityTitle.first);
        await tester.tap(activityTitle.first);
        await tester.pumpAndSettle();

        expect(find.text('Activity Details'), findsOneWidget);
        expect(find.text('Close'), findsOneWidget);

        // Tap Close button
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(find.text('Activity Details'), findsNothing);
      }
    });

    testWidgets('Add Expense Modal: Duplicate expense warning dialog and Preset chips', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      AppState.isAuthenticated.value = true;
      appRouter.go('/home');

      await tester.pumpWidget(
        const ProviderScope(
          child: TabbyApp(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Open Add Expense Modal
      final fab = find.byType(FloatingActionButton);
      await tester.tap(fab);
      await tester.pumpAndSettle();

      // Test preset chips: +₱100, +₱1000, +₱2000
      final preset100 = find.text('+₱100');
      await tester.ensureVisible(preset100);
      await tester.tap(preset100);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '100.00'), findsOneWidget);

      final preset1000 = find.text('+₱1000');
      await tester.ensureVisible(preset1000);
      await tester.tap(preset1000);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '1100.00'), findsOneWidget);

      final preset2000 = find.text('+₱2000');
      await tester.ensureVisible(preset2000);
      await tester.tap(preset2000);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '3100.00'), findsOneWidget);

      // Enter friend and description
      final nameField = find.widgetWithText(TextField, 'Enter name (e.g. Alex, Maria, Weekend Group)');
      await tester.enterText(nameField, 'Duplicate Test Friend');
      await tester.pumpAndSettle();

      // Set amount to 450.00
      final amountField = find.widgetWithText(TextField, '3100.00');
      await tester.enterText(amountField, '450.00');
      await tester.pumpAndSettle();

      // Save initial expense
      final saveBtn1 = find.text('Save Tab');
      await tester.ensureVisible(saveBtn1);
      await tester.tap(saveBtn1);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // Clear SnackBars so it doesn't obstruct FAB tap
      ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first)).clearSnackBars();
      await tester.pumpAndSettle();

      // 2. Open Add Expense Modal again to log the EXACT SAME amount with same friend
      await tester.tap(fab);
      await tester.pumpAndSettle();

      final nameField2 = find.widgetWithText(TextField, 'Enter name (e.g. Alex, Maria, Weekend Group)');
      await tester.enterText(nameField2, 'Duplicate Test Friend');
      await tester.pumpAndSettle();

      final amountField2 = find.widgetWithText(TextField, '0.00');
      await tester.enterText(amountField2, '450.00');
      await tester.pumpAndSettle();

      // Tap Save Tab -> should trigger _showDuplicateWarning
      final saveBtn2 = find.text('Save Tab');
      await tester.ensureVisible(saveBtn2);
      await tester.tap(saveBtn2);
      await tester.pumpAndSettle();

      // Verify Duplicate Dialog appears
      expect(find.text('Possible Duplicate'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Create Anyway'), findsOneWidget);

      // Test Cancel: dismisses dialog, modal remains
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Possible Duplicate'), findsNothing);
      expect(find.text('Quick Log Expense'), findsOneWidget);

      // Tap Save Tab again -> dialog reappears
      await tester.tap(saveBtn2);
      await tester.pumpAndSettle();
      expect(find.text('Possible Duplicate'), findsOneWidget);

      // Test Create Anyway: commits expense
      await tester.tap(find.text('Create Anyway'));
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      expect(find.text('Quick Log Expense'), findsNothing);
    });

    testWidgets('Tab Detail: User owes (I Paid) settlement, Receipt viewer actions, and Log New Expense', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      AppState.isAuthenticated.value = true;
      appRouter.go('/home');

      await tester.pumpWidget(
        const ProviderScope(
          child: TabbyApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Log an expense where "They paid" so current user owes counterpart
      final fab = find.byType(FloatingActionButton);
      await tester.tap(fab);
      await tester.pumpAndSettle();

      final nameField = find.widgetWithText(TextField, 'Enter name (e.g. Alex, Maria, Weekend Group)');
      await tester.enterText(nameField, 'Carlos Dalisay');
      await tester.pumpAndSettle();

      final amountField = find.widgetWithText(TextField, '0.00');
      await tester.enterText(amountField, '800.00');
      await tester.pumpAndSettle();

      // Tap "They paid"
      final theyPaidBtn = find.text('They paid');
      await tester.ensureVisible(theyPaidBtn);
      await tester.tap(theyPaidBtn);
      await tester.pumpAndSettle();

      final saveBtn = find.text('Save Tab');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // Navigate to My Tabs
      appRouter.go('/tabs');
      await tester.pumpAndSettle();

      // Tap on Carlos Dalisay
      final carlosTile = find.text('Carlos Dalisay');
      expect(carlosTile, findsOneWidget);
      await tester.tap(carlosTile);
      await tester.pumpAndSettle();

      // 1. Verify "I Paid" button exists
      final iPaidBtn = find.widgetWithText(TabbyButton, 'I Paid');
      expect(iPaidBtn, findsOneWidget);

      // Tap "I Paid" -> opens Record Settlement
      await tester.tap(iPaidBtn);
      await tester.pumpAndSettle();

      expect(find.text('Record Settlement'), findsOneWidget);
      expect(find.text('Submit Payment Proof'), findsOneWidget);

      // Select GCash and tap Submit Payment Proof
      await tester.tap(find.widgetWithText(ChoiceChip, 'GCash'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TabbyButton, 'Submit Payment Proof'));
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // Tab should now be settled
      expect(find.text('All settled up'), findsOneWidget);
      expect(find.text('Log New Expense'), findsOneWidget);

      // 2. Tap Log New Expense -> opens AddExpenseModal
      await tester.tap(find.text('Log New Expense'));
      await tester.pumpAndSettle();
      expect(find.text('Quick Log Expense'), findsOneWidget);

      // Close modal
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // 3. Tap on a ledger entry without receipt -> test "Attach Receipt Photo"
      final entryTile = find.text('Food');
      if (entryTile.evaluate().isNotEmpty) {
        await tester.tap(entryTile.first);
        await tester.pumpAndSettle();

        expect(find.text('Expense Details'), findsOneWidget);
        final attachPhotoBtn = find.text('Attach Receipt Photo');
        if (attachPhotoBtn.evaluate().isNotEmpty) {
          await tester.tap(attachPhotoBtn);
          await tester.pumpAndSettle();
          expect(find.textContaining('Receipt image attached'), findsOneWidget);
          ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first)).clearSnackBars();
          await tester.pumpAndSettle();
        }

        // Close details sheet if still open
        if (find.byIcon(Icons.close_rounded).evaluate().isNotEmpty) {
          await tester.tap(find.byIcon(Icons.close_rounded).last);
          await tester.pumpAndSettle();
        }
      }
    });

    testWidgets('Profile Screen: Deep settings sheets, Avatar options, and Form validations', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      AppState.isAuthenticated.value = true;
      appRouter.go('/profile');

      await tester.pumpWidget(
        const ProviderScope(
          child: TabbyApp(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Deep Security Settings Sheet
      final securityIconBtn = find.byTooltip('Security Settings');
      expect(securityIconBtn, findsOneWidget);
      await tester.tap(securityIconBtn);
      await tester.pumpAndSettle();

      expect(find.text('Security & App Lock'), findsOneWidget);
      expect(find.text('Biometric Unlock'), findsOneWidget);
      expect(find.text('Passcode Protection'), findsOneWidget);
      expect(find.text('Auto-Lock on Exit'), findsOneWidget);

      // Toggle Passcode switch
      final passcodeSwitch = find.widgetWithText(SwitchListTile, 'Passcode Protection');
      await tester.tap(passcodeSwitch);
      await tester.pumpAndSettle();

      // Tap Done
      await tester.tap(find.widgetWithText(TabbyButton, 'Done'));
      await tester.pumpAndSettle();
      expect(find.text('Security & App Lock'), findsNothing);

      // 2. Deep Notification Preferences Sheet
      final notifIconBtn = find.byTooltip('Notification Preferences');
      expect(notifIconBtn, findsOneWidget);
      await tester.tap(notifIconBtn);
      await tester.pumpAndSettle();

      expect(find.text('Notification Preferences'), findsOneWidget);
      expect(find.text('Push Notifications'), findsOneWidget);
      expect(find.text('Instant Payment Alerts'), findsOneWidget);
      expect(find.text('Gentle Reminder Nudges'), findsOneWidget);

      // Toggle Instant Payment Alerts
      final paymentAlertsSwitch = find.widgetWithText(SwitchListTile, 'Instant Payment Alerts');
      await tester.tap(paymentAlertsSwitch);
      await tester.pumpAndSettle();

      // Tap Done
      await tester.tap(find.widgetWithText(TabbyButton, 'Done'));
      await tester.pumpAndSettle();
      expect(find.text('Notification Preferences'), findsNothing);

      // 3. Avatar Options Sheet
      // Ensure page is scrolled back to top
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 800));
      await tester.pumpAndSettle();

      final cameraIconBtn = find.byIcon(Icons.camera_alt_rounded);
      await tester.tap(cameraIconBtn.first);
      await tester.pumpAndSettle();

      expect(find.text('Profile Photo'), findsOneWidget);
      expect(find.text('Choose from Gallery'), findsOneWidget);
      expect(find.text('Take Photo'), findsOneWidget);
      expect(find.text('Tabby Mascot Style'), findsOneWidget);
      expect(find.text('Remove Photo'), findsOneWidget);

      // Select Choose from Gallery
      await tester.tap(find.text('Choose from Gallery'));
      await tester.pumpAndSettle();
      expect(find.text('Profile photo updated successfully.'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(ProfileScreen))).clearSnackBars();
      await tester.pumpAndSettle();

      // Open avatar sheet again -> Select Tabby Mascot Style
      await tester.tap(find.byIcon(Icons.camera_alt_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tabby Mascot Style'));
      await tester.pumpAndSettle();
      expect(find.text('Tabby companion avatar applied!'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(ProfileScreen))).clearSnackBars();
      await tester.pumpAndSettle();

      // Open avatar sheet again -> Remove Photo
      await tester.tap(find.byIcon(Icons.camera_alt_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove Photo'));
      await tester.pumpAndSettle();
      expect(find.text('Avatar reset to default initials.'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(ProfileScreen))).clearSnackBars();
      await tester.pumpAndSettle();

      // 4. Edit Profile validation: empty name
      await tester.tap(find.text('Edit Profile'));
      await tester.pumpAndSettle();

      final editNameField = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(TextField),
      ).first;
      await tester.enterText(editNameField, '');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TabbyButton, 'Save Changes'));
      await tester.pumpAndSettle();
      expect(find.text('Please enter a display name.'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(ProfileScreen))).clearSnackBars();
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // 5. Add Friend validation: empty name
      final addFriendBtn = find.text('Add');
      await tester.ensureVisible(addFriendBtn);
      await tester.tap(addFriendBtn);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TabbyButton, 'Add Friend'));
      await tester.pumpAndSettle();
      expect(find.text('Please enter a name for your friend.'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(ProfileScreen))).clearSnackBars();
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // 6. Create Group validation: empty group name
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
      await tester.pumpAndSettle();

      final createGroupBtn = find.text('Create a Group');
      if (createGroupBtn.evaluate().isNotEmpty) {
        await tester.tap(createGroupBtn);
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(TabbyButton, 'Create Group Tab'));
        await tester.pumpAndSettle();
        expect(find.text('Please enter a group name.'), findsOneWidget);
        ScaffoldMessenger.of(tester.element(find.byType(ProfileScreen))).clearSnackBars();
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('Notification Center Sheet: Dues interactive Pay and Remind buttons', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      AppState.isAuthenticated.value = true;
      appRouter.go('/home');

      await tester.pumpWidget(
        const ProviderScope(
          child: TabbyApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Open Notification Center
      final notifBtn = find.byIcon(Icons.notifications_none_rounded);
      await tester.tap(notifBtn.first);
      await tester.pumpAndSettle();

      expect(find.text('Notifications'), findsOneWidget);

      // Check for Remind button inside Notification Center Sheet
      final remindBtn = find.descendant(
        of: find.byType(NotificationCenterSheet),
        matching: find.widgetWithText(ElevatedButton, 'Remind'),
      );
      if (remindBtn.evaluate().isNotEmpty) {
        await tester.tap(remindBtn.first);
        await tester.pumpAndSettle();
        expect(find.textContaining('Friendly reminder sent to'), findsOneWidget);
        ScaffoldMessenger.of(tester.element(find.byType(NotificationCenterSheet))).clearSnackBars();
        await tester.pumpAndSettle();
      }

      // Check for Pay button inside Notification Center Sheet
      final payBtn = find.descendant(
        of: find.byType(NotificationCenterSheet),
        matching: find.widgetWithText(ElevatedButton, 'Pay'),
      );
      if (payBtn.evaluate().isNotEmpty) {
        await tester.tap(payBtn.first);
        await tester.pumpAndSettle();
        // Navigates to Tab Detail screen
        expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      } else {
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('App Router 404 Error Screen: Unknown path displays friendly mascot and back button', (tester) async {
      AppState.isAuthenticated.value = true;
      appRouter.go('/unknown-route-that-does-not-exist');

      await tester.pumpWidget(
        const ProviderScope(
          child: TabbyApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Page Not Found'), findsOneWidget);
      expect(find.text("The page you're looking for doesn't exist or has been moved."), findsOneWidget);
      expect(find.widgetWithText(TabbyButton, 'Back to Home'), findsOneWidget);

      await tester.tap(find.widgetWithText(TabbyButton, 'Back to Home'));
      await tester.pumpAndSettle();
      expect(find.text('Recent Activity'), findsOneWidget);
    });
  });
}
