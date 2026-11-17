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

  test('pair helper is internal in both upgrade and fresh-install SQL', () {
    final patch = File('${root.path}/supabase/migrations/'
            '20261031000001_restrict_pair_outstanding.sql')
        .readAsStringSync();
    final schema =
        File('${root.path}/supabase/schema_all.sql').readAsStringSync();
    expect(patch, contains('public.get_pair_outstanding(UUID, UUID, UUID)'));
    expect(patch, contains('FROM PUBLIC, anon, authenticated'));
    expect(schema.replaceAll('\r\n', '\n'),
        contains(patch.replaceAll('\r\n', '\n').trim()));
  });

  String migration(String name) =>
      File('${root.path}/supabase/migrations/$name').readAsStringSync();

  String schemaSnapshot() =>
      File('${root.path}/supabase/schema_all.sql').readAsStringSync();

  String withoutComments(String sql) => sql
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  group('authorization hardening migration', () {
    late String sql;

    setUpAll(() {
      sql = withoutComments(
        migration('20261030000004_authorization_hardening.sql'),
      );
    });

    test('removes the open profile read policy', () {
      expect(
        sql,
        contains(
          'DROP POLICY IF EXISTS "Users can view all registered user profiles"',
        ),
      );
    });

    test('replaces the bucket-wide payment proof policies', () {
      expect(
        sql,
        contains(
          'DROP POLICY IF EXISTS "Authenticated users can view payment proofs"',
        ),
      );
      expect(
        sql,
        contains(
          'DROP POLICY IF EXISTS "Authenticated users can upload payment proofs"',
        ),
      );
      expect(sql, contains('"Uploaders can upload payment proofs"'));
      expect(sql, contains('(storage.foldername(name))[1] = auth.uid()::text'));
    });

    test('scopes proof reads to the uploader or an involved tab', () {
      expect(sql, contains('tx.receipt_url = storage.objects.name'));
      expect(sql, contains('public.is_tab_member(tx.tab_id, auth.uid())'));
    });

    test(
        'qualifies tab membership rows instead of comparing a column to itself',
        () {
      expect(sql, isNot(contains('tm.tab_id = tm.tab_id')));
      expect(sql, isNot(contains('tm.tab_id = tab_id')));
      expect(sql, contains('admin.tab_id = tab_members.tab_id'));
    });

    test('restricts membership changes to tab admins or self-leave', () {
      expect(sql, contains('"Tab admins can update tab membership"'));
      expect(sql, contains('"Tab admins or the member can remove membership"'));
      expect(sql, contains('user_id = auth.uid()'));
    });

    test('locks the contact tab RPC to the authenticated owner', () {
      expect(sql, contains('p_owner_id IS DISTINCT FROM auth.uid()'));
      expect(sql, contains('SET search_path = public, pg_temp'));
      expect(
        sql,
        contains(
          'REVOKE ALL ON FUNCTION public.get_or_create_contact_tab(uuid, text) FROM PUBLIC, anon',
        ),
      );
      expect(
        sql,
        contains(
          'GRANT EXECUTE ON FUNCTION public.get_or_create_contact_tab(uuid, text) TO authenticated',
        ),
      );
    });

    test('guards receipt references against foreign paths and remote URLs', () {
      expect(sql, contains('Receipt attachments must belong to the uploader'));
      expect(sql, contains('Receipt attachments must be uploaded files'));
    });
  });

  group('schema snapshot stays aligned', () {
    test('no longer grants a blanket profile read', () {
      final snapshot = schemaSnapshot();
      expect(
        snapshot.split('\n').where(
              (line) =>
                  line.trimLeft().startsWith('CREATE POLICY') &&
                  line.contains('view all registered user profiles'),
            ),
        isEmpty,
      );
    });

    test('carries the hardened membership and RPC definitions', () {
      final snapshot = schemaSnapshot();
      expect(snapshot, isNot(contains('tm.tab_id = tm.tab_id')));
      expect(snapshot, contains('"Tab admins can update tab membership"'));
      expect(
        snapshot,
        contains('CREATE OR REPLACE FUNCTION public.get_or_create_contact_tab'),
      );
      expect(
        snapshot,
        contains('Receipt attachments must belong to the uploader'),
      );
    });
  });
}
