import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tabby/core/theme/tabby_theme.dart';
import 'package:tabby/features/tabs/data/ledger_storage_factory_native.dart';
import 'package:tabby/shared/widgets/tabby_mascot_art.dart';
import 'package:tabby/shared/widgets/tabby_mascot_sprite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'iOS native QR channel registers save/share and rejects malformed data',
    (tester) async {
      expect(
        Platform.isIOS,
        isTrue,
        reason: 'This is an iOS native test, not a host mock.',
      );
      const channel = MethodChannel('tabby/receiving_qr');
      final capabilities = await channel.invokeMapMethod<String, dynamic>(
        'capabilities',
      );
      expect(capabilities, {'save': true, 'share': true, 'platform': 'ios'});
      await expectLater(
        channel.invokeMethod<bool>('save', {
          'bytes': Uint8List.fromList([1, 2, 3]),
        }),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'invalid_image',
          ),
        ),
      );
    },
  );
  testWidgets(
    'iOS native Keychain and encrypted SQLite persist synthetic cache',
    (tester) async {
      expect(Platform.isIOS, isTrue);
      final directory = await Directory.systemTemp.createTemp('tabby-ios-ci-');
      final first = NativeLedgerCacheStorage(directory: () async => directory);
      final key = 'ios-ci-${DateTime.now().microsecondsSinceEpoch}';
      const value = 'synthetic-ios-encrypted-storage-only';
      try {
        await first.write(key: key, value: value);
        expect(await first.read(key: key), value);
        await first.close();
        final reopened = NativeLedgerCacheStorage(
          directory: () async => directory,
        );
        try {
          expect(await reopened.read(key: key), value);
          final bytes = await File('${directory.path}/tabby-ledger-v1.sqlite')
              .readAsBytes();
          expect(
            String.fromCharCodes(bytes.take(16)),
            isNot(startsWith('SQLite format 3')),
          );
          expect(String.fromCharCodes(bytes), isNot(contains(value)));
          await reopened.removeValue(key: key);
        } finally {
          await reopened.close();
        }
      } finally {
        await first.close();
        await directory.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'iOS decodes all generated mascot sheets and reduced motion uses original',
    (tester) async {
      for (final pose in [
        TabbyMascotPose.thinking,
        TabbyMascotPose.waiting,
        TabbyMascotPose.helpful,
        TabbyMascotPose.reminder,
        TabbyMascotPose.celebrating,
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: TabbyTheme.lightTheme,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 160,
                  height: 160,
                  child: TabbyMascotArt(pose: pose, animate: true, size: 160),
                ),
              ),
            ),
          ),
        );
        final element = tester.element(find.byType(TabbyMascotSprite));
        final sprite = element.widget as TabbyMascotSprite;
        await precacheImage(
          ResizeImage.resizeIfNeeded(
            sprite.sheetDecodeWidth,
            null,
            AssetImage(sprite.frameSheet!.asset),
          ),
          element,
        );
        await tester.pump();
        final painter = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((w) => w.painter)
            .whereType<TabbyMascotSpritePainter>()
            .single;
        expect(sprite.frameSheet!.sources, contains(painter.normalizedSource));
        await tester.pumpWidget(const SizedBox.shrink());
      }
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 160,
                  height: 160,
                  child: TabbyMascotArt(
                    pose: TabbyMascotPose.waiting,
                    animate: true,
                    size: 160,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final element = tester.element(find.byType(TabbyMascotSprite));
      final sprite = element.widget as TabbyMascotSprite;
      await precacheImage(
        ResizeImage.resizeIfNeeded(
          sprite.decodeWidth,
          null,
          AssetImage(sprite.asset),
        ),
        element,
      );
      await tester.pump();
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<TabbyMascotSpritePainter>()
          .single;
      expect(
        painter.normalizedSource,
        MascotArtwork.specs[TabbyMascotPose.waiting]!.normalizedSource,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
