import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/theme/tabby_colors.dart';
import 'package:tabby/features/profile/presentation/profile_screen.dart';

void main() {
  testWidgets('Profile uses the approved grouped settings arrangement',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: ProfileScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      TabbyColors.brandEmerald,
    );
    expect(find.text('Profile & Settings'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Payment Methods'), findsOneWidget);
    expect(find.text('Manage Friends'), findsOneWidget);
    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Data & Support'), findsOneWidget);
    expect(find.text('Sync & Offline'), findsOneWidget);
    expect(find.text('About Tabby'), findsOneWidget);
    expect(find.text('Log Out'), findsOneWidget);
  });

  testWidgets(
      'Profile keeps the identity actions visible in the compact header',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: ProfileScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Frienzal'), findsOneWidget);
    expect(find.textContaining('TAB-'), findsOneWidget);
    expect(find.text('Edit Profile'), findsOneWidget);
  });
}
