import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/widgets/startup_gate.dart';

void main() {
  const app = MaterialApp(home: Text('Application ready'));
  testWidgets('renders immediately and retries failed auth initialization',
      (tester) async {
    final attempt = Completer<List<String>>();
    var calls = 0;
    await tester.pumpWidget(StartupGate(
        initialize: () {
          calls++;
          return calls == 1 ? attempt.future : Future.value([]);
        },
        child: app));
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
    'Profile refresh'
  ]) {
    testWidgets('$failure failure allows continuation', (tester) async {
      await tester.pumpWidget(StartupGate(
          initialize: () async => ['$failure unavailable'], child: app));
      await tester.pumpAndSettle();
      expect(find.text('$failure unavailable'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Application ready'), findsOneWidget);
    });
  }
}
