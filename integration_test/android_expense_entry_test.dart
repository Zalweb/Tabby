import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tabby/features/tabs/data/ledger_cache_storage.dart';
import 'package:tabby/features/tabs/data/ledger_key_value_store.dart';
import 'package:tabby/features/tabs/data/tabby_local_cache.dart';

import '../test/features/expense_entry_flow_test.dart' as cases;

// Real Android form/engine, explicit synthetic storage/ledger. Native encrypted
// SQLite is exercised in the separate storage target without these overrides.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('TABBY_USB_TEST') ||
      !const bool.fromEnvironment('TABBY_ENTRY_TEST')) {
    throw StateError(
      'Expense entry fixtures require the isolated entry package.',
    );
  }
  LedgerCacheStorage.debugOverride = const SecureLedgerKeyValueStore();
  TabbyLocalCache.debugInlineCodec = true;
  // WidgetTester.enterText injects editing values. Do not let the real Android
  // IME concurrently echo its previous value over that controlled input.
  setUp(() => binding.testTextInput.register());
  tearDown(() => binding.testTextInput.unregister());
  cases.main();
}
