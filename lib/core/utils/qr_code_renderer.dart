import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:qr_flutter/qr_flutter.dart';

/// Renders [data] as a square PNG QR code entirely on-device.
///
/// Returns `null` when the data cannot be encoded, so callers can surface an
/// inline error instead of sending the payload to a third-party image API.
Future<Uint8List?> renderQrPng(String data, {double size = 600}) async {
  try {
    final painter = QrPainter(
      data: data,
      version: QrVersions.auto,
      gapless: true,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: ui.Color(0xFF000000),
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: ui.Color(0xFF000000),
      ),
    );
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final side = size.toInt();
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, size, size),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    painter.paint(canvas, ui.Size(size, size));
    final image = await recorder.endRecording().toImage(side, side);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return byteData?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}
