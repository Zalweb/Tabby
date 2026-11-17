import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tabby/features/tabs/data/supabase_tabby_repository.dart';

const a = '00000000-0000-4000-8000-000000000001';
const b = '00000000-0000-4000-8000-000000000002';
void main() {
  test('both actor orders issue read-only ID pair lookup and reuse empty active tab', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://synthetic.invalid',
      'synthetic-public',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode([
            {'id': 'shared', 'status': 'active'},
          ]),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    for (final pair in [
      [a, b],
      [b, a],
    ]) {
      expect(
        await SupabaseTabbyRepository.readSharedTabId(client, pair[0], pair[1]),
        'shared',
      );
      final request = requests.last;
      expect(request.method, 'GET');
      expect(request.url.path, '/rest/v1/tabs');
      expect(request.url.queryParameters['tab_type'], 'eq.individual');
      final filter = request.url.queryParameters['or']!;
      expect(filter, contains('and(user_a.eq.$a,user_b.eq.$b)'));
      expect(filter, contains('and(user_a.eq.$b,user_b.eq.$a)'));
      expect(filter, isNot(contains('display_name')));
    }
    expect(requests, hasLength(2));
  });
  for (final response in [
    [],
    [
      {'id': 'old', 'status': 'archived'},
    ],
    [
      {'id': 'one', 'status': 'active'},
      {'id': 'two', 'status': 'active'},
    ],
  ]) {
    test(
      'no relationship differs from unavailable or ambiguous relationship: $response',
      () async {
        final client = SupabaseClient(
          'https://synthetic.invalid',
          'synthetic-public',
          httpClient: MockClient(
            (request) async => http.Response(
              jsonEncode(response),
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            ),
          ),
        );
        addTearDown(client.dispose);
        final result = SupabaseTabbyRepository.readSharedTabId(client, a, b);
        if (response.isEmpty) {
          expect(await result, isNull);
        } else {
          await expectLater(result, throwsStateError);
        }
      },
    );
  }
  test('HTTP failure is not interpreted as no shared tab', () async {
    final client = SupabaseClient(
      'https://synthetic.invalid',
      'synthetic-public',
      httpClient: MockClient(
        (request) async => http.Response(
          '{"message":"offline","code":"503","details":null,"hint":null}',
          503,
          request: request,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(client.dispose);
    await expectLater(
      SupabaseTabbyRepository.readSharedTabId(client, a, b),
      throwsA(isA<PostgrestException>()),
    );
  });
}
