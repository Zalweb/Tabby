typedef LedgerRows = List<Map<String, dynamic>>;

/// Loads complete ID-reconciled history in bounded server requests. No partial
/// response is published as a complete ledger or used for group obligations.
class LedgerPageLoader {
  LedgerPageLoader({
    required this.headers,
    required this.history,
    required this.balances,
  });
  final Future<LedgerRows> Function(String? after, int limit) headers;
  final Future<Map<String, dynamic>> Function(
    List<String> tabs,
    String kind,
    String? after,
    int limit,
  )
  history;
  final Future<Map<String, dynamic>> Function(List<String> tabs) balances;
  static const headerLimit = 100, historyLimit = 200;

  Future<LedgerRows> load(String actor) async {
    final rows = <String, Map<String, dynamic>>{};
    String? after;
    while (true) {
      final page = await headers(after, headerLimit);
      if (page.length > headerLimit) {
        throw const FormatException('Oversized tab page');
      }
      for (final row in page) {
        final id = row['id'];
        if (id is! String ||
            id.isEmpty ||
            (after != null && id.compareTo(after) <= 0) ||
            rows.containsKey(id)) {
          throw const FormatException('Invalid tab cursor');
        }
        rows[id] = {
          ...row,
          'transactions': <Map<String, dynamic>>[],
          'payments': <Map<String, dynamic>>[],
        };
        after = id;
      }
      if (page.length < headerLimit) break;
    }
    final ids = rows.keys.toList();
    for (var offset = 0; offset < ids.length; offset += headerLimit) {
      final batch = ids.skip(offset).take(headerLimit).toList();
      for (final kind in ['transactions', 'payments']) {
        after = null;
        final seen = <String>{};
        while (true) {
          final result = await history(batch, kind, after, historyLimit);
          _scope(result, actor);
          if (result['kind'] != kind ||
              result['records'] is! List ||
              (result['records'] as List).length > historyLimit) {
            throw const FormatException('Invalid history page');
          }
          String? last;
          for (final value in result['records'] as List) {
            final row = Map<String, dynamic>.from(value as Map);
            final id = row['id'], tab = row['tab_id'];
            if (id is! String ||
                !batch.contains(tab) ||
                (after != null && id.compareTo(after) <= 0) ||
                (last != null && id.compareTo(last) <= 0) ||
                !seen.add(id)) {
              throw const FormatException('Invalid history identity');
            }
            (rows[tab]![kind] as List).add(row);
            last = id;
          }
          final next = result['next_cursor'];
          if (next == null) break;
          if (next is! String ||
              next != last ||
              (after != null && next.compareTo(after) <= 0)) {
            throw const FormatException('Nonadvancing history cursor');
          }
          after = next;
        }
      }
      final result = await balances(batch);
      _scope(result, actor);
      final values = result['balances'];
      if (values is! List || values.length != batch.length) {
        throw const FormatException('Incomplete balances');
      }
      final seen = <String>{};
      for (final value in values) {
        final row = Map<String, dynamic>.from(value as Map);
        if (!batch.contains(row['tab_id']) ||
            !seen.add(row['tab_id'] as String) ||
            row['net_balance_centavos'] is! int) {
          throw const FormatException('Invalid balance');
        }
        rows[row['tab_id']]!['net_balance_centavos'] =
            row['net_balance_centavos'];
      }
    }
    return rows.values.toList();
  }

  void _scope(Map<String, dynamic> result, String actor) {
    if (result['version'] != 1 || result['account_id'] != actor) {
      throw const FormatException('Ledger scope mismatch');
    }
  }
}
