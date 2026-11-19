import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/widgets/startup_gate.dart';
import 'package:tabby/shared/widgets/tabby_loading_indicator.dart';

void main() {
  const app = MaterialApp(home: Text('Application ready'));
  const motionKey = ValueKey('tabby-loading-mascot-motion');

  testWidgets('renders immediately and retries failed auth initialization', (
    tester,
  ) async {
    final attempt = Completer<List<String>>();
    var calls = 0;
    await tester.pumpWidget(
      StartupGate(
        initialize: () {
          calls++;
          return calls == 1 ? attempt.future : Future.value([]);
        },
        child: app,
      ),
    );
    expect(find.text('Starting Tabby…'), findsOneWidget);
    attempt.completeError(StateError('Auth unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Application ready'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Application ready'), findsOneWidget);
  });

  for (final failure in [
    'Saved preferences',
    'Notifications',
    'Profile refresh',
  ]) {
    testWidgets('$failure failure allows continuation', (tester) async {
      await tester.pumpWidget(
        StartupGate(
          initialize: () async => ['$failure unavailable'],
          child: app,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('$failure unavailable'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Application ready'), findsOneWidget);
    });
  }

  testWidgets(
    'animateOpening shows visible motion on a fast launch then routes',
    (tester) async {
      await tester.pumpWidget(
        StartupGate(
          initialize: () async => <String>[],
          animateOpening: true,
          child: app,
        ),
      );
      // The first rendered frame holds the bounded reveal with the startup loader.
      expect(find.byType(TabbyLoadingIndicator), findsOneWidget);
      expect(find.text('Application ready'), findsNothing);
      expect(find.byKey(motionKey), findsOneWidget);
      final first = tester.widget<Transform>(find.byKey(motionKey)).transform;
      await tester.pump(const Duration(milliseconds: 160));
      final second = tester.widget<Transform>(find.byKey(motionKey)).transform;
      // Motion is actually visible inside the bounded hold.
      expect(second.storage.toList(), isNot(first.storage.toList()));
      expect(find.text('Application ready'), findsNothing);
      // Past the 400 ms hold (within the 420 ms budget) the app routes terminally.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('Application ready'), findsOneWidget);
      expect(find.byType(TabbyLoadingIndicator), findsNothing);
    },
  );

  testWidgets('slow initialization keeps the loader with no extra hold', (
    tester,
  ) async {
    final attempt = Completer<List<String>>();
    await tester.pumpWidget(
      StartupGate(
        initialize: () => attempt.future,
        animateOpening: true,
        child: app,
      ),
    );
    expect(find.byType(TabbyLoadingIndicator), findsOneWidget);
    // The bounded reveal ends while initialization is still pending; the real
    // startup loader remains and adds no minimum hold of its own.
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byType(TabbyLoadingIndicator), findsOneWidget);
    expect(find.text('Application ready'), findsNothing);
    expect(find.text('Try again'), findsNothing);
    attempt.complete(<String>[]);
    await tester.pumpAndSettle();
    expect(find.text('Application ready'), findsOneWidget);
  });

  testWidgets('initial error and retry yield immediately with animateOpening', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      StartupGate(
        initialize: () {
          calls++;
          return calls == 1
              ? Future<List<String>>.error(StateError('Auth unavailable'))
              : Future.value(<String>[]);
        },
        animateOpening: true,
        child: app,
      ),
    );
    await tester.pump();
    // Errors never wait for the opening hold.
    expect(
      find.text('Tabby couldn’t start. Please try again.'),
      findsOneWidget,
    );
    expect(find.byType(TabbyLoadingIndicator), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Application ready'), findsOneWidget);
  });

  testWidgets('system reduced motion skips the opening hold', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(
      StartupGate(
        initialize: () async => <String>[],
        animateOpening: true,
        child: app,
      ),
    );
    await tester.pumpAndSettle();
    // No bounded hold: a clean fast launch routes straight to the app.
    expect(find.text('Application ready'), findsOneWidget);
    expect(find.byType(TabbyLoadingIndicator), findsNothing);
  });
}
