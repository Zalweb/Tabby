import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:tabby/core/config/supabase_config.dart';
import 'package:tabby/features/tabs/data/supabase_tabby_repository.dart';
import 'package:tabby/features/tabs/data/tabby_local_cache.dart';
import 'package:tabby/features/tabs/domain/models.dart';

const actor = '00000000-0000-4000-8000-000000000001';
const other = '00000000-0000-4000-8000-000000000002';
const tabId = '00000000-0000-4000-8000-000000000003';
const savedId = '00000000-0000-4000-8000-000000000004';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var contact = false;
  final commands = <Map<String, dynamic>>[];
  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((request) async {
      http.Response reply(Object value, int status) => http.Response(
        jsonEncode(value),
        status,
        request: request,
        headers: {'content-type': 'application/json'},
      );
      if (request.method == 'GET' &&
          request.url.path == '/rest/v1/tab_members') {
        return reply([
          {'user_id': actor, 'contact_id': null},
          {if (contact) 'contact_id': other else 'user_id': other},
        ], 200);
      }
      if (request.method == 'POST' &&
          request.url.path == '/rest/v1/rpc/create_expense_v1') {
        final params = jsonDecode(request.body) as Map<String, dynamic>;
        final command = Map<String, dynamic>.from(params['p_command'] as Map);
        commands.add(command);
        final sum = (command['p_participants'] as List).fold<int>(
          0,
          (sum, p) => sum + (p['share_amount_centavos'] as int),
        );
        if (sum != command['p_total_amount_centavos']) {
          return reply({
            'message': 'Synthetic sum rejection',
            'code': 'P0001',
            'details': null,
            'hint': null,
          }, 400);
        }
        return reply(savedId, 200);
      }
      throw StateError(
        'Unexpected transport request: ${request.method} ${request.url.path}',
      );
    });
    // Exercise the real SDK/repository wire builder with a controlled transport.
    // This debug actor fixture does not assert real authentication or server SQL.
    await Supabase.initialize(
      url: 'https://synthetic.invalid',
      publishableKey: 'synthetic-public-key',
      httpClient: client,
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
    );
    await SupabaseConfig.initialize(
      url: 'https://synthetic.invalid',
      anonKey: 'synthetic-public-key',
      debug: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 1));
    SupabaseConfig.debugUserIdOverride = actor;
  });
  tearDownAll(() async {
    SupabaseConfig.debugUserIdOverride = null;
    await Supabase.instance.dispose();
  });
  setUp(() {
    commands.clear();
    FlutterSecureStorage.setMockInitialValues({});
  });
  for (final isContact in [false, true]) {
    for (final ownShare in [0, 15000, 45000]) {
      for (final ownerPaid in [false, true]) {
        test(
          'wire shares contact=$isContact own=$ownShare ownerPaid=$ownerPaid sum exactly once',
          () async {
            contact = isContact;
            final operation = const Uuid().v4();
            await TabbyLocalCache.enqueuePendingOp({
              'operation_id': operation,
              'type': 'add_expense',
              'local_entry_id': 'entry-$operation',
            }, userId: actor);
            final result = await SupabaseTabbyRepository.instance.logExpense(
              operationId: operation,
              tabId: tabId,
              title: 'Synthetic custom allocation',
              totalAmountCentavos: 45000,
              category: ExpenseCategory.other,
              paidByUserId: ownerPaid ? actor : other,
              myShareCentavos: ownShare,
              counterpartShareCentavos: 45000 - ownShare,
              currentUserId: actor,
              counterpartId: other,
            );
            expect(result, savedId);
            expect(commands, hasLength(1));
            final parts = (commands.single['p_participants'] as List)
                .cast<Map>();
            expect(parts, hasLength(2));
            final own = parts.singleWhere((p) => p['user_id'] == actor);
            final counterpart = parts.singleWhere(
              (p) => p[isContact ? 'contact_id' : 'user_id'] == other,
            );
            expect(own['share_amount_centavos'], ownShare);
            expect(counterpart['share_amount_centavos'], 45000 - ownShare);
            expect(
              parts.singleWhere(
                (p) => p['participant_role'] == 'payer',
              )[ownerPaid
                  ? 'user_id'
                  : isContact
                  ? 'contact_id'
                  : 'user_id'],
              ownerPaid ? actor : other,
            );
          },
        );
      }
    }
  }
}
