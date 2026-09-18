import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:tabby/features/tabs/presentation/add_expense_modal.dart';
import 'package:tabby/shared/widgets/tabby_button.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets(
      'Create Tab wizard shows registered friends and reaches Details with payer labels',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final notifier = _notifierWithFriends();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [tabbyProvider.overrideWith((_) => notifier)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => AddExpenseModal.show(context),
                child: const Text('Open Create Tab'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Create Tab'));
    await tester.pumpAndSettle();

    expect(find.text('Create Tab'), findsOneWidget);
    expect(find.text('Add People'), findsNWidgets(2));
    expect(find.text('Friends'), findsOneWidget);
    expect(find.text('Add someone not on Tabby'), findsOneWidget);
    expect(find.widgetWithText(CheckboxListTile, 'Alex Dela Cruz'),
        findsOneWidget);
    expect(find.widgetWithText(CheckboxListTile, 'Maria Santos'), findsOneWidget);

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Alex Dela Cruz'));
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Maria Santos'));
    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Details'), findsNWidgets(2));
    expect(find.text('I paid'), findsOneWidget);
    expect(find.text('They paid'), findsOneWidget);
    expect(find.text('You paid'), findsNothing);
    expect(find.text('Create Tab'), findsNWidgets(2));

  });

  testWidgets(
      'Create Tab blocks an unregistered participant from joining a group selection',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final notifier = _notifierWithFriends();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [tabbyProvider.overrideWith((_) => notifier)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => AddExpenseModal.show(context),
                child: const Text('Open Create Tab'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Create Tab'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Alex Dela Cruz'));

    await tester.enterText(
      find.byKey(const ValueKey('create-tab-unregistered-name')),
      'Jordan Cruz',
    );
    await tester.tap(find.text('Add Person'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Group tabs require registered Tabby friends.'),
        findsOneWidget);
    expect(find.text('Add People'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('create-tab-details')), findsNothing);

  });

  testWidgets('Create Tab creates a group tab for multiple registered friends',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final notifier = _notifierWithFriends();

    await tester.pumpWidget(_createTabHost(notifier));
    await tester.tap(find.text('Open Create Tab'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Alex Dela Cruz'));
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Maria Santos'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('create-tab-tab-name')),
      'Barkada Dinner',
    );
    await tester.enterText(
      find.byKey(const ValueKey('create-tab-amount')),
      '900.00',
    );
    await tester.tap(find.widgetWithText(TabbyButton, 'Create Tab'));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(find.text('Tab created'), findsOneWidget);
    final groupTab = notifier.state.tabs.firstWhere(
      (tab) => tab.isGroupTab && tab.groupName == 'Barkada Dinner',
    );
    expect(groupTab.entries, hasLength(1));
    expect(groupTab.netBalanceCentavos, 60000);
    expect(groupTab.entries.single.myShareCentavos, 30000);
    expect(groupTab.entries.single.counterpartShareCentavos, 60000);
  });

  testWidgets('Create Tab creates a tab-only participant from one name',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final notifier = _notifierWithFriends();

    await tester.pumpWidget(_createTabHost(notifier));
    await tester.tap(find.text('Open Create Tab'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('create-tab-unregistered-name')),
      'Jordan Cruz',
    );
    await tester.tap(find.text('Add Person'));
    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('create-tab-amount')),
      '500.00',
    );
    await tester.ensureVisible(find.widgetWithText(TabbyButton, 'Create Tab'));
    await tester.tap(find.widgetWithText(TabbyButton, 'Create Tab'));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(find.text('Tab created'), findsOneWidget);
    final createdTab = notifier.state.tabs.firstWhere(
      (tab) => tab.counterpart.displayName == 'Jordan Cruz',
    );
    expect(createdTab.isTabOnlyParticipant, isTrue);
  });
}

Widget _createTabHost(TabbyNotifier notifier) {
  return ProviderScope(
    overrides: [tabbyProvider.overrideWith((_) => notifier)],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => AddExpenseModal.show(context),
            child: const Text('Open Create Tab'),
          ),
        ),
      ),
    ),
  );
}

TabbyNotifier _notifierWithFriends() {
  final notifier = TabbyNotifier();
  notifier.state = notifier.state.copyWith(
    tabs: [
      _friendTab('friend-alex', 'Alex Dela Cruz', 'TAB-7K4P2M'),
      _friendTab('friend-maria', 'Maria Santos', 'TAB-8L5Q3N'),
    ],
    friendRequests: const [],
  );
  return notifier;
}

BilateralTab _friendTab(String id, String name, String friendCode) {
  return BilateralTab(
    id: id,
    counterpart: TabbyUser(
      id: id,
      displayName: name,
      email: '$id@example.com',
      phone: '',
      friendCode: friendCode,
    ),
    netBalanceCentavos: 0,
    itemCount: 0,
    entries: const [],
    lastUpdated: DateTime(2026, 9, 17),
  );
}
