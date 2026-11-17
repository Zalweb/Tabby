import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config/session_scope.dart';
import '../config/supabase_config.dart';
import 'qr_image_validator.dart';

/// Downloads using current authorization, never a stale public/signed URL.
class ReceivingQrExport {
  static const _channel = MethodChannel('tabby/receiving_qr');
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  static Future<bool> export({
    required bool share,
    required Future<Uint8List> Function() download,
    SessionStamp Function()? captureSession,
    bool Function(SessionStamp)? sessionIsCurrent,
  }) async {
    if (!supported) {
      throw UnsupportedError('QR save/share is available on Android and iOS.');
    }
    final session = (captureSession ?? SupabaseConfig.captureSession)();
    final prepared = await QrImageValidator.prepare(await download());
    if (!(sessionIsCurrent ?? SupabaseConfig.isCurrentSession)(session)) {
      throw StateError('Account changed. Reopen the receiving method.');
    }
    return await _channel.invokeMethod<bool>(share ? 'share' : 'save', {
          'bytes': prepared.bytes,
        }) ??
        false;
  }
}
