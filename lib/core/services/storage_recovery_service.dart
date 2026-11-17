import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'device_auth_service.dart';

class LocalStorageUnavailable implements Exception {
  const LocalStorageUnavailable();
}

/// Only used before providers and their queue writers are mounted.
class StorageRecoveryService {
  StorageRecoveryService({DeviceAuthService? auth, MethodChannel? channel})
    : _auth = auth ?? LocalDeviceAuthService(),
      _channel = channel ?? const MethodChannel('tabby/storage_recovery');
  final DeviceAuthService _auth;
  final MethodChannel _channel;
  static bool get supported => !kIsWeb && Platform.isAndroid;

  Future<bool> preserveAndReset() async {
    if (!await _auth.authenticate(
      reason: 'Recover Tabby storage on this device',
      allowDeviceCredential: true,
    )) {
      return false;
    }
    final result = await _channel.invokeMethod<bool>('preserveAndReset');
    if (result != true) throw const LocalStorageUnavailable();
    return true;
  }

  Future<void> closeForRestart() => _channel.invokeMethod<void>('close');
}
