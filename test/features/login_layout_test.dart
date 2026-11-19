import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/theme/tabby_theme.dart';
import 'package:tabby/features/auth/presentation/auth_welcome_widgets.dart';
import 'package:tabby/features/auth/presentation/login_screen.dart';
import 'package:tabby/features/onboarding/presentation/onboarding_screen.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    Widget screen,
    Size size, {
    double scale = 1,
    bool dark = false,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: dark ? TabbyTheme.darkTheme : TabbyTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final size in [
    const Size(320, 568),
    const Size(568, 320),
    const Size(390, 844),
    const Size(1280, 800),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'Google-only welcome at $size / $scale keeps action reachable',
        (tester) async {
          await open(tester, const LoginScreen(), size, scale: scale);
          expect(find.byType(WelcomeMascot), findsOneWidget);
          expect(find.byType(TextField), findsNothing);
          expect(find.text('Create an account'), findsNothing);
          expect(find.text('Continue Offline'), findsNothing);
          expect(find.text('Continue with Apple'), findsNothing);
          await tester.ensureVisible(find.text('Continue with Google'));
          expect(
            find.text('Continue with Google').hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
  testWidgets(
    'Google-only entry dark mode and offline service error stay actionable',
    (tester) async {
      await open(tester, const LoginScreen(), const Size(390, 844), dark: true);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, const Color(0xFF181A19));
      await tester.ensureVisible(find.text('Continue with Google'));
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Authentication service is unavailable'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'introduction contains only real Tabby capabilities with minimal art',
    (tester) async {
      await open(tester, const OnboardingScreen(), const Size(390, 844));
      expect(find.text('One tab for every friend.'), findsOneWidget);
      for (final title in [
        'Balances and receipts, together.',
        'Settle up, stay friends.',
      ]) {
        await tester.ensureVisible(find.text('Next'));
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        expect(find.byType(WelcomeMascot), findsOneWidget);
        expect(find.byType(Icon), findsNothing);
      }
      expect(find.textContaining('Your friend confirms'), findsOneWidget);
      expect(find.text('Continue to sign in'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'intro controls remain aligned with readable progress in dark $dark',
      (tester) async {
        await open(
          tester,
          const OnboardingScreen(),
          const Size(390, 844),
          dark: dark,
        );
        final skip = find.text('Skip');
        final primary = find.byType(FilledButton);
        final originalSkip = tester.getRect(skip);
        final originalButton = tester.getRect(primary);
        final progress = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        final background = tester
            .widget<Scaffold>(find.byType(Scaffold))
            .backgroundColor!;
        final track = Color.alphaBlend(progress.backgroundColor!, background);
        final activeLuminance = progress.color!.computeLuminance();
        final trackLuminance = track.computeLuminance();
        final bright = activeLuminance > trackLuminance
            ? activeLuminance
            : trackLuminance;
        final dim = activeLuminance < trackLuminance
            ? activeLuminance
            : trackLuminance;
        expect((bright + 0.05) / (dim + 0.05), greaterThanOrEqualTo(3));
        for (final title in [
          'Balances and receipts, together.',
          'Settle up, stay friends.',
        ]) {
          await tester.tap(primary);
          await tester.pumpAndSettle();
          expect(find.text(title), findsOneWidget);
          expect(
            tester.getRect(skip).center.dy,
            closeTo(originalSkip.center.dy, 0.1),
          );
          final button = tester.getRect(primary);
          expect(button.bottom, closeTo(originalButton.bottom, 0.1));
          expect(button.left, closeTo(originalButton.left, 0.1));
          expect(button.width, closeTo(originalButton.width, 0.1));
          expect(button.height, greaterThanOrEqualTo(54));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
