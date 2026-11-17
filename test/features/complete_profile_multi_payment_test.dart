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
    AppState.profileCompletionRequired.value = true;
  });
  testWidgets(
      'setup requires explicit receiving details and preserves a failed save',
      (tester) async {
    appRouter.go('/complete-profile');
    await tester.pumpWidget(const ProviderScope(child: TabbyApp()));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Full name'), 'Synthetic account');
    await tester.enterText(
        find.widgetWithText(TextField, 'Mobile number'), '+63 918 123 4567');
    await tester.ensureVisible(find.text('Save and continue'));
    await tester.tap(find.text('Save and continue'));
    await tester.pumpAndSettle();
    expect(find.text('How friends pay you'), findsOneWidget);
    expect(find.text('GCash'), findsNothing);
    expect(find.text('Preferred'), findsNothing);
    await tester.ensureVisible(find.text('+ Add Another Payment Method'));
    await tester.tap(find.text('+ Add Another Payment Method'));
    await tester.pumpAndSettle();
    expect(find.text('Generate QR from Number'), findsNothing);
    expect(find.text('Upload wallet QR image'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maya').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Payment method name'),
        'Synthetic Maya');
    await tester.enterText(
        find.widgetWithText(TextField, 'Account number or note'),
        '09998887766');
    await tester.ensureVisible(find.text('Add to setup'));
    await tester.tap(find.text('Add to setup'));
    await tester.pumpAndSettle();
    expect(
        find.text('Confirm these are your receiving details.'), findsOneWidget);
    await tester.ensureVisible(find.text('These are my receiving details'));
    await tester.tap(find.text('These are my receiving details'));
    await tester.ensureVisible(find.text('Add to setup'));
    await tester.tap(find.text('Add to setup'));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic Maya'), findsOneWidget);
    expect(find.text('Ready to save'), findsOneWidget);
    expect(find.text('GCash'), findsNothing);
    await tester.ensureVisible(find.text('Complete Setup and Start'));
    await tester.tap(find.text('Complete Setup and Start'));
    await tester.pumpAndSettle();
    expect(find.text('Retry Unsaved Methods'), findsOneWidget);
    expect(find.textContaining('Save not acknowledged'), findsOneWidget);
    expect(find.textContaining('Some receiving methods'), findsOneWidget);
    expect(AppState.profileCompletionRequired.value, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
