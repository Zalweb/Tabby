import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Account-scoped owned bytes; picker cache paths are not durable references.
class ReceiptBlobStore {
  static const _storage = FlutterSecureStorage();
  static bool isPending(String path) => path.startsWith('tabby-receipt:');
  static String _key(String path) =>
      'tabby_receipt_blob_${base64UrlEncode(utf8.encode(path))}';
  static Future<String> save(Uint8List bytes,
      {required String ownerId, String extension = 'jpg'}) async {
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw const FormatException('Choose a receipt image up to 5 MB.');
    }
    final path = 'tabby-receipt:$ownerId:${const Uuid().v4()}.$extension';
    await _storage.write(key: _key(path), value: base64Encode(bytes));
    return path;
  }

  static Future<Uint8List?> read(String path, {required String ownerId}) async {
    if (!path.startsWith('tabby-receipt:$ownerId:')) {
      throw StateError('Receipt belongs to a different account.');
    }
    final encoded = await _storage.read(key: _key(path));
    return encoded == null ? null : base64Decode(encoded);
  }
}
