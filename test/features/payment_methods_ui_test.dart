import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/profile/presentation/profile_screen.dart';

void main() {
  testWidgets('Profile opens the multiple payment-method manager',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Payment Methods'));
    await tester.pumpAndSettle();

    expect(find.text('Payment Methods'), findsWidgets);
    expect(find.text('Add Payment Method'), findsOneWidget);
    expect(find.text('Preferred'), findsOneWidget);
  });
}
