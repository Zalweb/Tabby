import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/tabs/data/ledger_cache_storage.dart';
import 'package:tabby/features/tabs/data/ledger_key_value_store.dart';
import 'package:tabby/features/tabs/data/tabby_local_cache.dart';

/// Platform storage is explicitly mocked for widget/unit tests. Device storage
/// and restored key behavior require separate Android acceptance.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});
  LedgerCacheStorage.debugOverride = const SecureLedgerKeyValueStore();
  TabbyLocalCache.debugInlineCodec = true;
  await testMain();
}
