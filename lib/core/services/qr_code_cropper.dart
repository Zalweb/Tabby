import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

/// Result of an automated QR code detection and crop operation.
class QrCropResult {
  const QrCropResult({
    required this.bytes,
    required this.wasCropped,
    required this.originalWidth,
    required this.originalHeight,
    required this.croppedWidth,
    required this.croppedHeight,
    this.boundingBox,
    required this.message,
  });

  /// Output image bytes (PNG if cropped, or original bytes if uncropped).
  final Uint8List bytes;

  /// True if a QR code region was detected and cropped out of a larger image.
  final bool wasCropped;

  /// Width of the source image before cropping.
  final int originalWidth;

  /// Height of the source image before cropping.
  final int originalHeight;

  /// Width of the resulting cropped image.
  final int croppedWidth;

  /// Height of the resulting cropped image.
  final int croppedHeight;

  /// Bounding rectangle in the original image coordinate space.
  final ui.Rect? boundingBox;

  /// User-friendly explanation of the crop outcome.
  final String message;
}

/// Information about an identified image format.
class ImageFormatInfo {
  final bool isValid;
  final String extension;
  final String mimeType;

  const ImageFormatInfo({
    required this.isValid,
    required this.extension,
    required this.mimeType,
  });
}

/// Native Dart image processor that detects and isolates QR codes from screenshots
/// (e.g., GCash, Maya, SeaBank, BDO, and QR Ph screenshots) by removing status bars,
/// app headers, navigation banners, and buttons.
class QrCodeCropper {
  QrCodeCropper._();

  /// Inspects uploaded file metadata and raw image bytes to reliably identify
  /// image formats across Web (blob URLs), iOS, Android, and desktop.
  static ImageFormatInfo detectImageFormat({
    String? path,
    String? name,
    String? mimeType,
    required Uint8List bytes,
  }) {
    // 1. Check binary magic bytes
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return const ImageFormatInfo(
          isValid: true, extension: 'png', mimeType: 'image/png');
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return const ImageFormatInfo(
          isValid: true, extension: 'jpg', mimeType: 'image/jpeg');
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return const ImageFormatInfo(
          isValid: true, extension: 'webp', mimeType: 'image/webp');
    }
    if (bytes.length >= 12 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      return const ImageFormatInfo(
          isValid: true, extension: 'heic', mimeType: 'image/heic');
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return const ImageFormatInfo(
          isValid: true, extension: 'gif', mimeType: 'image/gif');
    }

    // 2. Check MIME type
    final mime = (mimeType ?? '').toLowerCase();
    if (mime.contains('png')) {
      return const ImageFormatInfo(
          isValid: true, extension: 'png', mimeType: 'image/png');
    }
    if (mime.contains('jpeg') || mime.contains('jpg')) {
      return const ImageFormatInfo(
          isValid: true, extension: 'jpg', mimeType: 'image/jpeg');
    }
    if (mime.contains('webp')) {
      return const ImageFormatInfo(
          isValid: true, extension: 'webp', mimeType: 'image/webp');
    }
    if (mime.contains('heic') || mime.contains('heif')) {
      return const ImageFormatInfo(
          isValid: true, extension: 'heic', mimeType: 'image/heic');
    }

    // 3. Check filename or path extension
    for (final candidate in [name, path]) {
      if (candidate != null && candidate.contains('.')) {
        final ext = candidate.split('.').last.toLowerCase();
        if (ext == 'png') {
          return const ImageFormatInfo(
              isValid: true, extension: 'png', mimeType: 'image/png');
        }
        if (ext == 'jpg' || ext == 'jpeg') {
          return const ImageFormatInfo(
              isValid: true, extension: 'jpg', mimeType: 'image/jpeg');
        }
        if (ext == 'webp') {
          return const ImageFormatInfo(
              isValid: true, extension: 'webp', mimeType: 'image/webp');
        }
        if (ext == 'heic' || ext == 'heif') {
          return const ImageFormatInfo(
              isValid: true, extension: 'heic', mimeType: 'image/heic');
        }
      }
    }

