import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:sqlite3/sqlite3.dart';

// Synthetic 100 tabs x 100 entries. This measures Windows engine/I/O cost,
// not Android frame timing, Keystore latency or low-memory acceptance.
void main() {
  final random = Random.secure();
  final key = List.generate(
    32,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final root = Directory(
    '.dart_tool/storage-benchmark-${DateTime.now().millisecondsSinceEpoch}',
  )..createSync(recursive: true);
  final rows = [
    for (var tab = 0; tab < 100; tab++)
      for (var entry = 0; entry < 100; entry++)
        {
          'id': 'entry-$tab-$entry',
          'tab_id': 'tab-$tab',
          'title': 'Synthetic history fixture $entry',
          'category': 'food',
          'total_amount_centavos': 10001 + entry,
          'my_share_centavos': 5000,
          'counterpart_share_centavos': 5001 + entry,
          'paid_by_user_id': 'fixture-owner',
          'paid_by_name': 'Synthetic owner',
          'date': '2026-11-01T12:00:00Z',
          'status': 'acknowledged',
          'receipt_url': null,
          'participants': <Object>[],
        },
  ];
  final output = <String, Object>{
    'platform': Platform.operatingSystem,
    'sqlite': sqlite3.version.toString(),
    'tabs': 100,
    'entries': rows.length,
  };
  final jsonFile = File('${root.path}/synthetic-legacy.json');
  final timer = Stopwatch()..start();
  for (var i = 0; i < 30; i++) {
    rows[i]['title'] = 'Synthetic history fixture update $i';
    jsonFile.writeAsStringSync(jsonEncode(rows), flush: true);
  }
  timer.stop();
  output['legacy_30_full_json_writes_ms'] = timer.elapsedMilliseconds;
  output['legacy_bytes'] = jsonFile.lengthSync();
  for (final encrypted in [false, true]) {
    final file = File(
      '${root.path}/${encrypted ? 'encrypted' : 'plain'}.sqlite',
    );
    final db = sqlite3.open(file.path);
    final cipher = db.select('PRAGMA cipher');
    if (cipher.isEmpty) throw StateError('Encryption runtime unavailable');
    if (encrypted) db.execute("PRAGMA key = '$key'");
    output['cipher'] = cipher.first.values.first.toString();
    db.execute('PRAGMA journal_mode=WAL');
    db.execute('PRAGMA synchronous=FULL');
    db.execute(
      'CREATE TABLE entries(id TEXT PRIMARY KEY, tab_id TEXT NOT NULL, payload TEXT NOT NULL)',
    );
    db.execute('CREATE INDEX entry_tab ON entries(tab_id, id)');
    final insert = db.prepare('INSERT INTO entries VALUES(?,?,?)');
    timer
      ..reset()
      ..start();
    db.execute('BEGIN');
    for (final row in rows) {
      insert.execute([row['id'], row['tab_id'], jsonEncode(row)]);
    }
    db.execute('COMMIT');
    timer.stop();
    final name = encrypted ? 'encrypted' : 'plain';
    output['${name}_initial_10000_ms'] = timer.elapsedMilliseconds;
    insert.close();
    final update = db.prepare('UPDATE entries SET payload=? WHERE id=?');
    timer
      ..reset()
      ..start();
    for (var i = 0; i < 30; i++) {
      rows[i]['title'] = 'Synthetic history fixture changed $name $i';
      db.execute('BEGIN');
      update.execute([jsonEncode(rows[i]), rows[i]['id']]);
      db.execute('COMMIT');
    }
    timer.stop();
    output['${name}_30_single_row_updates_us'] = timer.elapsedMicroseconds;
    update.close();
    timer
      ..reset()
      ..start();
    for (var i = 0; i < 100; i++) {
      final page = db.select(
        'SELECT payload FROM entries WHERE tab_id=? ORDER BY id LIMIT 25',
        ['tab-$i'],
      );
      if (page.length != 25) throw StateError('Wrong page');
      for (final row in page) {
        jsonDecode(row['payload'] as String);
      }
    }
    timer.stop();
    output['${name}_100_pages_of_25_ms'] = timer.elapsedMilliseconds;
    db.close();
    output['${name}_file_bytes'] = file.lengthSync();
    if (encrypted) {
      final raw = file.readAsBytesSync();
      if (latin1.decode(raw).contains('Synthetic history fixture')) {
        throw StateError('Plaintext found');
      }
      final noKey = sqlite3.open(file.path);
      var rejected = false;
      try {
        noKey.select('SELECT * FROM entries LIMIT 1');
      } catch (_) {
        rejected = true;
      }
      noKey.close();
      if (!rejected) throw StateError('Unkeyed read accepted');
      final reopen = sqlite3.open(file.path)..execute("PRAGMA key = '$key'");
      if (reopen
              .select('SELECT count(*) AS count FROM entries')
              .single['count'] !=
          10000) {
        throw StateError('Keyed reopen failed');
      }
      reopen.close();
      output['encrypted_unkeyed_read_rejected'] = rejected;
      output['encrypted_keyed_reopen_rows'] = 10000;
    }
  }
  final report = const JsonEncoder.withIndent('  ').convert(output);
  File('${root.path}/summary.json').writeAsStringSync(report);
  stdout.writeln(report);
}
