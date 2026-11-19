import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabby/main.dart';

import 'package:tabby/core/config/app_state.dart';

void main() {
  testWidgets('TabbyApp boots up, displays dashboard, and navigates tabs',
      (tester) async {
    AppState.isAuthenticated.value = true;
    await tester.pumpWidget(
      const ProviderScope(
        child: TabbyApp(),
      ),
    );

    // Initial pump & settle
    await tester.pumpAndSettle();

    // Verify Home Dashboard header & greeting (without emojis)
    expect(find.text('Frienzal'), findsOneWidget);
    expect(find.text('NET BALANCE'), findsOneWidget);
    expect(find.text('Received'), findsOneWidget);
    expect(find.byKey(const ValueKey('navigation-create-tab')), findsOneWidget);

    // Tap on 'My Tabs' navigation item
    await tester.tap(find.byKey(const ValueKey('navigation-tab-my-tabs')));
    await tester.pumpAndSettle();

    // Verify My Tabs screen headers (one in top bar, one in bottom navigation)
    expect(find.text('My Tabs'), findsNWidgets(2));
    expect(find.text('No Active Tabs'), findsOneWidget);

    // Tap on 'Profile' navigation item
    await tester.tap(find.byKey(const ValueKey('navigation-tab-profile')));
    await tester.pumpAndSettle();

    // Verify Profile screen elements
    expect(find.text('Profile & Settings'), findsOneWidget);
    expect(find.text('Payment Methods'), findsOneWidget);
    expect(find.text('Manage Friends'), findsOneWidget);
    expect(find.text('Currency Precision'), findsNothing);
    expect(find.text('Appearance'), findsOneWidget);
  });
}
