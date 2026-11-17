import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class LedgerKeyValueStore {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> removeValue({required String key});
}

/// Browser compatibility and explicit unit-test boundary. Native production
/// uses encrypted transactional SQLite through the platform factory.
class SecureLedgerKeyValueStore implements LedgerKeyValueStore {
  const SecureLedgerKeyValueStore({
    this.storage = const FlutterSecureStorage(),
  });
  final FlutterSecureStorage storage;
  @override
  Future<String?> read({required String key}) => storage.read(key: key);
  @override
  Future<void> write({required String key, required String value}) =>
      storage.write(key: key, value: value);
  @override
  Future<void> removeValue({required String key}) => storage.delete(key: key);
}
