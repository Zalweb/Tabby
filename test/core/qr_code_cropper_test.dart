import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/services/qr_code_cropper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QrCodeCropper Service', () {
    test('Correctly identifies and crops QR code from simulated screenshot', () async {
      // Create a 400x800 simulated mobile phone screenshot
      // with a 150x150 QR-like pattern in the center
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Background (e.g., GCash blue or phone interface)
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 400, 800),
        Paint()..color = const Color(0xFF005CE6),
      );

      // White card containing the QR code
      const qrCardRect = Rect.fromLTWH(75, 250, 250, 250);
      canvas.drawRect(
        qrCardRect,
        Paint()..color = Colors.white,
      );

      // Draw high-frequency QR-like pattern inside the white card
      final blackPaint = Paint()..color = Colors.black;
      for (int r = 0; r < 20; r++) {
        for (int c = 0; c < 20; c++) {
          if ((r + c) % 2 == 0) {
            canvas.drawRect(
              Rect.fromLTWH(100.0 + c * 10, 275.0 + r * 10, 10, 10),
              blackPaint,
            );
          }
        }
      }

      final picture = recorder.endRecording();
      final img = await picture.toImage(400, 800);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final sourceBytes = byteData!.buffer.asUint8List();

      final result = await QrCodeCropper.cropQrCode(sourceBytes);

      expect(result.wasCropped, isTrue);
      expect(result.originalWidth, 400);
      expect(result.originalHeight, 800);
      // The cropped image must be substantially smaller than the 800px tall screenshot
      expect(result.croppedHeight, lessThan(450));
      expect(result.croppedWidth, lessThan(450));
      // Aspect ratio of the cropped image should be nearly square (approx 1.0)
      final cropRatio = result.croppedWidth / result.croppedHeight;
      expect(cropRatio, closeTo(1.0, 0.25));
    });

    test('Leaves already-square standalone QR image uncropped', () async {
      // 200x200 square image
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 200, 200),
        Paint()..color = Colors.white,
      );

      // High-frequency pattern
      final blackPaint = Paint()..color = Colors.black;
      for (int i = 0; i < 15; i++) {
        for (int j = 0; j < 15; j++) {
          if ((i * j) % 2 == 0) {
            canvas.drawRect(
              Rect.fromLTWH(10.0 + i * 12, 10.0 + j * 12, 12, 12),
              blackPaint,
            );
          }
        }
      }

      final picture = recorder.endRecording();
      final img = await picture.toImage(200, 200);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final sourceBytes = byteData!.buffer.asUint8List();

      final result = await QrCodeCropper.cropQrCode(sourceBytes);

      // Should recognize it's already standalone and square
      expect(result.wasCropped, isFalse);
      expect(result.croppedWidth, 200);
      expect(result.croppedHeight, 200);
    });

    test('Processes user uploaded real-world InstaPay QR image', () async {
      final file = File(
          r'C:\Users\frien\.gemini\antigravity\brain\61c3c771-9c7f-47b2-90c6-a0e6cfcf2dc1\.user_uploaded\media_1790865435232.png');
      if (file.existsSync()) {
        final bytes = await file.readAsBytes();
        final format = QrCodeCropper.detectImageFormat(
          path: 'blob:http://localhost:8088/50785f78-b3ec-4eb0-a5fb-39cf9e504c55',
          name: 'media_1790865435232.png',
          bytes: bytes,
        );
        expect(format.isValid, isTrue);
        expect(format.extension, 'png');
        expect(format.mimeType, 'image/png');

        final result = await QrCodeCropper.cropQrCode(bytes);
        expect(result.bytes.isNotEmpty, isTrue);
        expect(result.croppedWidth, greaterThan(0));
        expect(result.croppedHeight, greaterThan(0));
      }
    });

    test('detectImageFormat correctly identifies images from Web blob URLs and binary headers', () {
      // 1. Web blob URL with PNG magic bytes
      final pngBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00]);
      final blobResult = QrCodeCropper.detectImageFormat(
        path: 'blob:http://localhost:8088/a348c47f-855c-4da8-963d-49520cb25d30',
        bytes: pngBytes,
      );
      expect(blobResult.isValid, isTrue);
      expect(blobResult.extension, 'png');

      // 2. JPEG magic bytes
      final jpgBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
      final jpgResult = QrCodeCropper.detectImageFormat(
        path: 'blob:http://localhost:8088/some-random-id',
        bytes: jpgBytes,
      );
      expect(jpgResult.isValid, isTrue);
      expect(jpgResult.extension, 'jpg');

      // 3. Invalid non-image data
      final textBytes = Uint8List.fromList('hello world text content'.codeUnits);
      final invalidResult = QrCodeCropper.detectImageFormat(
        path: 'blob:http://localhost:8088/some-text-file',
        bytes: textBytes,
      );
      expect(invalidResult.isValid, isFalse);
    });
  });
}
