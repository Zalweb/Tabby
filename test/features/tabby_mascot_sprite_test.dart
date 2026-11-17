import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/shared/widgets/tabby_mascot_sprite.dart';

void main() {
  Widget host({
    bool animate = true,
    bool reduced = false,
    bool visible = true,
    bool sleeping = false,
    double size = 96,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: TickerMode(
        enabled: visible,
        child: Center(
          child: SizedBox.square(
            dimension: size,
            child: TabbyMascotSprite(animate: animate, sleeping: sleeping),
          ),
        ),
      ),
    ),
  );

  TabbyMascotSpritePainter painter(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((widget) => widget.painter)
      .whereType<TabbyMascotSpritePainter>()
      .single;

  Future<void> load(WidgetTester tester, Widget widget) async {
    await tester.pumpWidget(widget);
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/branding/tabby-blink-sheet.png'),
        tester.element(find.byType(TabbyMascotSprite)),
      );
    });
    await tester.pump();
    expect(painter(tester).image.width, 1254);
  }

  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  testWidgets('real sprite holds open, plays eight frames, then loops', (
    tester,
  ) async {
    await load(tester, host());
    expect(painter(tester).frame, 0);
    await tester.pump(const Duration(milliseconds: 3199));
    expect(painter(tester).frame, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(painter(tester).frame, 1);
    for (final step in [
      (80, 2),
      (60, 3),
      (65, 4),
      (65, 5),
      (60, 6),
      (80, 7),
      (190, 0),
    ]) {
      await tester.pump(Duration(milliseconds: step.$1));
      expect(painter(tester).frame, step.$2);
    }
    await unmount(tester);
  });

  testWidgets('reduced motion interrupts a blink and stays open', (
    tester,
  ) async {
    await load(tester, host());
    await tester.pump(const Duration(milliseconds: 3200));
    await tester.pump(const Duration(milliseconds: 80));
    expect(painter(tester).frame, 2);
    await tester.pumpWidget(host(reduced: true));
    expect(painter(tester).frame, 0);
    await tester.pump(const Duration(seconds: 10));
    expect(painter(tester).frame, 0);
    await unmount(tester);
  });

  testWidgets('hidden route pauses and restarts with a full open-eye hold', (
    tester,
  ) async {
    await load(tester, host());
    await tester.pump(const Duration(milliseconds: 3200));
    await tester.pumpWidget(host(visible: false));
    await tester.pump(const Duration(seconds: 10));
    expect(painter(tester).frame, 0);
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 3199));
    expect(painter(tester).frame, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(painter(tester).frame, 1);
    await unmount(tester);
  });

  testWidgets('background lifecycle pauses and resumes playback', (
    tester,
  ) async {
    await load(tester, host());
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );
    await tester.pump(const Duration(seconds: 10));
    expect(painter(tester).frame, 0);
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pump(const Duration(milliseconds: 3200));
    expect(painter(tester).frame, 1);
    await unmount(tester);
  });

  testWidgets('sleeping uses closed eyes and waking starts open', (
    tester,
  ) async {
    await load(tester, host(sleeping: true));
    expect(painter(tester).frame, 3);
    await tester.pump(const Duration(seconds: 10));
    expect(painter(tester).frame, 3);
    await tester.pumpWidget(host());
    expect(painter(tester).frame, 0);
    await unmount(tester);
  });

  testWidgets('frames contain visible transparent artwork at app sizes', (
    tester,
  ) async {
    for (final size in [64.0, 128.0]) {
      await load(tester, host(animate: false, size: size));
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.descendant(
          of: find.byType(TabbyMascotSprite),
          matching: find.byType(RepaintBoundary),
        ),
      );
      final image = (await tester.runAsync(() => boundary.toImage()))!;
      final bytes = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      var opaque = 0;
      var transparent = 0;
      for (var i = 3; i < bytes.lengthInBytes; i += 4) {
        if (bytes.getUint8(i) > 240) opaque++;
        if (bytes.getUint8(i) == 0) transparent++;
      }
      expect(opaque, greaterThan(size * size * 0.2));
      expect(transparent, greaterThan(size * size * 0.1));
      image.dispose();
      await unmount(tester);
    }
    expect(tester.takeException(), isNull);
  });
}
