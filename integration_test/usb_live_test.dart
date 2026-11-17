import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Credentials belong to a dedicated synthetic fixture account, never a real user.
// This is a bounded Auth/API smoke test, not complete financial acceptance.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('live Auth issues a session and serves the fixture profile', (
    tester,
  ) async {
    const url = String.fromEnvironment('SUPABASE_URL');
    const key = String.fromEnvironment('SUPABASE_ANON_KEY');
    const email = String.fromEnvironment('TABBY_TEST_EMAIL');
    const password = String.fromEnvironment('TABBY_TEST_PASSWORD');
    if (!const bool.fromEnvironment('TABBY_USB_TEST') ||
        !const bool.fromEnvironment('TABBY_LIVE_TEST') ||
        !url.startsWith('https://') ||
        Uri.parse(url).host == 'ziaqrkagsvozhotremsx.supabase.co' ||
        key.isEmpty ||
        email.isEmpty ||
        password.isEmpty) {
      fail(
        'Explicit migrated HTTPS backend and synthetic Auth account required.',
      );
    }
    final client = SupabaseClient(url, key);
    try {
      final signedIn = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      expect(signedIn.session, isNotNull);
      final current = await client.auth.getUser();
      expect(current.user?.id, signedIn.user?.id);
      expect(current.user!.appMetadata['tabby_azure_fixture'], isTrue);
      final profile = await client
          .from('users')
          .select('id')
          .eq('id', current.user!.id)
          .single();
      expect(profile['id'], current.user!.id);
      // Review tables are deliberately RPC-only. A nonparty RPC call proves
      // the migration contract exists while keeping all real history private.
      await expectLater(
        client.rpc(
          'expense_review_state_v1',
          params: {'p_transaction_id': '00000000-0000-4000-8000-000000000000'},
        ),
        throwsA(
          isA<PostgrestException>()
              .having((error) => error.code, 'party check', '42501')
              .having(
                (error) => error.message,
                'review RPC exists and authorizes its caller',
                'Expense party required',
              ),
        ),
      );
      await expectLater(
        client.from('expense_acknowledgments').select('id').limit(0),
        throwsA(
          isA<PostgrestException>().having(
            (error) => error.code,
            'review table remains RPC-only',
            '42501',
          ),
        ),
      );
      await expectLater(
        client.from('m2_feature_flags').select('feature').limit(0),
        throwsA(
          isA<PostgrestException>().having(
            (error) => error.code,
            'server denies client access to rollout flags',
            '42501',
          ),
        ),
      );
      debugPrint('LIVE_CHECK fixtureAuthAndAuthorization=true');
      await _verifyFixtureRealtime(client, current.user!.id);
    } finally {
      await client.auth.signOut(scope: SignOutScope.local);
      await client.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

Future<void> _verifyFixtureRealtime(SupabaseClient client, String actor) async {
  final before = await client
      .from('users')
      .select('display_name')
      .eq('id', actor)
      .single();
  final marker = 'Azure QA ${DateTime.now().microsecondsSinceEpoch}';
  final subscribed = Completer<void>();
  final replicationReady = Completer<void>();
  final delivered = Completer<void>();
  final channel = client
      .channel(
        'azure-tablet-${DateTime.now().microsecondsSinceEpoch}',
        opts: const RealtimeChannelConfig(replicationReady: true),
      )
      .onSystemEvents((payload) {
        if (payload is Map &&
            payload['extension'] == 'system' &&
            payload['status'] == 'ok' &&
            !replicationReady.isCompleted) {
          replicationReady.complete();
        }
      })
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'users',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: actor,
        ),
        callback: (payload) {
          if (payload.newRecord['id'] == actor &&
              payload.newRecord['display_name'] == marker &&
              !delivered.isCompleted) {
            delivered.complete();
          }
        },
      );
  var changed = false;
  try {
    channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed &&
          !subscribed.isCompleted) {
        subscribed.complete();
      } else if (status == RealtimeSubscribeStatus.channelError &&
          !subscribed.isCompleted) {
        subscribed.completeError(StateError('Realtime subscription failed.'));
      }
    });
    await subscribed.future.timeout(const Duration(seconds: 30));
    debugPrint('LIVE_CHECK realtimeJoined=true');
    // Joining the WebSocket precedes CDC setup. Wait for the explicit
    // replication-ready event before publishing the fixture change.
    await replicationReady.future.timeout(const Duration(seconds: 30));
    debugPrint('LIVE_CHECK replicationReady=true');
    changed = true;
    final acknowledged = await client.rpc(
      'update_profile_v2',
      params: {
        'p_expected_owner': actor,
        'p_changes': {'display_name': marker},
      },
    );
    expect(
      acknowledged is Map &&
          acknowledged['id'] == actor &&
          acknowledged['display_name'] == marker,
      isTrue,
      reason: 'The fixture profile RPC must acknowledge its saved marker.',
    );
    final saved = await client
        .from('users')
        .select('display_name')
        .eq('id', actor)
        .single();
    expect(saved['display_name'] == marker, isTrue);
    debugPrint('LIVE_CHECK profileAckAndReadback=true');
    await delivered.future.timeout(const Duration(seconds: 30));
    debugPrint('LIVE_CHECK realtimeUpdateDelivered=true');
  } finally {
    try {
      if (changed) {
        await client.rpc(
          'update_profile_v2',
          params: {
            'p_expected_owner': actor,
            'p_changes': {'display_name': before['display_name']},
          },
        );
        final restored = await client
            .from('users')
            .select('display_name')
            .eq('id', actor)
            .single();
        expect(restored['display_name'] == before['display_name'], isTrue);
        debugPrint('LIVE_CHECK fixtureProfileRestored=true');
      }
    } finally {
      await client.removeChannel(channel);
    }
  }
}
