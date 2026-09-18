import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tabby/features/connections/presentation/connections_screen.dart';

void main() {
  testWidgets('Connections keeps the emerald header and friend controls',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ConnectionsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connections'), findsOneWidget);
    expect(find.text('Friends'), findsOneWidget);
    expect(find.text('Add Friend'), findsOneWidget);
  });
}
