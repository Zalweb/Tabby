import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/tabs/data/tabby_local_cache.dart';

void main() {
  test(
      'explicit retry preserves wire identity and leaves unmapped legacy writes held',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    await TabbyLocalCache.enqueuePendingOp(
        {'operation_id': 'safe', 'local_entry_id': 'entry'},
        userId: 'A');
    await TabbyLocalCache.prepareMoneyCommand('safe',
        userId: 'A', rpc: 'create_expense_v1', command: {'amount': 100});
    await TabbyLocalCache.enqueuePendingOp({'operation_id': 'legacy'},
        userId: 'A');
    for (final id in ['safe', 'legacy']) {
      await TabbyLocalCache.recordPendingFailure(id,
          userId: 'A', now: DateTime.utc(2026), permanent: true);
    }
    await TabbyLocalCache.retryPendingWrites(userId: 'A');
    final ops = await TabbyLocalCache.loadPendingOps(userId: 'A');
    final safe = ops.firstWhere((op) => op['operation_id'] == 'safe');
    expect(safe['sync_state'], 'queued');
    expect(safe['attempt_count'], 0);
    expect(safe['rpc_command'], {'amount': 100});
    expect(ops.firstWhere((op) => op['operation_id'] == 'legacy')['sync_state'],
        'needsAttention');
  });
  test('unreadable durable queue cannot be overwritten or counted as empty',
      () async {
    FlutterSecureStorage.setMockInitialValues(
        {'tabby_pending_ops_A': 'invalid-json'});
    await expectLater(
        TabbyLocalCache.enqueuePendingOp({'operation_id': 'new'}, userId: 'A'),
        throwsFormatException);
    await expectLater(TabbyLocalCache.loadPendingOps(userId: 'A', strict: true),
        throwsFormatException);
    expect(await const FlutterSecureStorage().read(key: 'tabby_pending_ops_A'),
        'invalid-json');
  });
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('transient failures wait, survive reload and stop after five attempts',
      () async {
    final now = DateTime.utc(2026, 10, 31);
    await TabbyLocalCache.enqueuePendingOp({'operation_id': 'op'}, userId: 'A');
    for (var attempt = 1; attempt <= 5; attempt++) {
      await TabbyLocalCache.recordPendingFailure('op', userId: 'A', now: now);
      final op = (await TabbyLocalCache.loadPendingOps(userId: 'A')).single;
      expect(op['attempt_count'], attempt);
      expect(TabbyLocalCache.canAttemptPendingOp(op, now), isFalse);
      if (attempt < 5) {
        final delay = Duration(seconds: 5 * (1 << (attempt - 1)));
        expect(TabbyLocalCache.canAttemptPendingOp(op, now.add(delay)), isTrue);
      } else {
        expect(op['sync_state'], 'needsAttention');
        expect(
            TabbyLocalCache.canAttemptPendingOp(
                op, now.add(const Duration(days: 1))),
            isFalse);
      }
    }
  });
  test('permanent failure never retries on idle reload or account change',
      () async {
    final now = DateTime.utc(2026);
    await TabbyLocalCache.enqueuePendingOp({'operation_id': 'bad'},
        userId: 'A');
    await TabbyLocalCache.recordPendingFailure('bad',
        userId: 'A', now: now, permanent: true);
    for (var reload = 0; reload < 3; reload++) {
      final op = (await TabbyLocalCache.loadPendingOps(userId: 'A')).single;
      expect(op['attempt_count'], 1);
      expect(
          TabbyLocalCache.canAttemptPendingOp(
              op, now.add(const Duration(days: 10))),
          isFalse);
    }
    expect(await TabbyLocalCache.loadPendingOps(userId: 'B'), isEmpty);
  });
}
