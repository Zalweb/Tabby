import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../tabs/domain/models.dart';
import '../../../core/services/receipt_attachment_service.dart';

/// Canonical PNG strips source metadata and bounds decoding/retained image size.
Future<Uint8List> prepareAvatar(Uint8List source) async {
  if (source.isEmpty || source.length > 10 * 1024 * 1024) {
    throw const FormatException('Choose a photo up to 10 MB.');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(source);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width * descriptor.height > 24000000) {
      throw const FormatException('Choose a smaller photo.');
    }
    final edge = descriptor.width > descriptor.height
        ? descriptor.width
        : descriptor.height;
    final scale = edge > 512 ? 512 / edge : 1.0;
    codec = await descriptor.instantiateCodec(
        targetWidth: (descriptor.width * scale).round().clamp(1, 512),
        targetHeight: (descriptor.height * scale).round().clamp(1, 512));
    image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null || data.lengthInBytes > 2 * 1024 * 1024) {
      throw const FormatException('Unable to prepare photo.');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

class ProfileAvatarDraft extends ChangeNotifier {
  ProfileAvatarDraft(
      {required this.owner,
      required this.isCurrent,
      required this.pick,
      required this.upload,
      required this.save,
      this.storage = const FlutterSecureStorage(),
      Future<Uint8List> Function(Uint8List)? prepare})
      : prepare = prepare ?? prepareAvatar;
  final String owner;
  final bool Function() isCurrent;
  final Future<XFile?> Function(ImageSource) pick;
  final Future<void> Function(String path, Uint8List bytes) upload;
  final Future<ProfileUpdateResult> Function(String reference) save;
  final Future<Uint8List> Function(Uint8List) prepare;
  final FlutterSecureStorage storage;
  String get key => 'tabby_${owner}_avatar_draft_v1';
  String? path, error;
  String? _pickedImage;
  Uint8List? bytes;
  bool busy = false, _disposed = false, _ready = false;
  static final _writes = <String, Future<void>>{};
  Future<T> _stored<T>(Future<T> Function() work) async {
    final previous = _writes[owner] ?? Future<void>.value();
    final result = previous.then((_) => work());
    final barrier =
        result.then<void>((_) {}, onError: (Object _, StackTrace stack) {});
    _writes[owner] = barrier;
    try {
      return await result;
    } finally {
      if (identical(_writes[owner], barrier)) _writes.remove(owner);
    }
  }

  Future<void> _clearIfMatches(String? expected) => _stored(() async {
        final raw = await storage.read(key: key);
        if (raw != null &&
            (jsonDecode(raw) as Map<String, dynamic>)['path'] == expected) {
          await storage.delete(key: key);
        }
      });

  bool get current => !_disposed && isCurrent();
  bool get hasDraft => bytes != null && path != null;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> restore() async {
    if (_ready || busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      final raw = await _stored(() => storage.read(key: key));
      if (!current) return;
      if (raw != null) {
        if (raw.length > 3 * 1024 * 1024) {
          throw const FormatException('Invalid avatar draft size');
        }
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final restoredPath = map['path'] as String;
        final restored = base64Decode(map['bytes'] as String);
        if (!RegExp('^${RegExp.escape(owner)}/[0-9a-f-]{36}\\.png\$')
                .hasMatch(restoredPath) ||
            restored.length > 2 * 1024 * 1024 ||
            restored.isEmpty) {
          throw const FormatException('Invalid avatar draft');
        }
        path = restoredPath;
        bytes = restored;
        _pickedImage = map['source_id'] as String?;
      }
      _ready = true;
      final recovered =
          await ReceiptAttachmentService.recovery.restored(owner, 'avatar');
      if (recovered != null && current) await _retainPicked(recovered);
    } catch (_) {
      error =
          'Your saved photo draft could not be read. Retry before choosing another photo.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<bool> choose(ImageSource source) async {
    if (busy || !current) return false;
    if (!_ready) {
      await restore();
      if (!_ready || !current) return false;
    }
    busy = true;
    error = null;
    _notify();
    try {
      final file = await pick(source);
      if (file == null || !current) return false;
      await _retainPicked(file);
      return current;
    } catch (_) {
      if (current) {
        error =
            'Photo could not be selected or saved. Choose a clear image up to 10 MB and retry.';
      }
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> _retainPicked(XFile file) async {
    if (file.path.startsWith('tabby-picker:') &&
        _pickedImage == file.path &&
        hasDraft) {
      await ReceiptAttachmentService.recovery
          .acknowledge(owner, 'avatar', file);
      return;
    }
    if (await file.length() > 10 * 1024 * 1024) {
      throw const FormatException('Photo too large');
    }
    if (!current) return;
    final prepared = await prepare(await file.readAsBytes());
    if (!current) return;
    final newPath = '$owner/${const Uuid().v4()}.png';
    final encoded = jsonEncode({
      'path': newPath,
      'bytes': base64Encode(prepared),
      'source_id': file.path
    });
    await _stored(() => storage.write(key: key, value: encoded));
    if (!current) return;
    path = newPath;
    _pickedImage = file.path;
    bytes = Uint8List.fromList(prepared);
    await ReceiptAttachmentService.recovery.acknowledge(owner, 'avatar', file);
  }

  Future<bool> apply() async {
    if (busy || !current || !hasDraft) return false;
    busy = true;
    error = null;
    _notify();
    try {
      final frozenPath = path!, frozenBytes = Uint8List.fromList(bytes!);
      await upload(frozenPath, frozenBytes);
      if (!current) return false;
      final result = await save('avatar:$frozenPath');
      if (!current) return false;
      if (!result.isSuccess) throw StateError('Profile rejected');
      // A failed cleanup must not turn an acknowledged profile into a failure.
      // Keeping this immutable command permits a safe same-photo replay.
      try {
        await _clearIfMatches(frozenPath);
      } catch (_) {}
      path = null;
      bytes = null;
      return true;
    } catch (_) {
      if (current) {
        error =
            'Photo could not be saved. Your selected photo is kept here for retry.';
      }
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<bool> usePreset(String value) async {
    if (busy || !current) return false;
    if (!_ready) {
      await restore();
      if (!_ready || !current) return false;
    }
    busy = true;
    final frozenPath = path;
    error = null;
    _notify();
    try {
      final result = await save(value);
      if (!current) return false;
      if (!result.isSuccess) throw StateError('Profile rejected');
      try {
        await _clearIfMatches(frozenPath);
      } catch (_) {}
      path = null;
      bytes = null;
      return true;
    } catch (_) {
      if (current) error = 'Photo could not be updated. Please retry.';
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
