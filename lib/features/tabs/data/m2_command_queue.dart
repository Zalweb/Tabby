import '../../../core/config/supabase_config.dart';
import 'ledger_cache_storage.dart';
import 'tabby_local_cache.dart';

import 'dart:convert';

/// M2 joins the existing serialized replay owner; forms never call write RPCs.
class M2CommandQueue {
  M2CommandQueue({
    required this.actor,
    required this.current,
    required this.wake,
  });
  final String actor;
  final bool Function() current;
  final Future<void> Function() wake;
  static const rpcs = {
    'create_expense_v3',
    'change_recurrence_v1',
    'materialize_recurrence_v1',
    'invite_contact_claim_v1',
    'decide_contact_claim_v1',
    'review_expense_v1',
  };
  Future<void> enqueue(
    String operationId,
    String rpc,
    Map<String, dynamic> command,
  ) async {
    if (actor.isEmpty ||
        !current() ||
        !rpcs.contains(rpc) ||
        command['p_expected_actor'] != actor) {
      throw StateError('Account or command changed.');
    }
    // The immutable intent is separate from runtime wire fields, whose freezing
    // is owned by DurableMoneyExecutor. Same-ID edits must conflict locally too.
    await TabbyLocalCache.enqueuePendingOp({
      'type': 'm2_command',
      'operation_id': operationId,
      'm2_rpc': rpc,
      'm2_command': command,
    }, userId: actor);
    if (!current()) throw StateError('Account changed.');
    await TabbyLocalCache.retryPendingOperation(operationId, userId: actor);
    if (!current()) throw StateError('Account changed.');
    await wake();
  }

  static Future<void> saveResult(
    String actor,
    String operation,
    String result,
  ) async {
    const storage = LedgerCacheStorage();
    // Each operation is its own immutable record; unrelated results cannot race
    // through a shared JSON map read/modify/write.
    await storage.write(
      key: 'tabby_m2_result_${actor}_$operation',
      value: jsonEncode(result),
    );
  }

  Future<String?> result(String operation) async {
    final value = await const LedgerCacheStorage().read(
      key: 'tabby_m2_result_${actor}_$operation',
    );
    if (!current()) throw StateError('Account changed.');
    return value == null ? null : jsonDecode(value) as String;
  }

  Future<bool> needsAttention(String operation) async {
    final ops = await TabbyLocalCache.loadPendingOps(
      userId: actor,
      strict: true,
    );
    if (!current()) throw StateError('Account changed.');
    return ops.any(
      (p) =>
          p['operation_id'] == operation && p['sync_state'] == 'needsAttention',
    );
  }

  static M2CommandQueue forSession(Future<void> Function() wake) {
    final session = SupabaseConfig.captureSession();
    return M2CommandQueue(
      actor: session.accountId ?? '',
      current: () => SupabaseConfig.isCurrentSession(session),
      wake: wake,
    );
  }
}
