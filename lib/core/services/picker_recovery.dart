import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'form_draft_store.dart';

/// image_picker has one native pending intent. Its owner and destination are
/// saved BEFORE launch. Recovery stores bytes privately; it never performs an
/// upload, profile update, payment submission, or financial confirmation.
class PickerRecovery {
  PickerRecovery(
      {required this.pick,
      required this.retrieve,
      this.storage = const FlutterSecureStorage()});
  final Future<XFile?> Function(ImageSource) pick;
  final Future<LostDataResponse> Function() retrieve;
  final FlutterSecureStorage storage;
  static const intentKey = 'tabby_pending_image_picker_v1';
  static const maxBytes = 10 * 1024 * 1024;
  bool _busy = false, _retrieved = false;
  Future<void>? _recovery;
  XFile? _capturedFile;
  Map<String, dynamic>? _capturedIntent;
  FormDraftStore get _drafts => FormDraftStore(storage: storage);
  String _purpose(String value) => 'picker:$value';

  Future<Map<String, dynamic>?> _intent() async {
    final raw = await storage.read(key: intentKey);
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> _clear(String id) async {
    if ((await _intent())?['id'] == id) await storage.delete(key: intentKey);
  }

  Future<XFile> _retain(Map<String, dynamic> intent, XFile file) async {
    _capturedFile = file;
    _capturedIntent = intent;
    if (file.path.isNotEmpty && !file.path.startsWith('tabby-picker:')) {
      await storage.write(
          key: intentKey,
          value: jsonEncode({...intent, 'recovered_path': file.path}));
    }
    if (await file.length() > maxBytes) {
      await _rejectCaptured(intent);
      throw const FormatException('Choose an image up to 10 MB.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > maxBytes) {
      await _rejectCaptured(intent);
      throw const FormatException('Choose an image up to 10 MB.');
    }
    final id = intent['id'] as String;
    await _drafts.write(
        intent['owner'] as String, _purpose(intent['purpose'] as String), {
      'id': id,
      'bytes': base64Encode(bytes),
      'name': file.name,
      'mime': file.mimeType,
    });
    await _clear(id);
    _capturedFile = null;
    _capturedIntent = null;
    return XFile.fromData(bytes,
        path: 'tabby-picker:$id', name: file.name, mimeType: file.mimeType);
  }

  Future<void> _rejectCaptured(Map<String, dynamic> intent) async {
    await _clear(intent['id'] as String);
    _capturedFile = null;
    _capturedIntent = null;
  }

  Future<XFile?> select(
      {required String owner,
      required String purpose,
      required ImageSource source,
      required bool Function() isCurrent}) async {
    if (_busy) throw StateError('An image picker is already open.');
    _busy = true;
    try {
      await recover();
      if (!isCurrent()) return null;
      final intent = <String, dynamic>{
        'id': const Uuid().v4(),
        'owner': owner,
        'purpose': purpose
      };
      await storage.write(key: intentKey, value: jsonEncode(intent));
      if (!isCurrent()) {
        await _clear(intent['id'] as String);
        return null;
      }
      final file = await pick(source);
      if (file == null) {
        await _clear(intent['id'] as String);
        return null;
      }
      final retained = await _retain(intent, file);
      return isCurrent() ? retained : null;
    } finally {
      _busy = false;
    }
  }

  Future<void> recover() {
    if (_recovery != null) return _recovery!;
    final result = _recover();
    _recovery = result;
    return result.whenComplete(() {
      if (identical(_recovery, result)) _recovery = null;
    });
  }

  Future<void> _recover() async {
    if (_capturedFile != null && _capturedIntent != null) {
      await _retain(_capturedIntent!, _capturedFile!);
      return;
    }
    final intent = await _intent();
    if (intent?['recovered_path'] case final String path) {
      await _retain(intent!, XFile(path));
      return;
    }
    if (_retrieved) return;
    final response = await retrieve();
    _retrieved = true;
    // No durable attribution means no safe destination. Never guess an owner.
    if (intent == null) return;
    final files = response.files;
    if (files != null && files.isNotEmpty) {
      final file = files.single;
      // The plugin consumes its result. Preserve the cache path before copying
      // bytes, so a failed encrypted write can be retried within cache lifetime.
      await _retain(intent, file);
    } else {
      if (response.exception != null) {
        await _drafts.write(
            intent['owner'] as String, _purpose(intent['purpose'] as String), {
          'id': intent['id'],
          'error': 'The image could not be recovered. Choose it again.'
        });
      }
      await _clear(intent['id'] as String);
    }
  }

  Future<XFile?> restored(String owner, String purpose) async {
    await recover();
    final value = await _drafts.read(owner, _purpose(purpose));
    if (value == null) return null;
    if (value['error'] != null) {
      throw const FormatException(
          'The image could not be recovered. Choose it again.');
    }
    final bytes = base64Decode(value['bytes'] as String);
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('Invalid recovered image');
    }
    return XFile.fromData(bytes,
        path: 'tabby-picker:${value['id']}',
        name: value['name'] as String,
        mimeType: value['mime'] as String?);
  }

  Future<void> acknowledge(String owner, String purpose, XFile file) async {
    final value = await _drafts.read(owner, _purpose(purpose));
    if (value != null && file.path == 'tabby-picker:${value['id']}') {
      await _drafts.removeIf(
          owner, _purpose(purpose), 'id', value['id'] as String);
    }
  }

  Future<void> discard(String owner, String purpose) async {
    if (_busy) throw StateError('Close the image picker first.');
    await _drafts.remove(owner, _purpose(purpose));
    final intent = await _intent();
    if (intent?['owner'] == owner && intent?['purpose'] == purpose) {
      await _clear(intent!['id'] as String);
    }
    if (_capturedIntent?['owner'] == owner &&
        _capturedIntent?['purpose'] == purpose) {
      _capturedIntent = null;
      _capturedFile = null;
    }
  }
}
