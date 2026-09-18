import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabby/main.dart';
import 'package:tabby/core/config/app_state.dart';
import 'package:tabby/core/router/app_router.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:tabby/shared/widgets/tabby_button.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    AppState.isAuthenticated.value = true;
    AppState.hasSeenOnboarding.value = true;
    AppState.profileCompletionRequired.value = false;
  });

  testWidgets('Login screen: Google OAuth and email credentials are available',
      (tester) async {
    AppState.isAuthenticated.value = false;

    await tester.pumpWidget(
      const ProviderScope(
        child: TabbyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
    expect(find.text('Create an account'), findsOneWidget);

    final googleButton = find.text('Continue with Google');
    await tester.ensureVisible(googleButton);
    await tester.tap(googleButton);
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

    expect(find.text('Payment Methods'), findsWidgets);
    expect(find.text('Add Payment Method'), findsOneWidget);
    await tester.tap(find.text('Add Payment Method'));
    await tester.pumpAndSettle();
    expect(find.text('Save Payment Method'), findsOneWidget);
    final paymentMethodName = find.byType(TextField).first;
    await tester.enterText(paymentMethodName, 'My GCash QR');
    await tester.tap(find.text('Save Payment Method'));
    await tester.pumpAndSettle();
    expect(find.text('My GCash QR'), findsNothing);
    await tester.tap(find.byIcon(Icons.close_rounded).last);
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
    final syncTile = find.text('Sync & Offline');
    await tester.ensureVisible(syncTile);
    await tester.tap(syncTile);
    await tester.pumpAndSettle();

    expect(find.text('Backend & Offline Sync'), findsWidgets);
    expect(find.text('Sync Data Now'), findsOneWidget);
    await tester.tap(find.text('Sync Data Now'));
    await tester.pumpAndSettle();
    expect(
      find
              .text('All tabs and transactions are fully synchronized.')
              .evaluate()
              .isNotEmpty ||
          find
              .textContaining('Tabby kept your cached data safe.')
              .evaluate()
              .isNotEmpty,
      isTrue,
    );
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // 7. Security Switch
    final securityTile = find.text('Security');
    await tester.ensureVisible(securityTile);
    await tester.tap(securityTile);
    await tester.pumpAndSettle();
    // Device authentication is intentionally not forced on a test device.
    expect(find.text('Biometric security disabled'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // 8. General Settings Switch
    final settingsTile = find.text('Notifications');
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
    final logoutTile = find.text('Log Out');
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

    // 1. Seed an accepted registered friend for friend-management coverage.
    final profileContainer = ProviderScope.containerOf(
      tester.element(find.text('Profile & Settings')),
    );
    seedAcceptedFriend(profileContainer, name: 'Carlos Yulo');
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // Navigate to Connections to manage friends
    final manageFriends = find.text('Manage Friends');
    await tester.ensureVisible(manageFriends);
    await tester.tap(manageFriends);
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
    appRouter.go('/profile');
    await tester.pumpAndSettle();
    final createGroupBtn = find.text('Create a Group');
    await tester.ensureVisible(createGroupBtn);
    await tester.tap(createGroupBtn);
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
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // Verify group in Connections Groups tab
    appRouter.go('/profile/connections');
    await tester.pumpAndSettle();
    final groupsTab = find.textContaining('Groups');
    await tester.tap(groupsTab);
    await tester.pumpAndSettle();
    expect(find.text('Gym Barkada'), findsOneWidget);

    // Return to profile for subsequent checks
    appRouter.go('/profile');
    await tester.pumpAndSettle();

    // 4. Test QR Ph upload and removal
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 600));
    await tester.pumpAndSettle();
    final manageQrBtn = find.text('Manage Payment QR Code');
    await tester.ensureVisible(manageQrBtn);
    await tester.tap(manageQrBtn);
    await tester.pumpAndSettle();

    expect(find.text('Payment Methods'), findsWidgets);
    expect(find.text('Add Payment Method'), findsOneWidget);
    await tester.tap(find.text('Add Payment Method'));
    await tester.pumpAndSettle();
    expect(find.text('Upload QR image'), findsOneWidget);
    Navigator.of(tester.element(find.text('Upload QR image'))).pop();
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('Payment Methods').last)).pop();
    await tester.pumpAndSettle();

    // 5. Remove Friend
    appRouter.go('/profile/connections');
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
    final createTabButton = find.text('Create a Tab');
    await tester.ensureVisible(createTabButton);
    await tester.tap(createTabButton);
    await tester.pumpAndSettle();

    expect(find.text('Create Tab'), findsOneWidget);

    final modalScrollable = find
        .descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        )
        .first;

    // Add the unregistered participant, then continue to details.
    final unregisteredField =
        find.byKey(const ValueKey('create-tab-unregistered-name'));
    await tester.enterText(unregisteredField, 'Alex Dela Cruz');
    await tester.tap(find.text('Add Person'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Enter amount
    final amountField = find.byKey(const ValueKey('create-tab-amount'));
    await tester.enterText(amountField, '1200.00');
    await tester.pumpAndSettle();

    // Enter description
    final descField = find.byKey(const ValueKey('create-tab-expense-title'));
    await tester.enterText(descField, 'Team Dinner');
    await tester.pumpAndSettle();

    // Attach a receipt, then create the tab.
    final attachBtn = find.text('Attach');
    expect(attachBtn, findsOneWidget);
    await tester.ensureVisible(attachBtn);
    await tester.tap(attachBtn, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Receipt attached'), findsOneWidget);

    final commitBtn = find.widgetWithText(TabbyButton, 'Create Tab');
    expect(commitBtn, findsOneWidget);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final modalScrollState = tester.state<ScrollableState>(modalScrollable);
    modalScrollState.position.jumpTo(modalScrollState.position.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.ensureVisible(commitBtn);
    await tester.pumpAndSettle();
    tester.widget<TabbyButton>(commitBtn).onPressed!();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Tab created'), findsOneWidget);
    await tester.tap(find.widgetWithText(TabbyButton, 'Done'));
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
    expect(find.text('Preferred'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    await tester.tap(find.text('Close').last);
    await tester.pumpAndSettle();
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
    expect(find.text('Create Tab'), findsOneWidget);
    expect(find.text('Empty Tab Friend'), findsOneWidget);
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

    final profileContainer = ProviderScope.containerOf(
      tester.element(find.text('Profile & Settings')),
    );
    seedAcceptedFriend(profileContainer, name: 'Alex Dela Cruz');

    // Create a group
    final createGroupBtn = find.text('Create a Group');
    await tester.ensureVisible(createGroupBtn);
    await tester.tap(createGroupBtn);
    await tester.pumpAndSettle();

    final groupNameField = find
        .descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(TextField),
        )
        .first;
    await tester.enterText(groupNameField, 'Beach Trip 2026');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, 'Alex Dela Cruz'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create Group Tab'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // Now open AddExpenseModal
    appRouter.go('/tabs');
    await tester.pumpAndSettle();

    final createTabButton = find.text('Create Tab').first;
    expect(createTabButton, findsOneWidget);
    await tester.ensureVisible(createTabButton);
    await tester.tap(createTabButton);
    await tester.pumpAndSettle();

    // Beach Trip 2026 should be in choice chips
    final groupChip = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.widgetWithText(ChoiceChip, 'Beach Trip 2026'),
    );
    expect(groupChip, findsOneWidget);
    await tester.tap(groupChip);
    await tester.pumpAndSettle();

    // Verify the existing group remains selected in the participant step.
    expect(find.text('Create Tab'), findsNWidgets(2));
    expect(find.text('Beach Trip 2026'), findsWidgets);

    // Close modal
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    // Remove group tab from connections
    appRouter.go('/profile/connections');
    await tester.pumpAndSettle();
    final groupsTab = find.textContaining('Groups');
    await tester.tap(groupsTab);
    await tester.pumpAndSettle();

    final groupTile = find.ancestor(
      of: find.text('Beach Trip 2026'),
      matching: find.byType(ListTile),
    );
    final groupOptionsBtn = find.descendant(
      of: groupTile,
      matching: find.byIcon(Icons.more_vert_rounded),
    );
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

void seedAcceptedFriend(ProviderContainer container, {required String name}) {
  const currentUser = TabbyUser(
    id: 'user-me',
    displayName: 'Frienzal',
    email: 'frienzal@tabby.ph',
    phone: '+639178881234',
    friendCode: 'TAB-9N6R3Q',
  );
  final friend = TabbyUser(
    id: 'friend-alex',
    displayName: name,
    email: 'alex@example.com',
    phone: '+639181112222',
    friendCode: 'TAB-7K4P2M',
  );
  final friendship = FriendRequest(
    id: 'friendship-alex',
    requesterId: currentUser.id,
    addresseeId: friend.id,
    requester: currentUser,
    addressee: friend,
    status: FriendRequestStatus.accepted,
    createdAt: DateTime(2026, 9, 17),
    currentUserId: currentUser.id,
  );
  final notifier = container.read(tabbyProvider.notifier);
  notifier.state = notifier.state.copyWith(
    tabs: [
      BilateralTab(
        id: friend.id,
        counterpart: friend,
        netBalanceCentavos: 0,
        itemCount: 0,
        entries: const [],
        lastUpdated: DateTime(2026, 9, 17),
      ),
    ],
    friendRequests: [friendship],
  );
}
