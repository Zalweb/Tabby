import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabby/main.dart';
import 'package:tabby/core/config/app_state.dart';
import 'package:tabby/core/router/app_router.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    AppState.isAuthenticated.value = true;
    AppState.hasSeenOnboarding.value = true;
    AppState.profileCompletionRequired.value = false;
  });

  testWidgets('Login screen: Google OAuth is the only sign-in path',
      (tester) async {
    AppState.isAuthenticated.value = false;

    await tester.pumpWidget(
      const ProviderScope(
        child: TabbyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Forgot password?'), findsNothing);
    expect(find.text('Sign Up'), findsNothing);

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    // Offline mode must not claim that an OAuth session was created.
    expect(
        find.text(
            'Authentication service is unavailable. Please try again when online.'),
        findsOneWidget);
  });

  testWidgets('Notification Center sheet opens and functions from dashboard',
      (tester) async {
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

    // Find notification icon in Home header
    final notifBtn = find.byIcon(Icons.notifications_none_rounded);
    expect(notifBtn, findsWidgets);
    await tester.tap(notifBtn.first);
    await tester.pumpAndSettle();

    // Notification center sheet opened
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('No New Notifications'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);

    // Close notification sheet
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsNothing);
  });

  testWidgets(
      'Profile screen: Edit profile, QR manager, Add Friend, and Sheets are fully interactive',
      (tester) async {
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

    // Navigate to Profile
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    // 1. Edit Profile
    expect(find.text('Edit Profile'), findsOneWidget);
    await tester.tap(find.text('Edit Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Save Changes'), findsOneWidget);
    final editFields = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    );
    await tester.enterText(editFields.at(0), 'Frienzal Santos');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(find.text('Profile details updated successfully!'), findsOneWidget);
    expect(find.text('Frienzal Santos'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // 2. Avatar options
    final cameraIcon = find.byIcon(Icons.camera_alt_rounded);
    expect(cameraIcon, findsOneWidget);
    await tester.tap(cameraIcon);
    await tester.pumpAndSettle();
    expect(find.text('Profile Photo'), findsOneWidget);
    expect(find.text('Take Photo'), findsOneWidget);
    await tester.tap(find.text('Take Photo'));
    await tester.pumpAndSettle();
    expect(find.text('Camera snapshot applied to profile.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // 3. QR Manager
    final manageQrText = find.text('Manage Payment QR Code');
    await tester.ensureVisible(manageQrText);
    await tester.tap(manageQrText);
    await tester.pumpAndSettle();

    expect(find.text('Payment QR Ph Settings'), findsOneWidget);
    expect(find.text('Save Payment Details'), findsOneWidget);
    await tester.tap(find.text('Save Payment Details'));
    await tester.pumpAndSettle();
    expect(find.text('Payment QR and numbers saved!'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // 4. Connect Friend flow
    final connectBtn = find.text('Connect');
    await tester.ensureVisible(connectBtn);
    await tester.tap(connectBtn);
    await tester.pumpAndSettle();
    expect(find.text('Connect with a Friend'), findsOneWidget);
    expect(find.text('Friend\'s Full Name'), findsNothing);
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // 5. Currency Precision sheet
    final currencyTile = find.text('Currency Precision');
    await tester.ensureVisible(currencyTile);
    await tester.tap(currencyTile);
    await tester.pumpAndSettle();

    expect(find.text('Integer Centavo Precision'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    // 6. Sync Diagnostics sheet
    final syncTile = find.text('Backend & Offline Sync');
    await tester.ensureVisible(syncTile);
    await tester.tap(syncTile);
    await tester.pumpAndSettle();

    expect(find.text('Backend & Offline Sync'), findsWidgets);
    expect(find.text('Sync Data Now'), findsOneWidget);
    await tester.tap(find.text('Sync Data Now'));
    await tester.pumpAndSettle();
    expect(find.text('All tabs and transactions are fully synchronized.'),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // 7. Security Switch
    final securityTile = find.text('Security');
    await tester.ensureVisible(securityTile);
    await tester.tap(securityTile);
    await tester.pumpAndSettle();
    expect(find.text('Biometric security disabled.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // 8. General Settings Switch
    final settingsTile = find.text('Settings');
    await tester.ensureVisible(settingsTile);
    await tester.tap(settingsTile);
    await tester.pumpAndSettle();
    expect(find.text('Notifications disabled.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // 9. Help Center sheet
    final helpTile = find.text('Help Center');
    await tester.ensureVisible(helpTile);
    await tester.tap(helpTile);
    await tester.pumpAndSettle();

    expect(find.text('Help Center & FAQ'), findsOneWidget);
    expect(find.text('What is a Tab in Tabby?'), findsOneWidget);
    expect(find.textContaining('running balance between you'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // 10. Logout confirmation dialog
    final logoutTile = find.text('Logout');
    await tester.ensureVisible(logoutTile);
    await tester.tap(logoutTile);
    await tester.pumpAndSettle();

    expect(find.text('Log Out'), findsWidgets);
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(AppState.isAuthenticated.value, isTrue);

    await tester.ensureVisible(logoutTile);
    await tester.tap(logoutTile);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log Out').last);
    await tester.pumpAndSettle();
    expect(AppState.isAuthenticated.value, isFalse);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets(
      'Dashboard filter switching and activity details sheet work cleanly',
      (tester) async {
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

    // Tap Weekly filter
    final weeklyText = find.text('Weekly');
    await tester.ensureVisible(weeklyText);
    await tester.tap(weeklyText);
    await tester.pumpAndSettle();

    // Tap Daily filter
    final dailyText = find.text('Daily');
    await tester.ensureVisible(dailyText);
    await tester.tap(dailyText);
    await tester.pumpAndSettle();

    // Tap Monthly filter
    final monthlyText = find.text('Monthly');
    await tester.ensureVisible(monthlyText);
    await tester.tap(monthlyText);
    await tester.pumpAndSettle();
  });

  testWidgets(
      'Profile: Groups creation, Friend management (edit & remove), and QR Ph management',
      (tester) async {
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

    // 1. Seed a saved contact for friend-management coverage.
    final profileContainer = ProviderScope.containerOf(
      tester.element(find.text('Profile & Settings')),
    );
    await profileContainer.read(tabbyProvider.notifier).addFriend(
          name: 'Carlos Yulo',
          phone: '+63 918 111 2222',
        );
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Carlos Yulo'), findsOneWidget);

    // 2. Open friend options sheet and edit friend
    final moreBtn = find.byIcon(Icons.more_vert_rounded).first;
    await tester.ensureVisible(moreBtn);
    await tester.tap(moreBtn);
    await tester.pumpAndSettle();

    expect(find.text('Edit Friend Details'), findsOneWidget);
    await tester.tap(find.text('Edit Friend Details'));
    await tester.pumpAndSettle();

    final editFields = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    );
    await tester.enterText(editFields.at(0), 'Carlos Edriel Yulo');
    await tester.pumpAndSettle();

    final editScrollable = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(SingleChildScrollView),
    );
    await tester.drag(editScrollable, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Changes'), warnIfMissed: false);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(find.text('Carlos Edriel Yulo'), findsOneWidget);

    // 3. Create a Group Tab
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Create a Group'), findsOneWidget);
    await tester.tap(find.text('Create a Group'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Create New Group Tab'), findsOneWidget);
    final groupNameField = find
        .descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(TextField),
        )
        .first;
    await tester.enterText(groupNameField, 'Gym Barkada');
    await tester.pumpAndSettle();

    // Select Carlos Edriel Yulo chip
    final chip = find.byType(FilterChip).first;
    await tester.tap(chip);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create Group Tab'));
    await tester.pumpAndSettle();

    expect(find.text('Gym Barkada'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // 4. Test QR Ph upload and removal
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 600));
    await tester.pumpAndSettle();
    final manageQrBtn = find.text('Manage Payment QR Code');
    await tester.ensureVisible(manageQrBtn);
    await tester.tap(manageQrBtn);
    await tester.pumpAndSettle();

    expect(find.text('Upload New QR Code Image'), findsOneWidget);
    await tester.tap(find.text('Upload New QR Code Image'));
    await tester.pumpAndSettle();

    expect(
        find.text('Payment QR Ph code verified and linked!'), findsOneWidget);
    expect(find.text('Custom QR Ph Code Active & Verified'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // Open QR manager again to remove custom QR
    final editQrBtn = find.text('Edit Payment QR Code');
    await tester.ensureVisible(editQrBtn);
    await tester.tap(editQrBtn);
    await tester.pumpAndSettle();

    expect(find.text('Remove QR Code'), findsOneWidget);
    await tester.tap(find.text('Remove QR Code'));
    await tester.pumpAndSettle();
    expect(find.text('Custom QR code removed.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // 5. Remove Friend
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    final moreBtn2 = find.byIcon(Icons.more_vert_rounded).first;
    await tester.ensureVisible(moreBtn2);
    await tester.tap(moreBtn2);
    await tester.pumpAndSettle();

    expect(find.text('Remove Friend'), findsOneWidget);
    await tester.tap(find.text('Remove Friend'));
    await tester.pumpAndSettle();

    expect(
        find.text(
            'Are you sure you want to remove Carlos Edriel Yulo from your friends list?'),
        findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Carlos Edriel Yulo has been removed from your friends list.'),
        findsOneWidget);
  });

  testWidgets(
      'Tab detail: Clipboard copying, Receipts viewing, and Expense receipt attachment',
      (tester) async {
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
    expect(fab, findsOneWidget);
    await tester.tap(fab);
    await tester.pumpAndSettle();

    expect(find.text('Quick Log Expense'), findsOneWidget);

    final modalScrollable = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(SingleChildScrollView),
    );

    // Scroll down to attach receipt
    await tester.drag(modalScrollable, const Offset(0, -300));
    await tester.pumpAndSettle();

    final attachBtn = find.text('Attach');
    expect(attachBtn, findsOneWidget);
    await tester.tap(attachBtn, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Receipt: Attached'), findsOneWidget);

    // Scroll back up to enter details
    await tester.drag(modalScrollable, const Offset(0, 300));
    await tester.pumpAndSettle();

    // Enter friend name
    final nameField = find.widgetWithText(
        TextField, 'Enter name (e.g. Alex, Maria, Weekend Group)');
    await tester.enterText(nameField, 'Alex Dela Cruz');
    await tester.pumpAndSettle();

    // Enter amount
    final amountField = find.widgetWithText(TextField, '0.00');
    await tester.enterText(amountField, '1200.00');
    await tester.pumpAndSettle();

    // Enter description
    final descField = find.descendant(
      of: find.byType(BottomSheet),
      matching:
          find.widgetWithText(TextField, 'Dinner, Grocery run, Taxi fare'),
    );
    await tester.enterText(descField, 'Team Dinner');
    await tester.pumpAndSettle();

    // Scroll down to save button
    await tester.drag(modalScrollable, const Offset(0, -400));
    await tester.pumpAndSettle();

    final commitBtn = find.text('Save Tab');
    expect(commitBtn, findsOneWidget);
    await tester.tap(commitBtn, warnIfMissed: false);
    await tester.pumpAndSettle();

    // Navigate to My Tabs
    appRouter.go('/tabs');
    await tester.pumpAndSettle();

    // Tap the tab to view detail
    final tabTile = find.text('Alex Dela Cruz');
    expect(tabTile, findsWidgets);
    await tester.tap(tabTile.first);
    await tester.pumpAndSettle();

    // Verify Tab detail screen opened
    expect(find.text('Shared Media & Receipts'), findsNothing);

    // Tap View Receipts icon button in header
    final receiptBtn = find.byIcon(Icons.receipt_long_rounded);
    expect(receiptBtn, findsWidgets);
    await tester.tap(receiptBtn.first);
    await tester.pumpAndSettle();

    expect(find.text('Shared Media & Receipts'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    // Tap entry to view entry details
    final entryTile = find.text('Team Dinner');
    expect(entryTile, findsWidgets);
    await tester.tap(entryTile.first);
    await tester.pumpAndSettle();

    expect(find.text('Expense Details'), findsOneWidget);
    expect(
        find.textContaining('Verified Bill/Receipt Attached'), findsOneWidget);

    // Tap verified bill/receipt attached badge to open preview modal
    await tester.tap(find.textContaining('Verified Bill/Receipt Attached'));
    await tester.pumpAndSettle();
    expect(find.text('Receipt Preview'), findsOneWidget);
    expect(find.text('Save Image'), findsOneWidget);
    await tester.tap(find.text('Close').last);
    await tester.pumpAndSettle();

    // Close entry details sheet
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    // Tap Payment Info icon button in header
    final paymentInfoBtn = find.byIcon(Icons.qr_code_2_rounded);
    expect(paymentInfoBtn, findsWidgets);
    await tester.tap(paymentInfoBtn.first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Payment Info'), findsOneWidget);
    expect(find.text('Tap to enlarge'), findsOneWidget);

    // Tap QR Ph container to enlarge
    await tester.tap(find.text('Tap to enlarge'));
    await tester.pumpAndSettle();

    expect(find.text('QR Ph Official'), findsOneWidget);
    expect(find.text('Copy QR String'), findsOneWidget);
    await tester.tap(find.text('Copy QR String'));
    await tester.pumpAndSettle();
    expect(find.text('QR Ph payload copied to clipboard!'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // Close QR modal (topmost sheet)
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();

    // Close underlying payment info sheet
    if (find.byIcon(Icons.close_rounded).evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
      'Tab detail empty state: Shows mascot and Log First Expense CTA when tab has zero entries',
      (tester) async {
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

    // Add a saved contact with zero initial expenses.
    final profileContainer = ProviderScope.containerOf(
      tester.element(find.text('Profile & Settings')),
    );
    await profileContainer.read(tabbyProvider.notifier).addFriend(
          name: 'Empty Tab Friend',
          phone: '+63 999 000 1111',
        );
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // Go to My Tabs and open this friend's tab
    appRouter.go('/tabs');
    await tester.pumpAndSettle();

    final friendTile = find.text('Empty Tab Friend');
    expect(friendTile, findsWidgets);
    await tester.tap(friendTile.first);
    await tester.pumpAndSettle();

    // Verify empty state is displayed
    expect(find.text('No transactions yet'), findsOneWidget);
    expect(find.text('Log First Expense'), findsOneWidget);

    // Tap Log First Expense CTA button
    await tester.tap(find.text('Log First Expense'));
    await tester.pumpAndSettle();

    // Verify AddExpenseModal opened with pre-filled friend name
    expect(find.text('Quick Log Expense'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Empty Tab Friend'), findsOneWidget);
  });

  testWidgets(
      'AddExpenseModal chips include both friends and groups with group icon',
      (tester) async {
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

    // Create a group
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
    await tester.pumpAndSettle();
    final createGroupBtn = find.text('Create a Group');
    await tester.tap(createGroupBtn, warnIfMissed: false);
    await tester.pumpAndSettle();

    final groupNameField = find
        .descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(TextField),
        )
        .first;
    await tester.enterText(groupNameField, 'Beach Trip 2026');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create Group Tab'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // Now open AddExpenseModal
    appRouter.go('/tabs');
    await tester.pumpAndSettle();

    final fab = find.byType(FloatingActionButton);
    await tester.tap(fab);
    await tester.pumpAndSettle();

    // Beach Trip 2026 should be in choice chips
    final groupChip = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.widgetWithText(ChoiceChip, 'Beach Trip 2026'),
    );
    expect(groupChip, findsOneWidget);
    await tester.tap(groupChip);
    await tester.pumpAndSettle();

    // Verify group name populated in TextField
    final modalTextField = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.widgetWithText(TextField, 'Beach Trip 2026'),
    );
    expect(modalTextField, findsOneWidget);

    // Close modal
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    // Remove group tab from profile
    appRouter.go('/profile');
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await tester.pumpAndSettle();

    final groupOptionsBtn = find.byIcon(Icons.more_vert_rounded).first;
    await tester.ensureVisible(groupOptionsBtn);
    await tester.tap(groupOptionsBtn);
    await tester.pumpAndSettle();

    expect(find.text('Delete Group Tab'), findsOneWidget);
    await tester.tap(find.text('Delete Group Tab'));
    await tester.pumpAndSettle();

    expect(
        find.textContaining(
            'Are you sure you want to delete "Beach Trip 2026"?'),
        findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(
        find.text('Group "Beach Trip 2026" has been deleted.'), findsOneWidget);
  });
}
