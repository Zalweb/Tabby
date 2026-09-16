import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabby/core/config/app_state.dart';
import 'package:tabby/core/router/app_router.dart';
import 'package:tabby/features/profile/presentation/profile_screen.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:tabby/main.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    AppState.isAuthenticated.value = true;
    AppState.hasSeenOnboarding.value = true;
  });

  testWidgets('Profile shows a shareable Tabby ID and connect action',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    appRouter.go('/profile');
    await tester.pumpWidget(const ProviderScope(child: TabbyApp()));
    await tester.pumpAndSettle();

    expect(find.text('Your Tabby ID'), findsOneWidget);
    expect(find.text('TAB-9N6R3Q'), findsOneWidget);
    expect(find.text('ID: USER-ME'), findsNothing);
    expect(find.text('Connect by Tabby ID'), findsWidgets);

    await tester.tap(find.text('Connect by Tabby ID').first);
    await tester.pumpAndSettle();

    expect(find.text('Connect with a Friend'), findsOneWidget);
    expect(find.text('Tabby ID'), findsOneWidget);
    expect(find.text('Send Friend Request'), findsNothing);
  });

  testWidgets('Friends Connect action opens the Tabby ID flow', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    appRouter.go('/profile');
    await tester.pumpWidget(const ProviderScope(child: TabbyApp()));
    await tester.pumpAndSettle();

    final connectAction = find.text('Connect');
    await tester.ensureVisible(connectAction);
    await tester.tap(connectAction);
    await tester.pumpAndSettle();

    expect(find.text('Connect with a Friend'), findsOneWidget);
    expect(find.text('Add a New Friend'), findsNothing);
    expect(find.text('Friend\'s Full Name'), findsNothing);
  });

  testWidgets('Quick Log Expense labels connected friends and preserves their ID',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    const friend = TabbyUser(
      id: 'friend-uuid',
      displayName: 'Alex',
      email: 'alex@example.com',
      phone: '',
      friendCode: 'TAB-7K4P2M',
    );
    final notifier = TabbyNotifier();
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
    );

    appRouter.go('/home');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [tabbyProvider.overrideWith((_) => notifier)],
        child: const TabbyApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, 'Alex'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);

    final amountField = find.widgetWithText(TextField, '0.00');
    await tester.enterText(amountField, '100.00');
    final saveButton = find.text('Save Tab');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(notifier.state.tabs.single.counterpart.id, friend.id);
    expect(notifier.state.tabs.single.entries.single.tabId, friend.id);
  });

  testWidgets('Connect by Tabby ID rejects malformed codes before lookup',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    appRouter.go('/profile');
    await tester.pumpWidget(const ProviderScope(child: TabbyApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect by Tabby ID').first);
    await tester.pumpAndSettle();

    final idField = find.widgetWithText(TextField, 'TAB-7K4P2M');
    await tester.enterText(idField, 'TAB-123');
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid Tabby ID such as TAB-7K4P2M.'),
        findsOneWidget);
    expect(find.text('Send Friend Request'), findsNothing);
  });

  testWidgets(
      'Connect by Tabby ID closes safely while a friend lookup is pending',
      (tester) async {
    final lookupCompleter = Completer<TabbyUser?>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => ConnectByIdSheet(
                  findFriend: (_) => lookupCompleter.future,
                  sendFriendRequest: (_) async => null,
                ),
              ),
              child: const Text('Open Connect Sheet'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Connect Sheet'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'TAB-7K4P2M');
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    lookupCompleter.complete(null);
    await tester.pumpAndSettle();

    expect(find.text('Connect with a Friend'), findsNothing);
  });
}
