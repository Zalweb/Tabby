import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/tabs/data/tabby_local_cache.dart';
import 'package:tabby/features/tabs/domain/activity_reconciliation.dart';
import 'package:tabby/features/tabs/domain/models.dart';

TabbyActivity row(String id, {String description = 'Dinner'}) => TabbyActivity(
    id: id,
    actorName: 'Same display name',
    description: description,
    amountCentavos: 5000,
    timestamp: DateTime(2026, 11, 1));
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
      'server and separate optimistic same-price rows never merge by similarity',
      () {
    final result = reconcileActivityIds(
        [row('server'), row('entry-new'), row('payment-new'), row('server')]);
    expect(result.map((r) => r.id), ['server', 'entry-new', 'payment-new']);
  });
  test('explicit result mapping equates only its source ID; server row wins',
      () {
    final result = reconcileActivityIds([
      row('server', description: 'Authoritative'),
      row('entry-known'),
      row('entry-separate')
    ], mappings: {
      'entry-known': 'server'
    });
    expect(result.length, 2);
    expect(result.first.description, 'Authoritative');
    expect(result.last.id, 'entry-separate');
  });
  test('mapping checkpoint repairs older cached activity after response loss',
      () async {
    await TabbyLocalCache.saveActivities(
        [row('entry-known'), row('entry-separate')],
        userId: 'owner', strict: true);
    await TabbyLocalCache.saveEntryMapping('entry-known', 'server', 'tab',
        userId: 'owner');
    final restored = (await TabbyLocalCache.loadActivities(userId: 'owner'))!;
    expect(restored.map((r) => r.id), ['server', 'entry-separate']);
    final merged = reconcileActivityIds(
        [row('server', description: 'Server'), ...restored]);
    expect(merged.length, 2);
    expect(merged.first.description, 'Server');
    await TabbyLocalCache.saveActivities(merged, userId: 'owner', strict: true);
    expect((await TabbyLocalCache.loadActivities(userId: 'owner'))!.length, 2);
  });
  test(
      'opaque UUID-shaped local IDs use explicit mappings and account isolation',
      () async {
    const local = '00000000-0000-4000-8000-000000000123';
    await TabbyLocalCache.saveEntryMapping(local, 'server-A', 'tab-A',
        userId: 'A');
    for (final owner in ['A', 'B']) {
      await TabbyLocalCache.saveActivities([row(local)],
          userId: owner, strict: true);
    }
    expect((await TabbyLocalCache.loadActivities(userId: 'A'))!.single.id,
        'server-A');
    expect(
        (await TabbyLocalCache.loadActivities(userId: 'B'))!.single.id, local);
  });
  test('concurrent mapping checkpoints preserve every distinct operation',
      () async {
    await Future.wait([
      for (var i = 0; i < 8; i++)
        TabbyLocalCache.saveEntryMapping('entry-$i', 'server-$i', 'tab',
            userId: 'owner')
    ]);
    final resolved = await TabbyLocalCache.resolveActivityMappings(
        [for (var i = 0; i < 8; i++) row('entry-$i')],
        userId: 'owner');
    expect(resolved.map((r) => r.id).toSet(),
        {for (var i = 0; i < 8; i++) 'server-$i'});
    await expectLater(
        TabbyLocalCache.saveEntryMapping('entry-1', 'different', 'tab',
            userId: 'owner'),
        throwsStateError);
  });
  test('unmapped legacy activity and empty IDs are retained for review',
      () async {
    final rows = [row('act-legacy'), row('server'), row(''), row('')];
    expect(
        (await TabbyLocalCache.resolveActivityMappings(rows, userId: 'owner'))
            .length,
        4);
  });
  test('payment activity status never calls a pending submission settled', () {
    final pending = LedgerEntry(
        id: 'payment',
        tabId: 'tab',
        title: 'Wallet payment',
        category: ExpenseCategory.other,
        totalAmountCentavos: 5000,
        myShareCentavos: 0,
        counterpartShareCentavos: 0,
        paidByUserId: 'owner',
        paidByName: 'You',
        date: DateTime(2026),
        isPayment: true,
        status: TransactionStatus.paymentSubmitted);
    expect(activityForEntry(pending, 'owner', 'Friend').description,
        'Payment submitted: Wallet payment');
    expect(
        activityForEntry(pending.copyWith(status: TransactionStatus.settled),
                'owner', 'Friend')
            .description,
        'Payment confirmed: Wallet payment');
    expect(
        activityForEntry(pending.copyWith(status: TransactionStatus.cancelled),
                'owner', 'Friend')
            .description,
        'Payment rejected: Wallet payment');
    expect(activityForEntry(pending, 'owner', 'Friend').id, pending.id);
  });
}
