import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/shared/widgets/tabby_mascot_art.dart';
import 'package:tabby/shared/widgets/tabby_mascot_frame_sheet.dart';
import 'package:tabby/shared/widgets/tabby_mascot_sprite.dart';

void main() {
  Widget scene(
    String pose, {
    bool reduced = false,
    bool visible = true,
    MascotFrameSheet? override,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: TickerMode(
        enabled: visible,
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              height: 120,
              child: TabbyMascotSprite(
                animate: true,
                asset: MascotArtwork
                    .specs[TabbyMascotPose.values.byName(pose)]!
                    .asset,
                normalizedSource: MascotArtwork
                    .specs[TabbyMascotPose.values.byName(pose)]!
                    .normalizedSource,
                frameSheet: override ?? mascotFrameSheets[pose],
                sheetDecodeWidth: 768,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  TabbyMascotSpritePainter painter(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((w) => w.painter)
      .whereType<TabbyMascotSpritePainter>()
      .single;
  Future<void> load(WidgetTester tester, String pose) async {
    await tester.pumpWidget(scene(pose));
    final context = tester.element(find.byType(TabbyMascotSprite));
    final sheet = mascotFrameSheets[pose]!;
    await tester.runAsync(() async {
      await precacheImage(
        AssetImage(
          MascotArtwork.specs[TabbyMascotPose.values.byName(pose)]!.asset,
        ),
        context,
      );
      await precacheImage(
        ResizeImage.resizeIfNeeded(768, null, AssetImage(sheet.asset)),
        context,
      );
    });
    await tester.pump();
  }

  for (final pose in mascotFrameSheets.keys) {
    testWidgets(
      '$pose loads actual transparent atlas with stable frame windows',
      (tester) async {
        await load(tester, pose);
        final sheet = mascotFrameSheets[pose]!;
        expect(painter(tester).normalizedSource, sheet.sources.first);
        expect(painter(tester).image.width, 768);
        for (final source in sheet.sources) {
          expect(source.width, closeTo(sheet.sources.first.width, 1e-8));
          expect(source.height, closeTo(sheet.sources.first.height, 1e-8));
          expect(source.left, greaterThanOrEqualTo(0));
          expect(source.top, greaterThanOrEqualTo(0));
          expect(source.right, lessThanOrEqualTo(1));
          expect(source.bottom, lessThanOrEqualTo(1));
        }
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'blink, tail and wave advance actual source rectangles after quiet holds',
    (tester) async {
      await load(tester, 'reminder');
      final sheet = mascotFrameSheets['reminder']!;
      expect(painter(tester).frame, 0);
      await tester.pump(const Duration(milliseconds: 3199));
      expect(painter(tester).frame, 0);
      for (var i = 0; i < sheet.steps.length - 1; i++) {
        await tester.pump(
          Duration(milliseconds: i == 0 ? 1 : sheet.steps[i].milliseconds),
        );
        expect(painter(tester).frame, sheet.steps[i + 1].frame);
        expect(
          painter(tester).normalizedSource,
          sheet.sources[sheet.steps[i + 1].frame],
        );
      }
      expect(
        sheet.steps.map((s) => s.frame),
        containsAll([1, 2, 3, 5, 7, 9, 11]),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'reduced motion replaces atlas with approved original and never advances',
    (tester) async {
      await load(tester, 'waiting');
      await tester.pump(const Duration(milliseconds: 3200));
      expect(painter(tester).frame, 1);
      await tester.pumpWidget(scene('waiting', reduced: true));
      final still = painter(tester);
      expect(
        still.normalizedSource,
        MascotArtwork.specs[TabbyMascotPose.waiting]!.normalizedSource,
      );
      await tester.pump(const Duration(seconds: 30));
      expect(painter(tester).frame, 0);
      expect(painter(tester).image, still.image);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'offstage and background suspend frame playback and resume from a quiet rest',
    (tester) async {
      await load(tester, 'thinking');
      await tester.pump(const Duration(milliseconds: 3200));
      expect(painter(tester).frame, 1);
      await tester.pumpWidget(scene('thinking', visible: false));
      await tester.pump(const Duration(seconds: 30));
      expect(painter(tester).frame, 0);
      await tester.pumpWidget(scene('thinking'));
      await tester.pump(const Duration(milliseconds: 3200));
      expect(painter(tester).frame, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 30));
      // Paused Flutter does not paint a new frame; the last rendered blink is
      // frozen. The canceled timer must not consume hidden elapsed time.
      expect(painter(tester).frame, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(painter(tester).frame, 0);
      await tester.pump(const Duration(milliseconds: 3200));
      expect(painter(tester).frame, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'celebration gestures finish once and never replay on rebuild or resume',
    (tester) async {
      await load(tester, 'celebrating');
      final steps = mascotFrameSheets['celebrating']!.steps;
      for (final step in steps) {
        await tester.pump(Duration(milliseconds: step.milliseconds));
      }
      expect(painter(tester).frame, 0);
      await tester.pumpWidget(scene('celebrating'));
      await tester.pump(const Duration(milliseconds: 120));
      expect(painter(tester).frame, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 120));
      expect(painter(tester).frame, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('interrupting a success gesture never replays it later', (
    tester,
  ) async {
    await load(tester, 'celebrating');
    await tester.pump(const Duration(milliseconds: 120));
    expect(painter(tester).frame, 9);
    await tester.pumpWidget(scene('celebrating', reduced: true));
    await tester.pumpWidget(scene('celebrating'));
    await tester.pump(const Duration(milliseconds: 120));
    expect(painter(tester).frame, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'missing sheet keeps original pose and reports no uncaught image error',
    (tester) async {
      const broken = MascotFrameSheet('assets/branding/mascot/missing.png', [
        Rect.fromLTWH(0, 0, 1, 1),
      ]);
      await tester.pumpWidget(scene('waiting', override: broken));
      final context = tester.element(find.byType(TabbyMascotSprite));
      await tester.runAsync(() async {
        await precacheImage(
          const AssetImage('assets/branding/mascot/tabby-waiting.png'),
          context,
        );
        await precacheImage(
          ResizeImage.resizeIfNeeded(
            768,
            null,
            const AssetImage('assets/branding/mascot/missing.png'),
          ),
          context,
          onError: (_, _) {},
        );
      });
      await tester.pump();
      expect(
        painter(tester).normalizedSource,
        MascotArtwork.specs[TabbyMascotPose.waiting]!.normalizedSource,
      );
      await tester.pump(const Duration(seconds: 20));
      expect(painter(tester).frame, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
