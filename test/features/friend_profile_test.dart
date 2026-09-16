import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabby/core/config/app_state.dart';
import 'package:tabby/core/router/app_router.dart';
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
    expect(find.text('Connect by Tabby ID'), findsOneWidget);

    await tester.tap(find.text('Connect by Tabby ID'));
    await tester.pumpAndSettle();

    expect(find.text('Connect with a Friend'), findsOneWidget);
    expect(find.text('Tabby ID'), findsOneWidget);
    expect(find.text('Send Friend Request'), findsNothing);
  });

  testWidgets('Connect by Tabby ID rejects malformed codes before lookup',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    appRouter.go('/profile');
    await tester.pumpWidget(const ProviderScope(child: TabbyApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect by Tabby ID'));
    await tester.pumpAndSettle();

    final idField = find.widgetWithText(TextField, 'TAB-7K4P2M');
    await tester.enterText(idField, 'TAB-123');
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid Tabby ID such as TAB-7K4P2M.'),
        findsOneWidget);
    expect(find.text('Send Friend Request'), findsNothing);
  });
}
