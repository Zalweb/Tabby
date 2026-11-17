import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Directory _projectRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/pubspec.yaml').existsSync() &&
      dir.path != dir.parent.path) {
    dir = dir.parent;
  }
  return dir;
}

void main() {
  final root = _projectRoot();

  String migration(String name) =>
      File('${root.path}/supabase/migrations/$name').readAsStringSync();

  String withoutComments(String sql) => sql
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  test('reconciliation allows every notification type the triggers emit', () {
    final sql = migration('20261030000001_production_reconciliation.sql');

    expect(sql, contains("'expense_added'"));
    expect(sql, contains("'tab_reminder'"));
    expect(sql, contains('notifications_notification_type_check'));
    for (final legacyType in [
      'debt_created',
      'payment_submitted',
      'payment_confirmed',
      'report_filed',
    ]) {
      expect(sql, contains("'$legacyType'"));
    }
  });

  test('reconciliation writes reminder activity against live column names', () {
    final sql = withoutComments(
        migration('20261030000001_production_reconciliation.sql'));

    expect(sql, contains('actor_user_id, tab_id, event_type'));
    expect(sql, isNot(contains('action_type')));
    expect(sql, isNot(contains('description,')));
    expect(sql, contains("'REMINDER_SENT'"));
  });

  test('internal money helpers stay closed to unauthenticated roles', () {
    final reconciliation =
        migration('20261030000001_production_reconciliation.sql');
    final restriction =
        migration('20261030000002_restrict_unchecked_balance.sql');

    expect(
      reconciliation,
      contains(
        'REVOKE ALL ON FUNCTION public.calculate_user_tab_balance_unchecked',
      ),
    );
    expect(
      reconciliation,
      contains('REVOKE ALL ON FUNCTION public.validate_transaction_split'),
    );
    expect(restriction, contains('FROM PUBLIC, anon, authenticated'));
  });

  test('acceptance scripts ship with the migrations that they prove', () {
    for (final script in [
      '01_happy_path.sql',
      '02_overpayment.sql',
      '03_duplicate_identity.sql',
    ]) {
      final file = File('${root.path}/supabase/tests/acceptance/$script');
      expect(file.existsSync(), isTrue, reason: '$script is missing');
      expect(file.readAsStringSync(), contains('ACCEPTANCE_OK'));
    }
  });
}
