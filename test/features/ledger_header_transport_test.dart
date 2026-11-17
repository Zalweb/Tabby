import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tabby/features/tabs/data/ledger_page_loader.dart';
import 'package:tabby/features/tabs/data/supabase_tabby_repository.dart';

void main() {
  test('actual header requests load every ascending cursor page', () async {
    String id(int n) =>
        '${n.toString().padLeft(8, '0')}-0000-4000-8000-000000000000';
    final ids = List.generate(101, id);
    final requests = <Uri>[];
    final client = SupabaseClient(
      'https://synthetic.invalid',
      'synthetic-public-key',
      httpClient: MockClient((request) async {
        requests.add(request.url);
        final query = request.url.queryParameters;
        expect(query['status'], 'neq.archived');
        final after = query['id']?.substring(3);
        final page = ids
            .where((id) => after == null || id.compareTo(after) > 0)
            .toList();
        if (query['order']!.contains('.desc.')) {
          page.sort((a, b) => b.compareTo(a));
        }
        return http.Response(
          jsonEncode(
            page
                .take(int.parse(query['limit']!))
                .map((id) => {'id': id})
                .toList(),
          ),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    final loader = LedgerPageLoader(
      headers: (after, limit) =>
          SupabaseTabbyRepository.fetchTabHeaderPage(client, after, limit),
      history: (_, kind, __, ___) async => {
        'version': 1,
        'account_id': 'actor',
        'kind': kind,
        'records': [],
        'next_cursor': null,
      },
      balances: (tabs) async => {
        'version': 1,
        'account_id': 'actor',
        'balances': tabs
            .map((id) => {'tab_id': id, 'net_balance_centavos': 0})
            .toList(),
      },
    );
    final rows = await loader.load('actor');
    expect(rows.map((row) => row['id']), ids);
    expect(requests, hasLength(2));
    expect(
      requests.every(
        (uri) => uri.queryParameters['order'] == 'id.asc.nullslast',
      ),
      isTrue,
    );
    expect(requests.last.queryParameters['id'], 'gt.${id(99)}');
  });
}
