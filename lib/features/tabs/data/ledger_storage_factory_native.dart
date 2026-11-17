import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show QueryExecutor;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'ledger_cache_database.dart';
import 'ledger_key_value_store.dart';

LedgerKeyValueStore createLedgerStorage() => NativeLedgerCacheStorage();

class NativeLedgerCacheStorage implements LedgerKeyValueStore {
  NativeLedgerCacheStorage({
    this.storage = const FlutterSecureStorage(),
    this.directory,
  });
  static const keyName = 'tabby_ledger_database_key_v1';
  final FlutterSecureStorage storage;
  final Future<Directory> Function()? directory;
  Future<LedgerCacheDatabase>? _opening;
  Future<LedgerCacheDatabase> _database() =>
      _opening ??= _open().onError((Object error, StackTrace stack) {
        _opening = null;
        Error.throwWithStackTrace(error, stack);
      });
  Future<LedgerCacheDatabase> _open() async {
    final location =
        await (directory?.call() ?? getApplicationSupportDirectory());
    await location.create(recursive: true);
    final file = File('${location.path}/tabby-ledger-v1.sqlite');
    var key = await storage.read(key: keyName);
    if (key == null) {
      // A missing key is never repaired by overwriting an existing database.
      if (await file.exists()) {
        throw StateError('Ledger encryption key unavailable.');
      }
      final random = Random.secure();
      key = List.generate(
        32,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await storage.write(key: keyName, value: key);
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(key)) {
      throw StateError('Invalid ledger encryption key.');
    }
    final passphrase = key;
    final database = LedgerCacheDatabase(
      _encryptedExecutor(file.path, passphrase),
      legacyRead: (key) => storage.read(key: key),
    );
    try {
      await database.customSelect('SELECT 1').get();
      return database;
    } catch (_) {
      await database.close();
      rethrow;
    }
  }

  @override
  Future<String?> read({required String key}) async =>
      (await _database()).read(key: key);
  Future<void> close() async {
    final opened = _opening;
    _opening = null;
    if (opened != null) await (await opened).close();
  }

  @override
  Future<void> write({required String key, required String value}) async =>
      (await _database()).write(key: key, value: value);
  @override
  Future<void> removeValue({required String key}) async =>
      (await _database()).removeValue(key: key);
}

QueryExecutor _encryptedExecutor(String path, String passphrase) =>
    NativeDatabase.createInBackground(
      File(path),
      setup: (raw) {
        // Runtime check is deliberate in release too: never fall back to SQLite
        // without encryption, regardless of assertions being compiled out.
        if (raw.select('PRAGMA cipher').isEmpty) {
          throw StateError('Encrypted SQLite runtime unavailable.');
        }
        raw.execute("PRAGMA cipher='chacha20'");
        try {
          raw.execute("PRAGMA key='$passphrase'");
          raw.select('SELECT count(*) FROM sqlite_master');
        } catch (_) {
          throw StateError('Ledger database could not be unlocked.');
        }
        raw.execute('PRAGMA journal_mode=WAL');
        raw.execute('PRAGMA synchronous=FULL');
        raw.execute('PRAGMA foreign_keys=ON');
        raw.execute('PRAGMA temp_store=MEMORY');
      },
    );
