import 'tabby_local_cache.dart';

/// Freezes the exact wire payload before sending it. A retry reuses that payload.
class DurableMoneyExecutor {
  DurableMoneyExecutor({required this.invoke});
  final Future<String> Function(String rpc, Map<String, dynamic> params) invoke;

  Future<String> execute(
      {required String userId,
      required String operationId,
      required String rpc,
      required Map<String, dynamic> command}) async {
    final prepared = await TabbyLocalCache.prepareMoneyCommand(operationId,
        userId: userId, rpc: rpc, command: command);
    return invoke(prepared['rpc_name'] as String, {
      'p_operation_id': operationId,
      'p_command': prepared['rpc_command'],
    });
  }
}
