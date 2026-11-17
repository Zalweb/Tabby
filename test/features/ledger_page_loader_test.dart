import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/tabs/data/ledger_page_loader.dart';

void main() {
  String id(int n) => n.toString().padLeft(8, '0');
  test('100 tabs and 10000 entries load without N+1 balances or row-cap truncation', () async {
    var balanceCalls = 0, historyCalls = 0;
    final loader = LedgerPageLoader(
      headers: (after, limit) async =>
          after == null ? List.generate(100, (i) => {'id': id(i)}) : [],
      history: (tabs, kind, after, limit) async {
        historyCalls++;
        final start = after == null ? 0 : int.parse(after) + 1;
        final end = (start + limit).clamp(0, 10000);
        return {
          'version': 1,
          'account_id': 'actor',
          'kind': kind,
          'records': kind == 'payments'
              ? []
              : List.generate(
                  end - start,
                  (i) => {
                    'id': id(start + i),
                    'tab_id': id((start + i) ~/ 100),
                  },
                ),
          'next_cursor': kind == 'payments' || end == 10000
              ? null
              : id(end - 1),
        };
      },
      balances: (tabs) async {
        balanceCalls++;
        return {
          'version': 1,
          'account_id': 'actor',
          'balances': tabs
              .map((id) => {'tab_id': id, 'net_balance_centavos': 123})
              .toList(),
        };
      },
    );
    final result = await loader.load('actor');
    expect(result.length, 100);
    expect(result.expand((t) => t['transactions'] as List).length, 10000);
    expect(balanceCalls, 1);
    expect(historyCalls, 51);
    expect(result.every((row) => row['net_balance_centavos'] == 123), isTrue);
  });

  for (final failure in [
    'foreign',
    'repeated',
    'cursor',
    'oversized',
    'network',
    'balances',
  ]) {
    test('$failure page failure never publishes a partial ledger', () async {
      final loader = LedgerPageLoader(
        headers: (_, _) async => [
          {'id': 'tab'},
        ],
        history: (tabs, kind, after, limit) async {
          if (failure == 'network') throw StateError('offline');
          return {
            'version': 1,
            'account_id': failure == 'foreign' ? 'other' : 'actor',
            'kind': kind,
            'records': failure == 'oversized'
                ? List.filled(201, {'id': 'a', 'tab_id': 'tab'})
                : failure == 'repeated'
                ? [
                    {'id': 'a', 'tab_id': 'tab'},
                    {'id': 'a', 'tab_id': 'tab'},
                  ]
                : [
                    {'id': 'a', 'tab_id': 'tab'},
                  ],
            'next_cursor': failure == 'cursor' ? 'wrong' : null,
          };
        },
        balances: (_) async => {
          'version': 1,
          'account_id': 'actor',
          'balances': [],
        },
      );
      await expectLater(
        loader.load('actor'),
        throwsA(anyOf(isA<FormatException>(), isA<StateError>())),
      );
    });
  }
}
