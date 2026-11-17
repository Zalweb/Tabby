import 'ledger_key_value_store.dart';

LedgerKeyValueStore createLedgerStorage() => const SecureLedgerKeyValueStore();
