import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/main.dart';

void main() {
  group('shouldRenderDeviceFrame Responsive Logic', () {
    test('returns false when not running on Web', () {
      expect(
        shouldRenderDeviceFrame(
          isWeb: false,
          platform: TargetPlatform.windows,
          size: const Size(1920, 1080),
        ),
        isFalse,
      );
    });

    test('yields to full native screen on mobile browser platforms (iOS / Android)', () {
      // iPhone Safari
      expect(
        shouldRenderDeviceFrame(
          isWeb: true,
          platform: TargetPlatform.iOS,
          size: const Size(1920, 1080),
        ),
        isFalse,
      );

      // Android Chrome
      expect(
        shouldRenderDeviceFrame(
          isWeb: true,
          platform: TargetPlatform.android,
          size: const Size(1920, 1080),
        ),
        isFalse,
      );
    });

    test('yields to full native screen on narrow desktop browser windows (<= 500px)', () {
      expect(
        shouldRenderDeviceFrame(
          isWeb: true,
          platform: TargetPlatform.windows,
          size: const Size(430, 932),
        ),
        isFalse,
      );

      expect(
        shouldRenderDeviceFrame(
          isWeb: true,
          platform: TargetPlatform.macOS,
          size: const Size(500, 800),
        ),
        isFalse,
      );

      expect(
        shouldRenderDeviceFrame(
          isWeb: true,
          platform: TargetPlatform.linux,
          size: const Size(800, 480),
        ),
        isFalse,
      );
    });

    test('activates realistic iPhone frame on desktop web viewports (> 500px)', () {
      expect(
        shouldRenderDeviceFrame(
          isWeb: true,
          platform: TargetPlatform.windows,
          size: const Size(1280, 800),
        ),
        isTrue,
      );

      expect(
        shouldRenderDeviceFrame(
          isWeb: true,
          platform: TargetPlatform.macOS,
          size: const Size(1920, 1080),
        ),
        isTrue,
      );
    });
  });

  group('IPhoneDeviceFrameWrapper UI Components', () {
    testWidgets('renders iPhone hardware chassis, Dynamic Island, and Home Indicator', (tester) async {
      bool buttonPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: IPhoneDeviceFrameWrapper(
            child: Builder(
              builder: (context) {
                final mediaQuery = MediaQuery.of(context);
                return Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Screen: ${mediaQuery.size.width}x${mediaQuery.size.height}'),
                        Text('TopPadding: ${mediaQuery.padding.top}'),
                        Text('BottomPadding: ${mediaQuery.padding.bottom}'),
                        ElevatedButton(
                          onPressed: () => buttonPressed = true,
                          child: const Text('Tap Me Inside iPhone'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Dynamic Island and Home Indicator are rendered
      expect(find.byType(DynamicIslandWidget), findsOneWidget);
      expect(find.byType(IPhoneHomeIndicator), findsOneWidget);

      // Inner screen receives correct simulated iPhone dimensions and safe area insets
      expect(find.text('Screen: 380.0x800.0'), findsOneWidget);
      expect(find.text('TopPadding: 44.0'), findsOneWidget);
      expect(find.text('BottomPadding: 28.0'), findsOneWidget);

      // Test interactivity within the simulated screen
      await tester.tap(find.text('Tap Me Inside iPhone'));
      await tester.pumpAndSettle();
      expect(buttonPressed, isTrue);
    });

    testWidgets('DynamicIslandWidget dimensions, colors, and camera/speaker dots', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: DynamicIslandWidget(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final pillFinder = find.byType(DynamicIslandWidget);
      expect(pillFinder, findsOneWidget);

      final container = tester.widget<Container>(
        find.descendant(of: pillFinder, matching: find.byType(Container).first),
      );

      expect(container.constraints?.maxWidth, equals(105.0));
      expect(container.constraints?.maxHeight, equals(28.0));

      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, equals(const Color(0xFF000000)));
      expect(decoration.borderRadius, equals(BorderRadius.circular(20.0)));
    });

    testWidgets('IPhoneHomeIndicator dimensions and styling', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: IPhoneHomeIndicator(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final indicatorFinder = find.byType(IPhoneHomeIndicator);
      expect(indicatorFinder, findsOneWidget);

      final container = tester.widget<Container>(
        find.descendant(of: indicatorFinder, matching: find.byType(Container)),
      );

      expect(container.constraints?.maxWidth, equals(130.0));
      expect(container.constraints?.maxHeight, equals(4.0));
    });
  });
}
