import 'package:tabby/shared/widgets/tabby_mascot_sprite.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/theme/tabby_colors.dart';
import 'package:tabby/core/theme/tabby_palette.dart';
import 'package:tabby/core/theme/tabby_theme.dart';
import 'package:tabby/features/auth/presentation/login_screen.dart';
import 'package:tabby/features/auth/presentation/complete_profile_screen.dart';
import 'package:tabby/features/onboarding/presentation/onboarding_screen.dart';
import 'package:tabby/features/home/presentation/home_dashboard_screen.dart';
import 'package:tabby/features/tabs/presentation/my_tabs_screen.dart';
import 'package:tabby/features/tabs/presentation/tab_detail_screen.dart';
import 'package:tabby/features/connections/presentation/connections_screen.dart';
import 'package:tabby/features/profile/presentation/profile_screen.dart';
import 'package:tabby/features/profile/presentation/privacy_controls_screen.dart';

import '../support/warm_design_fixture.dart';

double ratio(Color a, Color b) =>
    (math.max(a.computeLuminance(), b.computeLuminance()) + 0.05) /
    (math.min(a.computeLuminance(), b.computeLuminance()) + 0.05);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final dark in [false, true]) {
    final p = dark ? TabbyPalette.dark : TabbyPalette.light;
    final theme = dark ? TabbyTheme.darkTheme : TabbyTheme.lightTheme;
    test(
      '${dark ? 'dark' : 'light'} warm controls and text have readable contrast',
      () {
        for (final bg in [p.canvas, p.surface, p.soft, p.accentTint]) {
          for (final foreground in [p.text, p.secondaryText, p.link]) {
            expect(ratio(foreground, bg), greaterThanOrEqualTo(4.5));
          }
        }
        for (final bg in [p.canvas, p.surface, p.soft]) {
          expect(ratio(p.controlBorder, bg), greaterThanOrEqualTo(3));
        }
        expect(
          ratio(TabbyColors.brandInk, TabbyColors.brandAmber),
          greaterThanOrEqualTo(4.5),
        );
        expect(ratio(p.positiveText, p.successTint), greaterThanOrEqualTo(4.5));
        expect(ratio(p.errorText, p.errorTint), greaterThanOrEqualTo(4.5));
        expect(ratio(p.warningText, p.pendingTint), greaterThanOrEqualTo(4.5));
        final input = theme.inputDecorationTheme;
        expect(
          ratio(
            (input.focusedBorder! as OutlineInputBorder).borderSide.color,
            p.soft,
          ),
          greaterThanOrEqualTo(3),
        );
        expect(
          theme.elevatedButtonTheme.style!.foregroundColor!.resolve({}),
          TabbyColors.brandInk,
        );
        expect(
          theme.textButtonTheme.style!.foregroundColor!.resolve({}),
          p.link,
        );
        expect(theme.listTileTheme.selectedColor, p.link);
        expect(
          theme.outlinedButtonTheme.style!.textStyle!.resolve({})!.fontFamily,
          'Inter',
        );
        expect(
          theme.datePickerTheme.dayForegroundColor!.resolve({
            WidgetState.selected,
          }),
          TabbyColors.brandInk,
        );
      },
    );
    for (final entry in <String, Widget>{
      'login': const LoginScreen(),
      'introduction': const OnboardingScreen(),
      'setup': const CompleteProfileScreen(),
      'home': const HomeDashboardScreen(),
      'tabs': const MyTabsScreen(),
      'detail': const TabDetailScreen(tabId: 'warm-tab'),
      'connections': const ConnectionsScreen(),
      'profile': const ProfileScreen(),
      'privacy': const PrivacyControlsScreen(),
    }.entries) {
      testWidgets(
        '${entry.key} shares the ${dark ? 'dark' : 'light'} warm canvas',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(390, 844));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(warmHost(entry.value, dark: dark));
          await tester.pumpAndSettle();
          final scaffold = find.byType(Scaffold).first;
          final actual = tester.widget<Scaffold>(scaffold);
          expect(
            actual.backgroundColor ??
                Theme.of(tester.element(scaffold)).scaffoldBackgroundColor,
            p.canvas,
          );
          expect(tester.takeException(), isNull);
          if (entry.key == 'profile') {
            expect(
              DefaultTextStyle.of(tester.element(find.text('SF'))).style.color,
              TabbyColors.brandInk,
            );
            for (final control in tester.widgetList<Switch>(
              find.byType(Switch),
            )) {
              final thumb =
                  control.thumbColor?.resolve({WidgetState.selected}) ??
                  control.activeThumbColor ??
                  theme.switchTheme.thumbColor!.resolve({WidgetState.selected});
              expect(thumb, TabbyColors.brandInk);
            }
          }
          if (entry.key == 'home') {
            expect(
              tester.widget<Text>(find.text('This month')).style?.color,
              TabbyColors.brandInk,
            );
            expect(
              find.byKey(const ValueKey('mascot-art-notebook')),
              findsOneWidget,
            );
            expect(tester.widget<TabbyMascotSprite>(find.byType(TabbyMascotSprite)).asset,
                'assets/branding/tabby-notebook-v3.png');
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }
}
