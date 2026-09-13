import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabby/main.dart';

void main() {
  testWidgets('TabbyApp boots up, displays dashboard, and navigates tabs', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: TabbyApp(),
      ),
    );

    // Initial pump & settle
    await tester.pumpAndSettle();

    // Verify Home Dashboard header & greeting
    expect(find.text('Frienzal 👋'), findsOneWidget);
    expect(find.text('YOU OWE'), findsOneWidget);
    expect(find.text("YOU'RE OWED"), findsOneWidget);
    expect(find.text('Log Expense'), findsOneWidget);

    // Tap on 'My Tabs' navigation item
    await tester.tap(find.text('My Tabs'));
    await tester.pumpAndSettle();

    // Verify My Tabs screen headers (one in AppBar, one in BottomNavigationBar)
    expect(find.text('My Tabs'), findsNWidgets(2));
    expect(find.textContaining('THEY OWE YOU'), findsOneWidget);
    expect(find.textContaining('YOU OWE'), findsOneWidget);

    // Tap on 'Profile' navigation item
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    // Verify Profile screen elements
    expect(find.text('Profile & Settings'), findsOneWidget);
    expect(find.text('My Payment QR Ph'), findsOneWidget);
    expect(find.text('Currency Precision'), findsOneWidget);
  });
}
