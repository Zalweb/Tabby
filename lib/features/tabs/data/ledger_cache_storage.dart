import 'ledger_key_value_store.dart';
import 'ledger_storage_factory_stub.dart'
    if (dart.library.io) 'ledger_storage_factory_native.dart'
    as platform;

class LedgerCacheStorage implements LedgerKeyValueStore {
  const LedgerCacheStorage();
  static LedgerKeyValueStore? debugOverride;
  static final LedgerKeyValueStore _native = platform.createLedgerStorage();
  LedgerKeyValueStore get _store => debugOverride ?? _native;
  @override
  Future<String?> read({required String key}) => _store.read(key: key);
  @override
  Future<void> write({required String key, required String value}) =>
      _store.write(key: key, value: value);
  @override
  Future<void> removeValue({required String key}) => _store.removeValue(key: key);
}
