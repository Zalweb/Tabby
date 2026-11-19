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
    bool disableAnimations = true,
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
              disableAnimations: disableAnimations,
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
          expect(
            tester.getRect(find.byType(WelcomeBackdrop)),
            Offset.zero & size,
          );
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
      expect(find.text('Get started'), findsOneWidget);
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
        final progress = tester.widget<WormPageIndicator>(
          find.byType(WormPageIndicator),
        );
        final activeLuminance = progress.indicatorColor.computeLuminance();
        final trackLuminance = progress.trackColor.computeLuminance();
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

  for (final size in [
    const Size(320, 568),
    const Size(568, 320),
    const Size(390, 844),
  ]) {
    testWidgets(
      'introduction content scrolls while controls stay reachable at $size / 200%',
      (tester) async {
        await open(
          tester,
          const OnboardingScreen(),
          size,
          scale: 2,
          dark: true,
        );
        final skip = find.text('Skip');
        final primary = find.byType(FilledButton);
        expect(skip.hitTestable(), findsOneWidget);
        expect(primary.hitTestable(), findsOneWidget);
        final skipRect = tester.getRect(skip);
        final primaryRect = tester.getRect(primary);

        final slideCopy = [
          'Hi, I’m Tabby — your friendly tab keeper. Add a shared meal or any cost you split, and I’ll keep a clear record of who paid and who owes what.',
          'Each tab keeps a running balance. Attach receipts to expenses so everyone on that tab can see the same record.',
          'Pay with your usual wallet, bank, or cash. Record it in Tabby. Your friend confirms when it arrives.',
        ];
        final titles = [
          'One tab for every friend.',
          'Balances and receipts, together.',
          'Settle up, stay friends.',
        ];

        for (var index = 0; index < titles.length; index++) {
          final pageBounds = tester.getRect(find.byType(PageView));
          for (final copy in [titles[index], slideCopy[index]]) {
            final text = find.text(copy);
            await tester.ensureVisible(text);
            expect(
              tester.getRect(text).top,
              greaterThanOrEqualTo(pageBounds.top - 0.1),
            );
            await Scrollable.ensureVisible(tester.element(text), alignment: 1);
            expect(
              tester.getRect(text).bottom,
              lessThanOrEqualTo(pageBounds.bottom + 0.1),
            );
          }
          expect(skip.hitTestable(), findsOneWidget);
          expect(primary.hitTestable(), findsOneWidget);
          expect(
            tester.getRect(skip).center.dy,
            closeTo(skipRect.center.dy, 0.1),
          );
          final currentButton = tester.getRect(primary);
          expect(currentButton.bottom, closeTo(primaryRect.bottom, 0.1));
          expect(currentButton.left, closeTo(primaryRect.left, 0.1));
          expect(currentButton.width, closeTo(primaryRect.width, 0.1));

          final indicator = tester.widget<WormPageIndicator>(
            find.byType(WormPageIndicator),
          );
          expect(indicator.step, index);
          expect(indicator.progress, index.toDouble());
          if (index < titles.length - 1) {
            await tester.tap(primary);
            await tester.pumpAndSettle();
          }
        }
        expect(find.text('Get started'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('indicator announces one step and hides offscreen slide text', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await open(tester, const OnboardingScreen(), const Size(390, 844));
      expect(find.bySemanticsLabel('Step 1 of 3'), findsOneWidget);
      expect(
        find.bySemanticsLabel('One tab for every friend.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Balances and receipts, together.'),
        findsNothing,
      );

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Step 2 of 3'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Balances and receipts, together.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('One tab for every friend.'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'interrupting Next keeps the CTA disabled until the pager returns to slide 2',
    (tester) async {
      await open(
        tester,
        const OnboardingScreen(),
        const Size(390, 844),
        disableAnimations: false,
      );
      final primary = find.byType(FilledButton);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Balances and receipts, together.'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final pageController = tester
          .widget<PageView>(find.byType(PageView))
          .controller!;
      expect(pageController.page!, greaterThan(1));
      expect(pageController.page!, lessThan(1.5));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(pageController.page!, inInclusiveRange(1, 1.5));
      expect(find.text('Get started'), findsNothing);
      expect(tester.widget<FilledButton>(primary).onPressed, isNull);

      await gesture.cancel();
      await tester.pumpAndSettle();

      expect(pageController.page!, closeTo(1, 0.001));
      expect(find.text('Balances and receipts, together.'), findsOneWidget);
      expect(find.text('Get started'), findsNothing);
      expect(tester.widget<FilledButton>(primary).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );
}
