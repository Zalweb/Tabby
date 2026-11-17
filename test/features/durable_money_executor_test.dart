import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/tabs/data/durable_money_executor.dart';
import 'package:tabby/features/tabs/data/tabby_local_cache.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
      'response loss and concurrent retries reuse durable identity and payload',
      () async {
    await TabbyLocalCache.enqueuePendingOp({'operation_id': 'op'}, userId: 'A');
    final calls = <Map<String, dynamic>>[];
    var first = true;
    final executor = DurableMoneyExecutor(invoke: (rpc, params) async {
      calls.add(params);
      if (first) {
        first = false;
        throw StateError('Response lost after commit');
      }
      return 'same-server-id';
    });
    Future<String> run(int amount) => executor.execute(
        userId: 'A',
        operationId: 'op',
        rpc: 'create_expense_v1',
        command: {'amount': amount});
    await expectLater(run(100), throwsStateError);
    expect(await Future.wait([run(200), run(300)]),
        ['same-server-id', 'same-server-id']);
    expect(calls.map((p) => p['p_operation_id']), everyElement('op'));
    expect(calls.map((p) => p['p_command']), everyElement({'amount': 100}));
    expect((await TabbyLocalCache.loadPendingOps(userId: 'A')), hasLength(1));
  });
  test(
      'commands cannot execute without a durable intent in the initiating account',
      () async {
    await TabbyLocalCache.enqueuePendingOp({'operation_id': 'op'}, userId: 'A');
    var called = false;
    final executor = DurableMoneyExecutor(invoke: (_, __) async {
      called = true;
      return 'id';
    });
    await expectLater(
        executor.execute(
            userId: 'B',
            operationId: 'op',
            rpc: 'submit_payment_v1',
            command: {}),
        throwsStateError);
    expect(called, isFalse);
  });
  test(
      're-enqueue cannot overwrite financial intent under the same operation ID',
      () async {
    await TabbyLocalCache.enqueuePendingOp(
        {'operation_id': 'op', 'amount': 100},
        userId: 'A');
    await expectLater(
        TabbyLocalCache.enqueuePendingOp({'operation_id': 'op', 'amount': 200},
            userId: 'A'),
        throwsStateError);
    expect((await TabbyLocalCache.loadPendingOps(userId: 'A')).single['amount'],
        100);
  });
}
