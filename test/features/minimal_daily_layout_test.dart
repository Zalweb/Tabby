import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/theme/tabby_palette.dart';
import 'package:tabby/features/home/presentation/home_dashboard_screen.dart';
import 'package:tabby/features/profile/presentation/profile_screen.dart';
import 'package:tabby/shared/widgets/tabby_button.dart';

import '../support/warm_design_fixture.dart';
import '../support/daily_home_fixture.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final dark in [false, true]) {
    for (final size in [
      const Size(320, 568),
      const Size(568, 320),
      const Size(1280, 800),
    ]) {
      testWidgets(
        'daily Home $size ${dark ? 'dark' : 'light'} at200% keeps useful content reachable',
        (tester) async {
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            warmHost(
              HomeDashboardScreen(now: () => dailyFixtureNow),
              dark: dark,
              scale: 2,
              ledger: dailyHomeLedger,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('NET BALANCE'), findsOneWidget);
          expect(find.byKey(const ValueKey('home-net-amount')), findsOneWidget);
          expect(find.text('2 of 3 clear for you'), findsOneWidget);
          expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('home-received')))
                .data,
            '₱125.00',
          );
          expect(
            tester.widget<Text>(find.byKey(const ValueKey('home-paid'))).data,
            '₱0.00',
          );
          expect(find.text('Total You Owe'), findsNothing);
          await tester.ensureVisible(find.text('Recent Activity'));
          await tester.pumpAndSettle();
          expect(find.text('3 logs'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets(
      'appearance ${dark ? 'dark' : 'light'} has inset rounded choices and reachable save at200%',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 568));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          warmHost(const ProfileScreen(), dark: dark, scale: 2),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Appearance'));
        await tester.tap(find.text('Appearance'));
        await tester.pumpAndSettle();
        for (final label in ['Light mode', 'Dark mode']) {
          final tile = tester.widget<ListTile>(
            find.ancestor(
              of: find.text(label),
              matching: find.byType(ListTile),
            ),
          );
          final shape = tile.shape! as RoundedRectangleBorder;
          expect(shape.borderRadius, BorderRadius.circular(16));
          expect(
            tile.contentPadding,
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          );
          if (tile.selected) {
            expect(
              shape.side.color,
              dark ? TabbyPalette.dark.link : TabbyPalette.light.link,
            );
          }
        }
        await tester.ensureVisible(find.text('Dark mode'));
        await tester.tap(find.text('Dark mode'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ListTile>(
                find.ancestor(
                  of: find.text('Dark mode'),
                  matching: find.byType(ListTile),
                ),
              )
              .selected,
          isTrue,
        );
        expect(
          tester
              .widget<ListTile>(
                find.ancestor(
                  of: find.text('Light mode'),
                  matching: find.byType(ListTile),
                ),
              )
              .selected,
          isFalse,
        );
        final done = find.widgetWithText(TabbyButton, 'Done');
        await tester.ensureVisible(done);
        await tester.tap(done);
        await tester.pumpAndSettle();
        expect(find.text('Dark mode'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
