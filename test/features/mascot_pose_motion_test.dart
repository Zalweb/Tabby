import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:tabby/shared/widgets/tabby_mascot_art.dart';
import 'package:tabby/shared/widgets/tabby_mascot_sprite.dart';
import 'package:tabby/shared/widgets/tabby_mascot_widget.dart';

void main() {
  Widget host(
    TabbyMascotPose pose, {
    bool reduced = false,
    bool visible = true,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: TickerMode(
        enabled: visible,
        child: Scaffold(
          body: Center(
            child: TabbyMascotWidget.art(
              pose: pose,
              size: 120,
              animateAmbient: true,
            ),
          ),
        ),
      ),
    ),
  );
  List<double> matrix(WidgetTester tester) => tester
      .widget<Transform>(find.byKey(const ValueKey('mascot-motion')))
      .transform
      .storage
      .toList();
  Future<void> load(WidgetTester tester, Widget widget) async {
    await tester.pumpWidget(widget);
    final sprite = tester.widget<TabbyMascotSprite>(
      find.byType(TabbyMascotSprite).last,
    );
    await tester.runAsync(
      () => precacheImage(
        ResizeImage.resizeIfNeeded(
          sprite.decodeWidth,
          null,
          AssetImage(sprite.asset),
        ),
        tester.element(find.byType(TabbyMascotSprite).last),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'thinking uses the supplied thinking pose instead of the generic blink sheet',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TabbyMascotWidget(
              emotion: MascotEmotion.calculating,
              showBubble: false,
              size: 120,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mascot-art-thinking')), findsOneWidget);
      expect(
        tester.widget<TabbyMascotSprite>(find.byType(TabbyMascotSprite)).asset,
        endsWith('tabby-thinking.png'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'payment submitted waits and owing money remains neutral notebook art',
    () {
      expect(
        mascotPoseForEmotion(MascotEmotion.paymentSubmitted),
        TabbyMascotPose.waiting,
      );
      expect(
        mascotPoseForEmotion(MascotEmotion.userOwes),
        TabbyMascotPose.notebook,
      );
      expect(
        mascotPoseForEmotion(MascotEmotion.userIsOwed),
        TabbyMascotPose.notebook,
      );
      expect(
        mascotPoseForEmotion(MascotEmotion.overdue),
        TabbyMascotPose.reminder,
      );
    },
  );
  for (final pose in TabbyMascotPose.values) {
    testWidgets('$pose decodes real artwork and reduced motion stays static', (
      tester,
    ) async {
      await load(tester, host(pose, reduced: true));
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<TabbyMascotSpritePainter>()
          .single;
      expect(painter.image.width, greaterThan(0));
      final crop = MascotArtwork.specs[pose]!.normalizedSource;
      if (crop != null) {
        expect(crop.left, greaterThanOrEqualTo(0));
        expect(crop.top, greaterThanOrEqualTo(0));
        expect(crop.right, lessThanOrEqualTo(1));
        expect(crop.bottom, lessThanOrEqualTo(1));
        expect(painter.image.width, lessThanOrEqualTo(1024));
      }
      final initial = matrix(tester);
      expect(initial[13], 0);
      await tester.pump(const Duration(seconds: 5));
      expect(matrix(tester), initial);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('thinking loop moves, pauses offstage and resumes', (
    tester,
  ) async {
    await load(tester, host(TabbyMascotPose.thinking));
    await tester.pump(const Duration(milliseconds: 100));
    final before = matrix(tester);
    await tester.pump(const Duration(milliseconds: 250));
    expect(matrix(tester), isNot(before));
    await tester.pumpWidget(host(TabbyMascotPose.thinking, visible: false));
    await tester.pump();
    final paused = matrix(tester);
    await tester.pump(const Duration(seconds: 5));
    expect(matrix(tester), paused);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(host(TabbyMascotPose.thinking));
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('backgrounding stops body and blink and foreground resumes', (
    tester,
  ) async {
    await load(tester, host(TabbyMascotPose.neutral));
    await tester.pump(const Duration(milliseconds: 600));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    final paused = matrix(tester);
    await tester.pump(const Duration(seconds: 8));
    expect(matrix(tester), paused);
    expect(tester.binding.hasScheduledFrame, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('transparent modal pauses covered mascot and dismissal resumes', (
    tester,
  ) async {
    await load(tester, host(TabbyMascotPose.waiting));
    final context = tester.element(find.byType(TabbyMascotWidget));
    showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(title: Text('Covered')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final paused = matrix(tester);
    await tester.pump(const Duration(seconds: 4));
    expect(matrix(tester), paused);
    expect(tester.binding.hasScheduledFrame, isFalse);
    Navigator.of(tester.element(find.text('Covered'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'celebration finishes once and does not replay after rebuild or resume',
    (tester) async {
      await load(tester, host(TabbyMascotPose.celebrating));
      await tester.pump(const Duration(milliseconds: 150));
      expect(matrix(tester)[13], lessThan(0));
      await tester.pump(const Duration(seconds: 2));
      expect(matrix(tester)[13], 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(host(TabbyMascotPose.celebrating));
      await tester.pump(const Duration(milliseconds: 200));
      expect(matrix(tester)[13], 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 300));
      expect(matrix(tester)[13], 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'enabling reduced motion during a loop removes all movement immediately',
    (tester) async {
      await load(tester, host(TabbyMascotPose.reminder));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(host(TabbyMascotPose.reminder, reduced: true));
      await tester.pump();
      expect(matrix(tester)[13], 0);
      await tester.pump(const Duration(seconds: 5));
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
