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
}
