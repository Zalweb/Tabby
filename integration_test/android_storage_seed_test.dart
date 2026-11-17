import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tabby/features/tabs/data/ledger_storage_factory_native.dart';

import 'native_storage_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('TABBY_USB_TEST')) {
    throw StateError('Native storage fixtures require the isolated package.');
  }
  testWidgets(
    'native ledger seeds 100 tabs 10000 entries and durable operations',
    (tester) async {
      await tester.runAsync(() async {
        final store = NativeLedgerCacheStorage(
          directory: nativeFixtureDirectory,
        );
        try {
          final watch = Stopwatch()..start();
          await store.write(
            key: nativeCacheKey,
            value: jsonEncode(nativeHistoryFixture()),
          );
          await const FlutterSecureStorage().write(
            key: nativeQueueKey,
            value: jsonEncode([
              {
                'operation_id': nativeOperation,
                'type': 'add_expense',
                'total_amount_centavos': 100,
              },
            ]),
          );
          final queue =
              jsonDecode((await store.read(key: nativeQueueKey))!) as List;
          expect(queue.single['operation_id'], nativeOperation);
          expect(
            await store.read(key: 'tabby_cached_tabs_other-native-owner'),
            isNull,
          );
          debugPrint(
            'NATIVE_STORAGE seedTabs=100 seedEntries=10000 writeMs=${watch.elapsedMilliseconds} encryptedQueue=true',
          );
        } finally {
          await store.close();
        }
      });
    },
  );
}
