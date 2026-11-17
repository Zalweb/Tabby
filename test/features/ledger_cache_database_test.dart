import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:tabby/features/tabs/data/ledger_cache_database.dart';
import 'package:tabby/features/tabs/data/ledger_storage_factory_native.dart';

Future<Directory> fixtureDirectory() async => Directory(
  '.dart_tool/ledger-test-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(100000)}',
)..createSync(recursive: true);
String fixtureKey() => List.generate(
  32,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();
LedgerCacheDatabase database(
  File file,
  String key,
  Map<String, String> legacy, {
  Future<void> Function()? fault,
}) => LedgerCacheDatabase(
  NativeDatabase.createInBackground(
    file,
    setup: (db) {
      if (db.select('PRAGMA cipher').isEmpty) {
        throw StateError('Encryption missing');
      }
      db.execute("PRAGMA key='$key'");
      db.execute('PRAGMA journal_mode=WAL');
      db.execute('PRAGMA synchronous=FULL');
    },
  ),
  legacyRead: (key) async => legacy[key],
  beforeCommit: fault,
);
Map<String, dynamic> entry(int index) => {
  'id': 'entry-$index',
  'date': DateTime.utc(
    2026,
    11,
    1,
  ).subtract(Duration(minutes: index)).toIso8601String(),
  'title': 'Synthetic private expense $index',
  'totalAmountCentavos': 10001 + index,
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'encrypted rows and import marker commit together and survive a reopen',
    () async {
      final dir = await fixtureDirectory(), key = fixtureKey();
      final file = File('${dir.path}/fixture.sqlite');
      const name = 'tabby_pending_ops_fixture-owner';
      final legacy = {
        name: jsonEncode([
          {
            'type': 'add_expense',
            'operation_id': 'stable-operation',
            'total_amount_centavos': 1234,
          },
        ]),
      };
      var fail = true;
      final first = database(
        file,
        key,
        legacy,
        fault: () async {
          if (fail) throw StateError('Synthetic interrupted import');
        },
      );
      await expectLater(first.read(key: name), throwsStateError);
      expect(
        (await first
                .customSelect('SELECT count(*) AS n FROM cache_keys')
                .getSingle())
            .read<int>('n'),
        0,
      );
      expect(legacy[name], isNotNull);
      fail = false;
      final original = await first.read(key: name);
      expect(jsonDecode(original!), jsonDecode(legacy[name]!));
      await first.close();
      final reopened = database(file, key, {});
      expect(await reopened.read(key: name), original);
      await reopened.close();
      expect(
        latin1.decode(file.readAsBytesSync()).contains('stable-operation'),
        isFalse,
      );
      final noKey = sqlite.sqlite3.open(file.path);
      expect(
        () => noKey.select('SELECT * FROM cache_items'),
        throwsA(isA<sqlite.SqliteException>()),
      );
      noKey.close();
    },
  );
  test(
    'pending operations without legacy IDs receive one durable ID exactly once',
    () async {
      final dir = await fixtureDirectory(), key = fixtureKey();
      final file = File('${dir.path}/fixture.sqlite');
      final db = database(file, key, {
        'tabby_pending_ops_owner': jsonEncode([
          {'type': 'add_expense'},
        ]),
      });
      final first =
          jsonDecode((await db.read(key: 'tabby_pending_ops_owner'))!) as List;
      expect(first.single['operation_id'], isA<String>());
      await db.close();
      final reopened = database(file, key, {});
      expect(
        jsonDecode((await reopened.read(key: 'tabby_pending_ops_owner'))!),
        first,
      );
      await reopened.close();
    },
  );
  test('failed replacement rolls back rows and deletion tombstones prevent old queue resurrection', () async {
    final dir = await fixtureDirectory(), key = fixtureKey();
    final file = File('${dir.path}/fixture.sqlite');
    const name = 'tabby_pending_ops_owner';
    final original = jsonEncode([
      {'operation_id': 'original', 'type': 'add_expense'},
    ]);
    var fail = false;
    final db = database(
      file,
      key,
      {name: original},
      fault: () async {
        if (fail) throw StateError('Synthetic failed commit');
      },
    );
    expect(jsonDecode((await db.read(key: name))!), jsonDecode(original));
    fail = true;
    await expectLater(
      db.write(
        key: name,
        value: jsonEncode([
          {'operation_id': 'replacement'},
        ]),
      ),
      throwsStateError,
    );
    expect(jsonDecode((await db.read(key: name))!), jsonDecode(original));
    fail = false;
    await db.removeValue(key: name);
    await db.close();
    final reopened = database(file, key, {name: original});
    expect(await reopened.read(key: name), isNull);
    await reopened.close();
  });
  test('100 tabs and 10000 entries normalize to IDs and update only changed records', () async {
    final dir = await fixtureDirectory(), key = fixtureKey();
    final file = File('${dir.path}/fixture.sqlite');
    final tabs = [
      for (var t = 0; t < 100; t++)
        {
          'id': 'tab-$t',
          'name': 'Synthetic tab $t',
          'entries': [for (var e = 0; e < 100; e++) entry(t * 100 + e)],
        },
    ];
    final db = database(file, key, {});
    const name = 'tabby_cached_tabs_owner-a';
    final timer = Stopwatch()..start();
    await db.write(key: name, value: jsonEncode(tabs));
    final initialMs = timer.elapsedMilliseconds;
    expect(
      (await db
              .customSelect(
                "SELECT count(*) AS n FROM cache_items WHERE row_kind='entry'",
              )
              .getSingle())
          .read<int>('n'),
      10000,
    );
    await db.customStatement('CREATE TABLE observed_updates(id TEXT)');
    await db.customStatement(
      'CREATE TRIGGER observe_update AFTER UPDATE ON cache_items BEGIN INSERT INTO observed_updates VALUES(new.row_id); END',
    );
    (tabs.first['entries'] as List).first['title'] = 'Synthetic edited expense';
    timer.reset();
    await db.write(key: name, value: jsonEncode(tabs));
    final updateMs = timer.elapsedMilliseconds;
    expect(
      (await db
              .customSelect('SELECT count(*) AS n FROM observed_updates')
              .getSingle())
          .read<int>('n'),
      1,
    );
    await db.customStatement('DELETE FROM observed_updates');
    (tabs.first['entries'] as List).insert(0, {
      ...entry(-1),
      'id': 'new-entry',
    });
    await db.write(key: name, value: jsonEncode(tabs));
    expect(
      (await db
              .customSelect('SELECT count(*) AS n FROM observed_updates')
              .getSingle())
          .read<int>('n'),
      0,
    );
    final page = await db.entryPage(key: name, tabId: 'tab-0', limit: 25);
    expect(page.length, 25);
    expect(page.first['id'], 'new-entry');
    expect(page[1]['title'], 'Synthetic edited expense');
    expect(await db.read(key: 'tabby_cached_tabs_owner-b'), isNull);
    final decoded = jsonDecode((await db.read(key: name))!) as List;
    expect(decoded.length, 100);
    expect((decoded.first['entries'] as List).length, 101);
    // Sanitized timing is Windows test-engine evidence, never device evidence.
    // ignore: avoid_print
    print(
      'Synthetic encrypted Drift: initial10000=${initialMs}ms changedEntry=${updateMs}ms',
    );
    await db.close();
  });
  test('duplicate financial IDs fail import and preserve the original legacy value', () async {
    final dir = await fixtureDirectory(), key = fixtureKey();
    final original = jsonEncode([
      {'operation_id': 'same'},
      {'operation_id': 'same', 'amount': 1},
    ]);
    final legacy = {'tabby_pending_ops_owner': original};
    final db = database(File('${dir.path}/fixture.sqlite'), key, legacy);
    await expectLater(
      db.read(key: 'tabby_pending_ops_owner'),
      throwsFormatException,
    );
    expect(legacy['tabby_pending_ops_owner'], original);
    expect(
      (await db
              .customSelect('SELECT count(*) AS n FROM cache_keys')
              .getSingle())
          .read<int>('n'),
      0,
    );
    await db.close();
  });
  test('native factory keeps its key in secure storage and never replaces a database with a lost key', () async {
    final dir = await fixtureDirectory();
    final first = NativeLedgerCacheStorage(directory: () async => dir);
    await first.write(
      key: 'tabby_pending_ops_owner',
      value: jsonEncode([
        {'operation_id': 'private-fixture'},
      ]),
    );
    final key = await const FlutterSecureStorage().read(
      key: NativeLedgerCacheStorage.keyName,
    );
    expect(key, hasLength(64));
    await first.close();
    final file = File('${dir.path}/tabby-ledger-v1.sqlite');
    final originalBytes = file.readAsBytesSync();
    await const FlutterSecureStorage().delete(
      key: NativeLedgerCacheStorage.keyName,
    );
    final missing = NativeLedgerCacheStorage(directory: () async => dir);
    await expectLater(
      missing.read(key: 'tabby_pending_ops_owner'),
      throwsStateError,
    );
    expect(file.readAsBytesSync(), originalBytes);
    await const FlutterSecureStorage().write(
      key: NativeLedgerCacheStorage.keyName,
      value: key,
    );
    expect(
      jsonDecode((await missing.read(key: 'tabby_pending_ops_owner'))!)
          .single['operation_id'],
      'private-fixture',
    );
    await missing.close();
  });
}
