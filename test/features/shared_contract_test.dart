import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/tabs/data/tabby_local_cache.dart';
import 'package:tabby/features/tabs/data/mock_tabby_repository.dart';
import 'package:tabby/features/tabs/domain/models.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('durable operation identity survives reload and duplicate enqueue',
      () async {
    const command = {'operation_id': 'stable-id', 'type': 'add_expense'};
    await TabbyLocalCache.enqueuePendingOp(command, userId: 'A');
    await TabbyLocalCache.enqueuePendingOp(command, userId: 'A');
    final first = await TabbyLocalCache.loadPendingOps(userId: 'A');
    final reloaded = await TabbyLocalCache.loadPendingOps(userId: 'A');
    expect(first, hasLength(1));
    expect(reloaded.single['operation_id'], 'stable-id');
    expect(await TabbyLocalCache.loadPendingOps(userId: 'B'), isEmpty);
  });

  test('proof submission never reduces balance before recipient confirmation',
      () {
    final submitted = LedgerEntry(
      id: 'submission-id',
      tabId: 'tab',
      title: 'External payment',
      category: ExpenseCategory.other,
      totalAmountCentavos: 1000,
      myShareCentavos: 0,
      counterpartShareCentavos: 0,
      paidByUserId: 'A',
      paidByName: 'A',
      date: DateTime(2026),
      isPayment: true,
      status: TransactionStatus.pending,
    );
    expect(MockTabbyRepository.calculateNetBalance([submitted], 'A'), 0);
    expect(
        MockTabbyRepository.calculateNetBalance(
            [submitted.copyWith(status: TransactionStatus.settled)], 'A'),
        1000);
  });
}
