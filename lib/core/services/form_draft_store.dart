import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypted account/workflow snapshots. Queue reads with writes across route
/// recreation so an older save cannot overwrite a newer draft or its removal.
class FormDraftStore {
  const FormDraftStore({this.storage = const FlutterSecureStorage()});
  final FlutterSecureStorage storage;
  static final _work = <String, Future<void>>{};
  static String key(String owner, String purpose) =>
      'tabby_form_v1_${base64UrlEncode(utf8.encode('$owner/$purpose'))}';
  Future<T> _run<T>(
      String owner, String purpose, Future<T> Function(String) task) async {
    final name = key(owner, purpose);
    final result =
        (_work[name] ?? Future<void>.value()).then((_) => task(name));
    final barrier =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _work[name] = barrier;
    try {
      return await result;
    } finally {
      if (identical(_work[name], barrier)) _work.remove(name);
    }
  }

  Future<Map<String, dynamic>?> read(String owner, String purpose) =>
      _run(owner, purpose, (key) async {
        final raw = await storage.read(key: key);
        if (raw == null) return null;
        final map = jsonDecode(raw) as Map<String, dynamic>;
        if (map['owner'] != owner || map['purpose'] != purpose) {
          throw const FormatException('Draft account/workflow mismatch');
        }
        return Map<String, dynamic>.from(map['value'] as Map);
      });
  Future<void> write(String owner, String purpose, Map<String, dynamic> value) {
    final encoded =
        jsonEncode({'owner': owner, 'purpose': purpose, 'value': value});
    if (encoded.length > 16 * 1024 * 1024) {
      throw const FormatException('Draft too large');
    }
    return _run(
        owner, purpose, (key) => storage.write(key: key, value: encoded));
  }

  Future<void> remove(String owner, String purpose) =>
      _run(owner, purpose, (key) => storage.delete(key: key));
  Future<void> removeIf(
          String owner, String purpose, String field, Object expected) =>
      _run(owner, purpose, (key) async {
        final raw = await storage.read(key: key);
        if (raw != null &&
            ((jsonDecode(raw) as Map)['value'] as Map)[field] == expected) {
          await storage.delete(key: key);
        }
      });
}
