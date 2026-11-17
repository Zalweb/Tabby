import 'dart:convert';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'ledger_key_value_store.dart';

/// Versioned SQL is explicit because these records retain evolving wire JSON.
/// Original financial IDs are primary keys, never name/amount fingerprints.
class LedgerCacheDatabase extends GeneratedDatabase
    implements LedgerKeyValueStore {
  LedgerCacheDatabase(
    super.executor, {
    required this.legacyRead,
    this.beforeCommit,
  });
  final Future<String?> Function(String key) legacyRead;
  final Future<void> Function()? beforeCommit;
  Future<void> _work = Future.value();
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo> get allTables => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        'CREATE TABLE cache_keys(cache_key TEXT PRIMARY KEY, kind TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE cache_items(cache_key TEXT NOT NULL REFERENCES cache_keys(cache_key), row_id TEXT NOT NULL, parent_id TEXT, row_kind TEXT NOT NULL, position INTEGER NOT NULL, digest TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(cache_key,row_id))',
      );
      await customStatement(
        'CREATE INDEX cache_page ON cache_items(cache_key,parent_id,position,row_id)',
      );
    },
  );
  Future<T> _serialized<T>(Future<T> Function() run) async {
    final result = _work.then((_) => run());
    _work = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<String?> _kind(String key) async => (await customSelect(
    'SELECT kind FROM cache_keys WHERE cache_key=?',
    variables: [Variable(key)],
  ).getSingleOrNull())?.read<String>('kind');
  Future<void> _replace(String key, String? value) async {
    // Encoding and content digests run outside the UI isolate. Only changed
    // immutable records cross the SQL executor boundary as writes.
    final encoded = await _encodeOffIsolate(key, value);
    final previous = await customSelect(
      'SELECT row_id,digest FROM cache_items WHERE cache_key=?',
      variables: [Variable(key)],
    ).get();
    final old = {
      for (final row in previous)
        row.read<String>('row_id'): row.read<String>('digest'),
    };
    final kept = <String>{};
    await customStatement(
      'INSERT INTO cache_keys VALUES(?,?) ON CONFLICT(cache_key) DO UPDATE SET kind=excluded.kind',
      [key, encoded.kind],
    );
    await batch((batch) {
      for (final row in encoded.rows) {
        final id = row['id'] as String;
        kept.add(id);
        if (old[id] == row['digest']) continue;
        batch.customStatement(
          'INSERT INTO cache_items VALUES(?,?,?,?,?,?,?) ON CONFLICT(cache_key,row_id) DO UPDATE SET parent_id=excluded.parent_id,row_kind=excluded.row_kind,position=excluded.position,digest=excluded.digest,payload=excluded.payload',
          [
            key,
            id,
            row['parent'],
            row['kind'],
            row['position'],
            row['digest'],
            row['payload'],
          ],
        );
      }
      for (final id in old.keys.where((id) => !kept.contains(id))) {
        batch.customStatement(
          'DELETE FROM cache_items WHERE cache_key=? AND row_id=?',
          [key, id],
        );
      }
    });
    await beforeCommit?.call();
  }

  Future<void> _migrate(String key) async {
    if (await _kind(key) != null) return;
    final legacy = await legacyRead(key);
    // Rows and authority marker commit together. A failure leaves the original
    // encrypted legacy value intact; it is never deleted by migration.
    await _replace(key, legacy);
  }

  @override
  Future<String?> read({required String key}) => _serialized(
    () => transaction(() async {
      await _migrate(key);
      final kind = (await _kind(key))!;
      if (kind == 'deleted') return null;
      final rows = (await customSelect(
        'SELECT row_id,parent_id,row_kind,position,payload FROM cache_items WHERE cache_key=? ORDER BY position,row_id',
        variables: [Variable(key)],
      ).get()).map((row) => row.data).toList();
      return _decodeOffIsolate(kind, rows);
    }),
  );
  @override
  Future<void> write({required String key, required String value}) =>
      _serialized(() => transaction(() => _replace(key, value)));
  @override
  Future<void> removeValue({required String key}) =>
      _serialized(() => transaction(() => _replace(key, null)));

  /// Indexed offline history paging; no full tab JSON decode is necessary.
  Future<List<Map<String, dynamic>>> entryPage({
    required String key,
    required String tabId,
    int offset = 0,
    int limit = 50,
  }) => _serialized(
    () => transaction(() async {
      if (offset < 0 || limit < 1 || limit > 100) {
        throw ArgumentError('Invalid history page');
      }
      await _migrate(key);
      final rows = await customSelect(
        'SELECT payload FROM cache_items WHERE cache_key=? AND parent_id=? AND row_kind=? ORDER BY position,row_id LIMIT ? OFFSET ?',
        variables: [
          Variable(key),
          Variable(tabId),
          const Variable('entry'),
          Variable(limit),
          Variable(offset),
        ],
      ).get();
      final payloads = rows.map((row) => row.read<String>('payload')).toList();
      return _decodePageOffIsolate(payloads);
    }),
  );
}

