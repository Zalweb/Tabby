import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tabby/core/services/form_draft_store.dart';
import 'package:tabby/core/services/pin_protection_service.dart';
import 'package:tabby/features/tabs/data/ledger_storage_factory_native.dart';

import 'native_storage_fixture.dart';

const _owner = 'signed-storage-upgrade-fixture';
const _cache = 'tabby_cached_tabs_$_owner';
const _queue = 'tabby_pending_ops_$_owner';
const _proof = 'tabby_signed_storage_upgrade_proof_v1';
const _operation = 'signed-storage-durable-operation';
const _phase = String.fromEnvironment('TABBY_SIGNED_STORAGE_FIXTURE');

void _require(bool condition, String reason) {
  // Assertions are disabled in release. Acceptance must fail explicitly in AOT.
  if (!condition) throw StateError(reason);
}

Future<void> _verifyStorage() async {
  const secure = FlutterSecureStorage();
  const drafts = FormDraftStore();
  final store = NativeLedgerCacheStorage();
  try {
    final history = jsonEncode(nativeHistoryFixture());
    final queue = jsonEncode([
      {
        'operation_id': _operation,
        'type': 'add_expense',
        'total_amount_centavos': 101,
      },
    ]);
    if (_phase == 'seed') {
      await store.write(key: _cache, value: history);
      await store.write(key: _queue, value: queue);
      await drafts.write(_owner, 'signed-upgrade', {
        'amountCentavos': 101,
        'operation': _operation,
      });
      await PinProtectionService().setPin(_owner, '7391');
      final key = await secure.read(key: NativeLedgerCacheStorage.keyName);
      _require(key != null, 'Native encryption key missing after seed');
      await secure.write(
        key: _proof,
        value: sha256.convert(utf8.encode(key!)).toString(),
      );
    }
    final saved = await store.read(key: _cache);
    _require(saved != null, 'History missing');
    _require(
      jsonEncode(jsonDecode(saved!)) == history,
      'History IDs, centavos, ordering or values changed',
    );
    _require(
      await store.read(key: _queue) == queue,
      'Queued operation changed',
    );
    _require(
      await store.read(key: 'tabby_cached_tabs_signed-storage-outsider') ==
          null,
      'Owner isolation failed',
    );
    final draft = await drafts.read(_owner, 'signed-upgrade');
    _require(
      draft?['amountCentavos'] == 101 && draft?['operation'] == _operation,
      'Encrypted draft changed',
    );
    _require(
      await PinProtectionService().verifyPin(_owner, '7391'),
      'PIN verifier missing or changed',
    );
    final key = await secure.read(key: NativeLedgerCacheStorage.keyName);
    _require(
      key != null &&
          await secure.read(key: _proof) ==
              sha256.convert(utf8.encode(key)).toString(),
      'Secure encryption key identity changed',
    );
  } finally {
    await store.close();
  }
  final folder = await getApplicationSupportDirectory();
  final encrypted = await File('${folder.path}/tabby-ledger-v1.sqlite')
      .readAsBytes();
  _require(
    !latin1.decode(encrypted).contains('Synthetic encrypted native expense'),
    'Plaintext financial cache found',
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _require(kReleaseMode, 'This rehearsal requires actual release AOT');
  _require(Platform.isAndroid, 'Android rehearsal only');
  _require(
    _phase == 'seed' || _phase == 'verify',
    'Explicit fixture phase needed',
  );
  try {
    await _verifyStorage();
    debugPrint(
      'SIGNED_STORAGE phase=$_phase passed=true historyEntries=10000 '
      'durableOperation=true draft=true pin=true sameKey=true ownerIsolated=true',
    );
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Signed storage $_phase passed')),
        ),
      ),
    );
  } catch (_) {
    debugPrint('SIGNED_STORAGE phase=$_phase passed=false');
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Signed storage check failed')),
        ),
      ),
    );
    rethrow;
  }
}
