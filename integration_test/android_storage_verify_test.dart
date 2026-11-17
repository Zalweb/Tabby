import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show QueryExecutor;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:tabby/features/tabs/data/ledger_cache_database.dart';
import 'package:tabby/features/tabs/data/ledger_storage_factory_native.dart';

import 'native_storage_fixture.dart';

QueryExecutor encryptedFixtureExecutor(File file, String key) =>
    NativeDatabase.createInBackground(
      file,
      setup: (raw) {
        if (raw.select('PRAGMA cipher').isEmpty) {
          throw StateError('Encrypted native SQLite unavailable.');
        }
        raw.execute("PRAGMA cipher='chacha20'");
        raw.execute("PRAGMA key='$key'");
        raw.execute('PRAGMA journal_mode=WAL');
        raw.execute('PRAGMA synchronous=FULL');
      },
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('TABBY_USB_TEST')) {
    throw StateError('Native storage fixtures require the isolated package.');
  }
  const secure = FlutterSecureStorage();
  testWidgets(
    'native ledger survives process restart encrypted and owner isolated',
    (tester) async {
      await tester.runAsync(() async {
        final store = NativeLedgerCacheStorage(
          directory: nativeFixtureDirectory,
        );
        try {
          final watch = Stopwatch()..start();
          final tabs =
              jsonDecode((await store.read(key: nativeCacheKey))!) as List;
          expect(tabs.length, 100);
          expect(
            tabs.fold<int>(
              0,
              (sum, tab) => sum + (tab['entries'] as List).length,
            ),
            10000,
          );
          expect(tabs.first['entries'][0]['totalAmountCentavos'], 100);
          final queue =
              jsonDecode((await store.read(key: nativeQueueKey))!) as List;
          expect(queue.single['operation_id'], nativeOperation);
          expect(
            await store.read(key: 'tabby_cached_tabs_other-native-owner'),
            isNull,
          );
          debugPrint(
            'NATIVE_STORAGE restartTabs=100 restartEntries=10000 readMs=${watch.elapsedMilliseconds} durableOperation=true',
          );
        } finally {
          await store.close();
        }
        final folder = await nativeFixtureDirectory();
        final file = File('${folder.path}/tabby-ledger-v1.sqlite');
        expect(
          latin1.decode(await file.readAsBytes()),
          isNot(contains('Synthetic encrypted native expense')),
        );
        final noKey = sqlite.sqlite3.open(file.path);
        try {
          expect(
            () => noKey.select('SELECT * FROM cache_items'),
            throwsA(isA<sqlite.SqliteException>()),
          );
        } finally {
          noKey.close();
        }
      });
    },
  );
  testWidgets(
    'native missing key rejects open without overwriting ciphertext',
    (tester) async {
      await tester.runAsync(() async {
        final folder = await nativeFixtureDirectory();
        final file = File('${folder.path}/tabby-ledger-v1.sqlite');
        final original = await file.readAsBytes();
        final key = await secure.read(key: NativeLedgerCacheStorage.keyName);
        expect(key, isNotNull);
        await secure.delete(key: NativeLedgerCacheStorage.keyName);
        final store = NativeLedgerCacheStorage(
          directory: nativeFixtureDirectory,
        );
        try {
          await expectLater(store.read(key: nativeCacheKey), throwsStateError);
          expect(await file.readAsBytes(), orderedEquals(original));
        } finally {
          await secure.write(key: NativeLedgerCacheStorage.keyName, value: key);
          await store.close();
        }
        debugPrint(
          'NATIVE_STORAGE missingKeyRejected=true ciphertextPreserved=true keyRestored=true',
        );
      });
    },
  );
  testWidgets(
    'native interrupted legacy import rolls back before durable retry',
    (tester) async {
      await tester.runAsync(() async {
        final folder = await nativeFixtureDirectory();
        final file = File(
          '${folder.path}/atomic-${DateTime.now().microsecondsSinceEpoch}.sqlite',
        );
        final key = (await secure.read(key: NativeLedgerCacheStorage.keyName))!;
        const legacyName = 'tabby_pending_ops_native-atomic-owner';
        final original = jsonEncode([
          {'operation_id': 'native-atomic-operation', 'type': 'add_expense'},
        ]);
        await secure.write(key: legacyName, value: original);
        var interrupt = true;
        LedgerCacheDatabase open({required bool fault}) => LedgerCacheDatabase(
          encryptedFixtureExecutor(file, key),
          legacyRead: (name) => secure.read(key: name),
          beforeCommit: fault
              ? () async {
                  if (interrupt) throw StateError('Synthetic interruption');
                }
              : null,
        );
        final db = open(fault: true);
        try {
          await expectLater(db.read(key: legacyName), throwsStateError);
          expect(
            (await db
                    .customSelect('SELECT count(*) AS n FROM cache_keys')
                    .getSingle())
                .read<int>('n'),
            0,
          );
          expect(await secure.read(key: legacyName), original);
          interrupt = false;
          expect(
            jsonDecode((await db.read(key: legacyName))!),
            jsonDecode(original),
          );
        } finally {
          await db.close();
        }
        final reopened = open(fault: false);
        try {
          expect(
            jsonDecode((await reopened.read(key: legacyName))!),
            jsonDecode(original),
          );
        } finally {
          await reopened.close();
        }
        debugPrint(
          'NATIVE_STORAGE atomicRollback=true retryDurable=true legacyPreserved=true',
        );
      });
    },
  );
}