    return const ImageFormatInfo(isValid: false, extension: '', mimeType: '');
  }

  /// Analyzes [imageBytes], locates the central QR code square, and returns a
  /// clean cropped square image with an optimal quiet-zone border.
  static Future<QrCropResult> cropQrCode(Uint8List imageBytes) async {
    try {
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final uiImage = frame.image;

      final width = uiImage.width;
      final height = uiImage.height;

      if (width < 60 || height < 60) {
        return QrCropResult(
          bytes: imageBytes,
          wasCropped: false,
          originalWidth: width,
          originalHeight: height,
          croppedWidth: width,
          croppedHeight: height,
          message: 'Image is too small for QR extraction.',
        );
      }

      // If the image is already square (aspect ratio between 0.95 and 1.05),
      // it's likely already a standalone QR code image.
      final aspectRatio = width / height;
      final isAlreadySquare = aspectRatio >= 0.94 && aspectRatio <= 1.06;

      final byteData =
          await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) {
        return QrCropResult(
          bytes: imageBytes,
          wasCropped: false,
          originalWidth: width,
          originalHeight: height,
          croppedWidth: width,
          croppedHeight: height,
          message: 'Could not extract pixel data.',
        );
      }

      final pixels = byteData.buffer.asUint8List();

      // Step 1: Attempt Finder Pattern Detection (1:1:3:1:1 ratio)
      final finderBox = _detectByFinderPatterns(pixels, width, height);

      // Step 2: Fallback to high-frequency edge transition density cluster
      final densityBox = finderBox ?? _detectByTransitionDensity(pixels, width, height);

      final detectedBox = finderBox ?? densityBox;

      if (detectedBox == null) {
        return QrCropResult(
          bytes: imageBytes,
          wasCropped: false,
          originalWidth: width,
          originalHeight: height,
          croppedWidth: width,
          croppedHeight: height,
          message: isAlreadySquare
              ? 'QR code is already standalone and square.'
              : 'No distinct QR pattern detected. Full image preserved.',
        );
      }

      // Check if the detected box actually removes significant non-QR areas
      final cropArea = detectedBox.width * detectedBox.height;
      final totalArea = width * height;
      final areaRatio = cropArea / totalArea;

      // If the detected box is virtually the whole image (> 92% of area) and already square,
      // leave it as is.
      if (isAlreadySquare && areaRatio > 0.88) {
        return QrCropResult(
          bytes: imageBytes,
          wasCropped: false,
          originalWidth: width,
          originalHeight: height,
          croppedWidth: width,
          croppedHeight: height,
          message: 'QR code is already standalone and square.',
        );
      }

      // Add a clean quiet-zone margin (approx 5% of QR width)
      final margin = (detectedBox.width * 0.05).clamp(8.0, 36.0);
      final finalCropRect = ui.Rect.fromLTRB(
        math.max(0.0, detectedBox.left - margin),
        math.max(0.0, detectedBox.top - margin),
        math.min(width.toDouble(), detectedBox.right + margin),
        math.min(height.toDouble(), detectedBox.bottom + margin),
      );

      // Crop the original high-resolution image using canvas
      final croppedBytes = await _cropImage(uiImage, finalCropRect);

      return QrCropResult(
        bytes: croppedBytes,
        wasCropped: true,
        originalWidth: width,
        originalHeight: height,
        croppedWidth: finalCropRect.width.round(),
        croppedHeight: finalCropRect.height.round(),
        boundingBox: finalCropRect,
        message: 'QR code automatically detected and cropped.',
      );
    } catch (e) {
      debugPrint('[QrCodeCropper] Extraction error: $e');
      return QrCropResult(
        bytes: imageBytes,
        wasCropped: false,
        originalWidth: 0,
        originalHeight: 0,
        croppedWidth: 0,
        croppedHeight: 0,
        message: 'Original image preserved.',
      );
    }
  }

  /// Detects QR codes by identifying standard 1:1:3:1:1 finder patterns
  /// (top-left, top-right, bottom-left corners).
  static ui.Rect? _detectByFinderPatterns(
    Uint8List pixels,
    int width,
    int height,
  ) {
    // Dynamic sampling step based on resolution
    final step = (width / 500).clamp(1, 4).toInt();
    final centers = <ui.Offset>[];

    for (int y = 0; y < height; y += step * 3) {
      int state = 0;
      final runs = [0, 0, 0, 0, 0];

      for (int x = 0; x < width; x += step) {
        final lum = _luminance(pixels, x, y, width);
        final isDark = lum < 100;

        if (state % 2 == 0) {
          // Even states: 0, 2, 4 -> Expecting dark
          if (isDark) {
            runs[state] += step;
          } else {
            // Switched from dark to light
            if (state == 4) {
              // 5 completed runs: dark, light, center dark, light, dark
              if (_isFinderPattern(runs)) {
                final cx = (x - (runs[4] + runs[3] + runs[2] / 2)).toDouble();
                final cy = y.toDouble();
                if (_verifyVerticalFinder(
                    pixels, cx.round(), cy.round(), width, height, runs[2])) {
                  if (!centers.any((c) =>
                      (c.dx - cx).abs() < 24 && (c.dy - cy).abs() < 24)) {
                    centers.add(ui.Offset(cx, cy));
                  }
                }
              }
              runs[0] = runs[2];
              runs[1] = runs[3];
              runs[2] = runs[4];
              runs[3] = step;
              runs[4] = 0;
              state = 3;
            } else {
              if (runs[state] > 0) {
                state++;
                runs[state] = step;
              }
            }
          }
        } else {
          // Odd states: 1, 3 -> Expecting light
          if (!isDark) {
            runs[state] += step;
          } else {
            // Switched from light to dark
            state++;
            runs[state] = step;
          }
        }
      }
    }

    if (centers.length >= 3) {
      double minX = centers.map((c) => c.dx).reduce(math.min);
      double maxX = centers.map((c) => c.dx).reduce(math.max);
      double minY = centers.map((c) => c.dy).reduce(math.min);
      double maxY = centers.map((c) => c.dy).reduce(math.max);

      // Estimate module size and expand to cover the full finder pattern boundaries
      final qrWidth = maxX - minX;
      final qrHeight = maxY - minY;

      if (qrWidth > 40 && qrHeight > 40) {
        final patternMargin = qrWidth * 0.12;
        return ui.Rect.fromLTRB(
          math.max(0.0, minX - patternMargin),
          math.max(0.0, minY - patternMargin),
          math.min(width.toDouble(), maxX + patternMargin),
          math.min(height.toDouble(), maxY + patternMargin),
        );
      }
    }

    return null;
  }

  /// Verifies if 5 runs match the 1:1:3:1:1 module proportions.
  static bool _isFinderPattern(List<int> runs) {
    final total = runs.reduce((a, b) => a + b);
    if (total < 7) return false;
    final module = total / 7.0;
    final maxVariance = module * 0.70;

    return (runs[0] - module).abs() < maxVariance &&
        (runs[1] - module).abs() < maxVariance &&
        (runs[2] - 3.0 * module).abs() < maxVariance * 2.0 &&
        (runs[3] - module).abs() < maxVariance &&
        (runs[4] - module).abs() < maxVariance;
  }

  /// Cross-verifies the finder pattern vertically at column [x].
  static bool _verifyVerticalFinder(
    Uint8List pixels,
    int x,
    int y,
    int width,
    int height,
    int centerDarkLength,
  ) {
    if (x < 0 || x >= width || y < 0 || y >= height) return false;
    final span = centerDarkLength * 4;
    final minY = math.max(0, y - span);
    final maxY = math.min(height - 1, y + span);

    int transitions = 0;
    bool lastDark = _luminance(pixels, x, minY, width) < 100;

    for (int currY = minY + 1; currY <= maxY; currY += 2) {
      final isDark = _luminance(pixels, x, currY, width) < 100;
      if (isDark != lastDark) {
        transitions++;
        lastDark = isDark;
      }
    }

    return transitions >= 4;
  }

  /// Detects the QR region via high-frequency black/white transitions projection profile.
  static ui.Rect? _detectByTransitionDensity(
    Uint8List pixels,
    int width,
    int height,
  ) {
    // 1. Horizontal projection (count transitions along each row)
    final rowTransitions = List.filled(height, 0);
    final rowStep = (height / 400).clamp(1, 4).toInt();
    final colStep = (width / 400).clamp(1, 4).toInt();

    for (int y = 0; y < height; y += rowStep) {
      int count = 0;
      bool lastDark = _luminance(pixels, 0, y, width) < 120;
      for (int x = colStep; x < width; x += colStep) {
        final isDark = _luminance(pixels, x, y, width) < 120;
        if (isDark != lastDark) {
          count++;
          lastDark = isDark;
        }
      }
      rowTransitions[y] = count;
      // Interpolate for sampled rows
      for (int i = 1; i < rowStep && y + i < height; i++) {
        rowTransitions[y + i] = count;
      }
    }

    // 2. Vertical projection (count transitions along each column)
    final colTransitions = List.filled(width, 0);
    for (int x = 0; x < width; x += colStep) {
      int count = 0;
      bool lastDark = _luminance(pixels, x, 0, width) < 120;
      for (int y = rowStep; y < height; y += rowStep) {
        final isDark = _luminance(pixels, x, y, width) < 120;
        if (isDark != lastDark) {
          count++;
          lastDark = isDark;
        }
      }
      colTransitions[x] = count;
      // Interpolate for sampled cols
      for (int i = 1; i < colStep && x + i < width; i++) {
        colTransitions[x + i] = count;
      }
    }

    // A QR code has high transition frequency (typically >= 6 transitions across rows/cols).
    int? startY, endY;
    int maxRowSpan = 0;
    int? bestStartY, bestEndY;

    for (int y = 0; y < height; y++) {
      if (rowTransitions[y] >= 6) {
        startY ??= y;
        endY = y;
      } else {
        if (startY != null && endY != null) {
          final span = endY - startY;
          if (span > maxRowSpan) {
            maxRowSpan = span;
            bestStartY = startY;
            bestEndY = endY;
          }
        }
        startY = null;
        endY = null;
      }
    }
    if (startY != null && endY != null) {
      final span = endY - startY;
      if (span > maxRowSpan) {
        bestStartY = startY;
        bestEndY = endY;
      }
    }

    int? startX, endX;
    int maxColSpan = 0;
    int? bestStartX, bestEndX;

    for (int x = 0; x < width; x++) {
      if (colTransitions[x] >= 6) {
        startX ??= x;
        endX = x;
      } else {
        if (startX != null && endX != null) {
          final span = endX - startX;
          if (span > maxColSpan) {
            maxColSpan = span;
            bestStartX = startX;
            bestEndX = endX;
          }
        }
        startX = null;
        endX = null;
      }
    }
    if (startX != null && endX != null) {
      final span = endX - startX;
      if (span > maxColSpan) {
        bestStartX = startX;
        bestEndX = endX;
      }
    }

    if (bestStartX != null &&
        bestEndX != null &&
        bestStartY != null &&
        bestEndY != null) {
      final spanW = (bestEndX - bestStartX).toDouble();
      final spanH = (bestEndY - bestStartY).toDouble();

      final ratio = spanW / spanH;
      if (ratio >= 0.65 && ratio <= 1.50 && spanW >= 50 && spanH >= 50) {
        final side = math.max(spanW, spanH);
        final centerX = (bestStartX + bestEndX) / 2.0;
        final centerY = (bestStartY + bestEndY) / 2.0;

        final left = (centerX - side / 2).clamp(0.0, width.toDouble());
        final top = (centerY - side / 2).clamp(0.0, height.toDouble());
        final right = (centerX + side / 2).clamp(0.0, width.toDouble());
        final bottom = (centerY + side / 2).clamp(0.0, height.toDouble());

        return ui.Rect.fromLTRB(left, top, right, bottom);
      }
    }

    return null;
  }

  /// Calculates the perceived luminance of a pixel at ([x], [y]).
  static int _luminance(Uint8List pixels, int x, int y, int width) {
    final offset = (y * width + x) * 4;
    if (offset + 2 >= pixels.length) return 255;
    final r = pixels[offset];
    final g = pixels[offset + 1];
    final b = pixels[offset + 2];
    return (0.299 * r + 0.587 * g + 0.114 * b).round();
  }

  /// Crops the [uiImage] to [cropRect] and returns the encoded PNG bytes.
  static Future<Uint8List> _cropImage(ui.Image uiImage, ui.Rect cropRect) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    final destRect = ui.Rect.fromLTWH(0, 0, cropRect.width, cropRect.height);

    // Draw white background in case source edges touch transparent or bleed
    canvas.drawRect(
      destRect,
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );

    canvas.drawImageRect(
      uiImage,
      cropRect,
      destRect,
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );

    final picture = recorder.endRecording();
    final croppedUiImage = await picture.toImage(
      cropRect.width.round(),
      cropRect.height.round(),
    );

    final byteData =
        await croppedUiImage.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }
}
