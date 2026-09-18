import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:tabby/features/tabs/presentation/my_tabs_screen.dart';

void main() {
  testWidgets('My Tabs uses the reference segmented layout', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tabbyProvider.overrideWith(
            (ref) => TabbyNotifier(loadInitialData: false),
          ),
        ],
        child: const MaterialApp(home: MyTabsScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Create Tab'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Groups'), findsOneWidget);
    expect(find.text('Active Tabs'), findsOneWidget);
    expect(find.text('Total Balance'), findsNothing);
  });

  testWidgets('My Tabs cards show tab details and Open action', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tabbyProvider.overrideWith(
            (ref) => TabbyNotifier(loadInitialData: false),
          ),
        ],
        child: const MaterialApp(home: MyTabsScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MyTabsScreen)),
    );
    unawaited(container.read(tabbyProvider.notifier).addExpense(
          counterpartId: 'user-alex',
          counterpartName: 'Alex Dela Cruz',
          title: 'Dinner with Friends',
          totalAmountCentavos: 40000,
          category: ExpenseCategory.food,
          paidByMe: true,
          isEqualSplit: true,
        ));
    expect(container.read(tabbyProvider).tabs, isNotEmpty);
    expect(container.read(filteredTabsProvider), isNotEmpty);
    expect(container.read(filteredTabsProvider).first.netBalanceCentavos,
        isNot(equals(0)));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Active Tabs'), findsOneWidget);
    expect(find.text('Alex Dela Cruz'), findsOneWidget);
    expect(find.textContaining('2 people'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
  });
}
