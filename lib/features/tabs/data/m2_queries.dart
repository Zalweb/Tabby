import '../../../core/config/supabase_config.dart';

class M2Queries {
  M2Queries({required this.actor, required this.current, required this.rpc});
  factory M2Queries.production() {
    final stamp = SupabaseConfig.captureSession();
    return M2Queries(
      actor: stamp.accountId ?? '',
      current: () => SupabaseConfig.isCurrentSession(stamp),
      rpc: (name, args) => SupabaseConfig.client.rpc(name, params: args),
    );
  }
  final String actor;
  final bool Function() current;
  final Future<dynamic> Function(String, Map<String, dynamic>) rpc;
  Future<Map<String, dynamic>> read(
    String name,
    Map<String, dynamic> params, {
    Map<String, Object?> scope = const {},
  }) async {
    if (!const {
      'list_recurrences_v1',
      'list_contact_claims_v1',
      'find_claim_target_v1',
      'contact_claim_payments_page_v1',
      'contact_claim_preview_v1',
      'expense_review_state_v1',
      'expense_review_history_v1',
      'contact_claim_history_page_v1',
      'get_expense_split_v1',
    }.contains(name)) {
      throw UnsupportedError('Writes must use the shared queue.');
    }
    if (actor.isEmpty || !current()) {
      throw StateError('Account changed.');
    }
    final result = await rpc(name, params);
    if (!current()) {
      throw StateError('Account changed.');
    }
    if (result is! Map ||
        result['account_id'] != actor ||
        !scope.entries.every((e) => result[e.key] == e.value)) {
      throw const FormatException('Read scope mismatch.');
    }
    if (result['records'] != null) {
      final records = result['records'];
      String? previous = params['p_after'] as String?;
      if (records is! List || records.length > 50) {
        throw const FormatException('Invalid page size.');
      }
      for (final row in records) {
        if (row is! Map ||
            row['id'] is! String ||
            !RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
            ).hasMatch(row['id']) ||
            (previous != null &&
                (row['id'] as String).compareTo(previous) <= 0)) {
          throw const FormatException('Invalid record order.');
        }
        previous = row['id'] as String;
      }
      if (result['next_cursor'] != null &&
          (records.isEmpty || result['next_cursor'] != previous)) {
        throw const FormatException('Invalid page cursor.');
      }
    }
    return Map<String, dynamic>.from(result);
  }
}
