import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:zxing2/qrcode.dart';

import 'qr_code_cropper.dart';

class PreparedQrImage {
  const PreparedQrImage(this.bytes, {required this.wasCropped});
  final Uint8List bytes;
  final bool wasCropped;
}

/// Checks actual QR decoding, not image shape or finder-pattern heuristics.
/// A readable code does not establish wallet ownership or confirm a payment.
class QrImageValidator {
  static Future<PreparedQrImage> prepare(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      throw const FormatException('Choose a QR image up to 10 MB.');
    }
    final canonical = await _canonicalPng(bytes);
    final payload = await _decode(canonical);
    if (payload == null || payload.trim().isEmpty) {
      throw const FormatException(
          'No readable QR code found. Export a clear receiving QR from your wallet.');
    }
    if (RegExp(r'^\+?[\d\s()-]{5,30}$').hasMatch(payload.trim())) {
      throw const FormatException(
          'This QR contains only an account number. Export your wallet receiving QR.');
    }
    final cropped = await QrCodeCropper.cropQrCode(canonical);
    // A crop is accepted only when the exact original payload still decodes.
    if (cropped.wasCropped && await _decode(cropped.bytes) == payload) {
      return PreparedQrImage(cropped.bytes, wasCropped: true);
    }
    return PreparedQrImage(canonical, wasCropped: false);
  }

  static Future<Uint8List> _canonicalPng(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width * descriptor.height > 24000000) {
        throw const FormatException('Choose a smaller QR image.');
      }
      final scale = 2048 /
          (descriptor.width > descriptor.height
              ? descriptor.width
              : descriptor.height);
      codec = await descriptor.instantiateCodec(
        targetWidth: scale < 1 ? (descriptor.width * scale).round() : null,
        targetHeight: scale < 1 ? (descriptor.height * scale).round() : null,
      );
      image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw const FormatException('Unable to read QR image.');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
          'Unable to read image. Choose a clear QR image.');
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  static Future<String?> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      return await compute(_decodePixels, (
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        image.width,
        image.height,
      ));
    } finally {
      image.dispose();
      codec.dispose();
    }
  }
}

String? _decodePixels((Uint8List, int, int) input) {
  final (rgba, width, height) = input;
  final pixels = Int32List(width * height);
  for (var i = 0; i < pixels.length; i++) {
    final offset = i * 4;
    // Composite transparent pixels onto white before luminance conversion.
    final alpha = rgba[offset + 3];
    int channel(int value) => (value * alpha + 255 * (255 - alpha)) ~/ 255;
    pixels[i] = (channel(rgba[offset]) << 16) |
        (channel(rgba[offset + 1]) << 8) |
        channel(rgba[offset + 2]);
  }
  try {
    final bitmap = BinaryBitmap(
        HybridBinarizer(RGBLuminanceSource(width, height, pixels)));
    return QRCodeReader().decode(bitmap).text;
  } catch (_) {
    return null;
  }
}