class _EncodedCacheValue {
  const _EncodedCacheValue(this.kind, this.rows);
  final String kind;
  final List<Map<String, Object?>> rows;
}

_EncodedCacheValue _encodeCacheValue(String key, String? raw) {
  if (raw == null) return const _EncodedCacheValue('deleted', []);
  final value = jsonDecode(raw);
  final rows = <Map<String, Object?>>[], seen = <String>{};
  void add(
    String id,
    Object? value,
    int position, {
    String? parent,
    String kind = 'value',
  }) {
    if (!seen.add(id)) {
      throw const FormatException('Duplicate immutable cache identity');
    }
    final payload = jsonEncode(value);
    final digest = sha256
        .convert(utf8.encode(jsonEncode([parent, kind, position, payload])))
        .toString();
    rows.add({
      'id': id,
      'parent': parent,
      'kind': kind,
      'position': position,
      'digest': digest,
      'payload': payload,
    });
  }

  if (value is List) {
    final tabs = key.startsWith('tabby_cached_tabs_');
    for (var i = 0; i < value.length; i++) {
      final row = Map<String, dynamic>.from(value[i] as Map);
      if (key.startsWith('tabby_pending_ops_')) {
        row['operation_id'] ??= const Uuid().v4();
      }
      final id = row['operation_id'] ?? row['id'];
      if (id is! String || id.isEmpty) {
        throw const FormatException('Missing immutable cache identity');
      }
      if (tabs) {
        final entries = row.remove('entries') as List? ?? [];
        add(jsonEncode(['tab', id]), row, i, kind: 'tab');
        for (var j = 0; j < entries.length; j++) {
          final entry = Map<String, dynamic>.from(entries[j] as Map);
          final entryId = entry['id'];
          if (entryId is! String || entryId.isEmpty) {
            throw const FormatException('Missing entry identity');
          }
          final date = DateTime.tryParse(entry['date'] as String? ?? '');
          add(
            jsonEncode(['entry', id, entryId]),
            entry,
            date == null ? j : -date.microsecondsSinceEpoch,
            parent: id,
            kind: 'entry',
          );
        }
      } else {
        add(id, row, i);
      }
    }
    return _EncodedCacheValue(tabs ? 'tabs' : 'list', rows);
  }
  if (value is Map) {
    var i = 0;
    for (final item in value.entries) {
      add(item.key as String, item.value, i++);
    }
    return _EncodedCacheValue('map', rows);
  }
  add('scalar', value, 0);
  return _EncodedCacheValue('scalar', rows);
}

String _decodeCacheValue(String kind, List<Map<String, Object?>> rows) {
  if (kind == 'tabs') {
    final entries = <String, List<Object?>>{};
    for (final row in rows.where((row) => row['row_kind'] == 'entry')) {
      (entries[row['parent_id'] as String] ??= []).add(
        jsonDecode(row['payload'] as String),
      );
    }
    return jsonEncode(
      rows.where((row) => row['row_kind'] == 'tab').map((row) {
        final tab =
            jsonDecode(row['payload'] as String) as Map<String, dynamic>;
        return {...tab, 'entries': entries[tab['id']] ?? []};
      }).toList(),
    );
  }
  if (kind == 'list') {
    return jsonEncode(
      rows.map((row) => jsonDecode(row['payload'] as String)).toList(),
    );
  }
  if (kind == 'map') {
    return jsonEncode({
      for (final row in rows)
        row['row_id'] as String: jsonDecode(row['payload'] as String),
    });
  }
  if (kind == 'scalar' && rows.length == 1) {
    return rows.single['payload'] as String;
  }
  throw const FormatException('Invalid cached value');
}

Future<_EncodedCacheValue> _encodeOffIsolate(String key, String? raw) =>
    Isolate.run(() => _encodeCacheValue(key, raw));
Future<String> _decodeOffIsolate(
  String kind,
  List<Map<String, Object?>> rows,
) => Isolate.run(() => _decodeCacheValue(kind, rows));
Future<List<Map<String, dynamic>>> _decodePageOffIsolate(List<String> values) =>
    Isolate.run(
      () =>
          values.map((raw) => jsonDecode(raw) as Map<String, dynamic>).toList(),
    );
