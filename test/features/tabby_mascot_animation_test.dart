import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:tabby/shared/widgets/tabby_mascot_widget.dart';

void main() {
  group('TabbyMascotWidget Animation and Emotion Engine', () {
    testWidgets('Renders properly for all 9 MascotEmotion states without errors',
        (tester) async {
      for (final emotion in MascotEmotion.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: TabbyMascotWidget(
                  emotion: emotion,
                  size: 80,
                  showBubble: true,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.text('Tabby'), findsOneWidget);
        expect(find.text(emotion.stateKey), findsOneWidget);
        expect(find.text(emotion.microcopy), findsOneWidget);
        expect(find.byIcon(emotion.icon), findsOneWidget);
      }
    });

    testWidgets('Smoothly transitions between emotions and updates speech bubble',
        (tester) async {
      var currentEmotion = MascotEmotion.idleNeutral;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: Center(
                  child: Column(
                    children: [
                      TabbyMascotWidget(
                        emotion: currentEmotion,
                        size: 72,
                        showBubble: true,
                      ),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            currentEmotion = MascotEmotion.celebrating;
                          });
                        },
                        child: const Text('Celebrate'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('IDLE_NEUTRAL'), findsOneWidget);

      // Tap to trigger emotion transition
      await tester.tap(find.text('Celebrate'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('CELEBRATING'), findsOneWidget);
    });

    testWidgets('Responds to interactive tap gestures', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TabbyMascotWidget(
                emotion: MascotEmotion.idleNeutral,
                size: 80,
                showBubble: false,
                onTap: () {
                  tapped = true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // Tap the mascot
      await tester.tap(find.byType(TabbyMascotWidget));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('Displays custom message override correctly', (tester) async {
      const customMsg = 'Custom companion message for testing';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: TabbyMascotWidget(
                emotion: MascotEmotion.calculating,
                customMessage: customMsg,
                showBubble: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text(customMsg), findsOneWidget);
      expect(find.text('CALCULATING'), findsOneWidget);
    });
  });
}
