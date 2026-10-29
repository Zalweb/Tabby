import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/config/supabase_config.dart';

void main() {
  var projectRoot = Directory.current;
  while (!File('${projectRoot.path}/pubspec.yaml').existsSync() &&
      projectRoot.path != projectRoot.parent.path) {
    projectRoot = projectRoot.parent;
  }

  test('mobile RPC names match the atomic money SQL contract', () {
    expect(SupabaseConfig.rpcCreateExpenseAtomic, 'create_expense_atomic');
    expect(SupabaseConfig.rpcSubmitPayment, 'submit_payment');
    expect(SupabaseConfig.rpcConfirmPayment, 'confirm_payment');
  });

  test('migration and schema expose the same payment RPC signatures', () {
    final migration = File(
      '${projectRoot.path}/supabase/migrations/'
      '20261029000001_atomic_money_contract.sql',
    ).readAsStringSync();
    final schema = File(
      '${projectRoot.path}/supabase/schema_all.sql',
    ).readAsStringSync();

    for (final signature in [
      'create_expense_atomic',
      'submit_payment',
      'confirm_payment',
      'recipient_user_id',
    ]) {
      expect(migration, contains(signature));
      expect(schema, contains(signature));
    }

    expect(
      migration,
      contains(
        'p_submitted_by_user_id UUID,',
      ),
    );
    expect(
      migration,
      contains(
        'Only the payment recipient can confirm this payment',
      ),
    );
  });

  test('participant identity hardening rejects duplicate allocations', () {
    final migration = File(
      '${projectRoot.path}/supabase/migrations/'
      '20261029000002_participant_identity_hardening.sql',
    ).readAsStringSync();
    final schema = File(
      '${projectRoot.path}/supabase/schema_all.sql',
    ).readAsStringSync();

    for (final sql in [migration, schema]) {
      expect(sql, contains('validate_transaction_participant_identity'));
      expect(
        sql,
        contains('A transaction participant identity may appear only once'),
      );
      expect(sql, contains('trigger_validate_transaction_participant_identity'));
      expect(
        sql,
        contains('trigger_assert_transaction_participant_identities'),
      );
    }
  });

  test('migration version prefixes are unique', () {
    // Shipped in main before ordering was enforced; renaming applied
    // migrations would make the CLI re-run them.
    const legacyDuplicates = {'20260917000002'};

    final migrations = Directory('${projectRoot.path}/supabase/migrations')
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .where((name) => name.endsWith('.sql'))
        .toList();

    final versions = <String, List<String>>{};
    for (final name in migrations) {
      versions.putIfAbsent(name.split('_').first, () => []).add(name);
    }

    for (final entry in versions.entries) {
      if (entry.value.length < 2) continue;
      expect(
        legacyDuplicates,
        contains(entry.key),
        reason: 'Migration version ${entry.key} is used by '
            '${entry.value.join(', ')}',
      );
    }
  });
}
