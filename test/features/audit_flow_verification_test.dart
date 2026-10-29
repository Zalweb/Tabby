import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/services/receipt_attachment_service.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/data/mock_tabby_repository.dart';
import 'package:tabby/features/tabs/data/tabby_local_cache.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:uuid/uuid.dart';

/// Post-audit flow verification: proves that adding tabs/debts is accurate
/// (no silent merges, no phantom duplicates), the activity feed never shows
/// duplicates, and settlement math drives balances to exactly zero.
void main() {
  // Connectivity watching inside TabbyNotifier uses platform EventChannels,
  // which require an initialized binding even in non-widget tests.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('Reliable financial synchronization', () {
    test('pending operations remain durable until individually acknowledged',
        () async {
      await TabbyLocalCache.enqueuePendingOp(
        {'operation_id': 'first', 'type': 'add_expense'},
        userId: 'alice',
      );
      final firstRead = await TabbyLocalCache.loadPendingOps(userId: 'alice');
      expect(await TabbyLocalCache.loadPendingOps(userId: 'alice'), firstRead);
      await TabbyLocalCache.enqueuePendingOp(
        {'operation_id': 'second', 'type': 'settle_payment'},
        userId: 'alice',
      );
      await TabbyLocalCache.acknowledgePendingOp('first', userId: 'alice');
      expect(
        (await TabbyLocalCache.loadPendingOps(userId: 'alice'))
            .map((op) => op['operation_id']),
        ['second'],
      );
    });

    test('concurrent queue writes and retries preserve every operation once',
        () async {
      await Future.wait([
        for (var i = 0; i < 20; i++)
          TabbyLocalCache.enqueuePendingOp(
            {'operation_id': '$i', 'type': 'add_expense'},
            userId: 'alice',
          ),
      ]);
      await Future.wait([
        TabbyLocalCache.acknowledgePendingOp('0', userId: 'alice'),
        TabbyLocalCache.enqueuePendingOp(
          {'operation_id': '20', 'type': 'add_expense'},
          userId: 'alice',
        ),
        TabbyLocalCache.enqueuePendingOp(
          {'operation_id': '1', 'type': 'add_expense'},
          userId: 'alice',
        ),
      ]);
      final ops = await TabbyLocalCache.loadPendingOps(userId: 'alice');
      expect(ops, hasLength(20));
      expect(ops.map((op) => op['operation_id']).toSet(), hasLength(20));
      expect(ops.any((op) => op['operation_id'] == '0'), isFalse);
      expect(ops.any((op) => op['operation_id'] == '20'), isTrue);
    });

    test(
        'logging out preserves queued writes without exposing them to another user',
        () async {
      await TabbyLocalCache.enqueuePendingOp(
        {'operation_id': 'expense', 'type': 'add_expense'},
        userId: 'alice',
      );
      await TabbyLocalCache.clearCache(userId: 'alice');
      expect(await TabbyLocalCache.hasPendingOps(userId: 'alice'), isTrue);
      expect(await TabbyLocalCache.hasPendingOps(userId: 'bob'), isFalse);
    });

    test('existing queued records receive a stable replay identity', () async {
      FlutterSecureStorage.setMockInitialValues({
        'tabby_pending_ops_alice': '[{"type":"add_expense"}]',
      });
      final first = await TabbyLocalCache.loadPendingOps(userId: 'alice');
      final second = await TabbyLocalCache.loadPendingOps(userId: 'alice');
      expect(first.single['operation_id'], isNotEmpty);
      expect(second.single['operation_id'], first.single['operation_id']);
    });

    test('exact replay identities do not merge unrelated equal-value debts',
        () {
      final now = DateTime.now();
      final firstId = const Uuid().v4();
      final secondId = const Uuid().v4();
      final local = LedgerEntry(
        id: 'entry-$firstId',
        tabId: 'tab',
        title: 'Dinner',
        category: ExpenseCategory.food,
        totalAmountCentavos: 10001,
        myShareCentavos: 5000,
        counterpartShareCentavos: 5001,
        paidByUserId: 'user-me',
        paidByName: 'You',
        date: now,
      );
      final entries = MockTabbyRepository.deduplicateLedgerEntries([
        local.copyWith(id: secondId),
        local,
        local.copyWith(id: firstId),
      ]);
      expect(entries.map((entry) => entry.id).toSet(), {firstId, secondId});
      expect(
          MockTabbyRepository.calculateNetBalance(entries, 'user-me'), 10002);
    });

    test('a submitted payment keeps the obligation and reminder unchanged',
        () async {
      final notifier = TabbyNotifier(loadInitialData: false);
      addTearDown(notifier.dispose);
      await notifier.addExpense(
        counterpartId: 'friend-juan',
        counterpartName: 'Juan',
        title: 'Dinner',
        totalAmountCentavos: 10001,
        category: ExpenseCategory.food,
        paidByMe: false,
        isEqualSplit: true,
        dueDate: DateTime.now().add(const Duration(days: 1)),
      );
      final tab = notifier.state.tabs.single;
      expect(tab.entries.single.myShareCentavos, 5000);
      expect(tab.entries.single.counterpartShareCentavos, 5001);
      await notifier.settleTab(
        tabId: tab.id,
        amountCentavos: 5000,
        method: PaymentMethod.gcash,
        isPayingMe: false,
      );
      expect(notifier.state.tabs.single.netBalanceCentavos, -5000);
      expect(notifier.state.tabs.single.entries.first.status,
          TransactionStatus.paymentSubmitted);
      expect(notifier.state.reminders, hasLength(1));
    });

    test('cloud receipt paths are preserved without opening a device file',
        () async {
      const storagePath = 'alice/expense.png';
      expect(
        await ReceiptAttachmentService.uploadPendingReceipt(
          storagePath,
          entryKey: 'expense',
          userId: 'alice',
        ),
        storagePath,
      );
      expect(
        await ReceiptAttachmentService.readPendingReceiptBytes(
          storagePath,
          userId: 'alice',
        ),
        isNull,
      );
      await expectLater(
        ReceiptAttachmentService.uploadPendingReceipt(
          '/temporary/receipt.png',
          entryKey: 'expense',
          userId: 'alice',
        ),
        throwsStateError,
      );
    });
  });

  group('Audit flow verification - tabs, debts, activity integrity', () {
    test('adding one expense creates exactly one tab, one entry, one activity',
        () async {
      final notifier = TabbyNotifier(loadInitialData: false);
      addTearDown(notifier.dispose);

      await notifier.addExpense(
        counterpartId: 'friend-juan',
        counterpartName: 'Juan',
        title: 'Dinner',
        totalAmountCentavos: 50000,
        category: ExpenseCategory.food,
        paidByMe: true,
        isEqualSplit: false, // Full obligation owed by Juan
      );

      expect(notifier.state.tabs, hasLength(1));
      final tab = notifier.state.tabs.single;
      expect(tab.entries, hasLength(1));
      expect(tab.netBalanceCentavos, 50000); // +PHP 500.00 (Juan owes you)
      expect(notifier.state.activities, hasLength(1));
      expect(notifier.state.activities.single.amountCentavos, 50000);
    });

    test('two identical expenses logged back-to-back are BOTH kept', () async {
      final notifier = TabbyNotifier(loadInitialData: false);
      addTearDown(notifier.dispose);

      for (var i = 0; i < 2; i++) {
        await notifier.addExpense(
          counterpartId: 'friend-juan',
          counterpartName: 'Juan',
          title: 'Dinner',
          totalAmountCentavos: 50000,
          category: ExpenseCategory.food,
          paidByMe: true,
          isEqualSplit: false,
        );
        // Distinct millisecond IDs (mirrors real user pacing).
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      // One Tab = One Financial Relationship (no duplicate tabs).
      expect(notifier.state.tabs, hasLength(1));
      final tab = notifier.state.tabs.single;
      // Both legitimate debts survive - dedup must not eat real entries.
      expect(tab.entries, hasLength(2));
      expect(tab.netBalanceCentavos, 100000); // accurate doubled balance
      // Two distinct activities, neither duplicated nor dropped.
      expect(notifier.state.activities, hasLength(2));
    });

    test('expenses with different counterparts create separate bilateral tabs',
        () async {
      final notifier = TabbyNotifier(loadInitialData: false);
      addTearDown(notifier.dispose);

      await notifier.addExpense(
        counterpartId: 'friend-juan',
        counterpartName: 'Juan',
        title: 'Dinner',
        totalAmountCentavos: 50000,
        category: ExpenseCategory.food,
        paidByMe: true,
        isEqualSplit: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await notifier.addExpense(
        counterpartId: 'friend-ana',
        counterpartName: 'Ana',
        title: 'Fare',
        totalAmountCentavos: 75000,
        category: ExpenseCategory.transportation,
        paidByMe: true,
        isEqualSplit: false,
      );

      expect(notifier.state.tabs, hasLength(2));
      final juanTab = notifier.state.tabs
          .firstWhere((t) => t.counterpart.displayName == 'Juan');
      final anaTab = notifier.state.tabs
          .firstWhere((t) => t.counterpart.displayName == 'Ana');
      expect(juanTab.entries, hasLength(1));
      expect(juanTab.netBalanceCentavos, 50000);
      expect(anaTab.entries, hasLength(1));
      expect(anaTab.netBalanceCentavos, 75000);
      expect(notifier.state.activities, hasLength(2));
    });

    test('counterpart-paid expense produces a negative you-owe balance',
        () async {
      final notifier = TabbyNotifier(loadInitialData: false);
      addTearDown(notifier.dispose);

      await notifier.addExpense(
        counterpartId: 'friend-juan',
        counterpartName: 'Juan',
        title: 'Coffee',
        totalAmountCentavos: 30000,
        category: ExpenseCategory.food,
        paidByMe: false,
        isEqualSplit: false,
      );

      final tab = notifier.state.tabs.single;
      expect(tab.entries, hasLength(1));
      expect(tab.netBalanceCentavos, -30000); // You owe Juan PHP 300.00
    });

    test('opposite-direction expenses offset within a single tab', () async {
      final notifier = TabbyNotifier(loadInitialData: false);
      addTearDown(notifier.dispose);

      await notifier.addExpense(
        counterpartId: 'friend-juan',
        counterpartName: 'Juan',
        title: 'Dinner',
        totalAmountCentavos: 50000,
        category: ExpenseCategory.food,
        paidByMe: true,
        isEqualSplit: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await notifier.addExpense(
        counterpartId: 'friend-juan',
        counterpartName: 'Juan',
        title: 'Fare',
        totalAmountCentavos: 10000,
        category: ExpenseCategory.transportation,
        paidByMe: false,
        isEqualSplit: false,
      );

      final tab = notifier.state.tabs.single;
      expect(tab.entries, hasLength(2));
      expect(tab.netBalanceCentavos, 40000); // 500.00 - 100.00 net
    });

    test('KKB equal split keeps integer-centavo precision (no centavo loss)',
        () async {
      final notifier = TabbyNotifier(loadInitialData: false);
      addTearDown(notifier.dispose);

      await notifier.addExpense(
        counterpartId: 'friend-juan',
        counterpartName: 'Juan',
        title: 'Group dinner',
        totalAmountCentavos: 50000,
        category: ExpenseCategory.food,
        paidByMe: true,
        isEqualSplit: true,
        participantCount: 2,
      );

      final tab = notifier.state.tabs.single;
      final entry = tab.entries.single;
      // PHP 500.00 / 2 = PHP 250.00 each, exact.
      expect(entry.myShareCentavos, 25000);
      expect(entry.counterpartShareCentavos, 25000);
      expect(entry.myShareCentavos + entry.counterpartShareCentavos, 50000);
      expect(tab.netBalanceCentavos, 25000); // Juan owes you his half
    });

    test('settlement math drives the balance to exactly zero', () async {
      final notifier = TabbyNotifier(loadInitialData: false);
      addTearDown(notifier.dispose);

      await notifier.addExpense(
        counterpartId: 'friend-juan',
        counterpartName: 'Juan',
        title: 'Borrowed cash',
        totalAmountCentavos: 50000,
        category: ExpenseCategory.borrowedCash,
        paidByMe: true,
        isEqualSplit: false,
      );
      final tabId = notifier.state.tabs.single.id;

      // Partial payment of PHP 200.00 -> PHP 300.00 remaining.
      await notifier.settleTab(
        tabId: tabId,
        amountCentavos: 20000,
        method: PaymentMethod.gcash,
        isPayingMe: true,
      );
      var tab = notifier.state.tabs.single;
      expect(tab.netBalanceCentavos, 30000);
      expect(tab.entries, hasLength(2)); // obligation + payment recorded
      expect(notifier.state.activities, hasLength(2)); // no dup, no loss

      // Full settlement of the remaining PHP 300.00 -> exactly zero.
      await notifier.settleTab(
        tabId: tabId,
        amountCentavos: 30000,
        method: PaymentMethod.cash,
        isPayingMe: true,
      );
      tab = notifier.state.tabs.single;
      expect(tab.netBalanceCentavos, 0);
      expect(tab.entries, hasLength(3));
      expect(notifier.state.activities, hasLength(3));
    });

    test('receipt attachment persists a real storage path on the entry',
        () async {
      final notifier = TabbyNotifier(loadInitialData: false);
      addTearDown(notifier.dispose);

      await notifier.addExpense(
        counterpartId: 'friend-juan',
        counterpartName: 'Juan',
        title: 'Dinner',
        totalAmountCentavos: 50000,
        category: ExpenseCategory.food,
        paidByMe: true,
        isEqualSplit: false,
      );
      final tab = notifier.state.tabs.single;
      final entryId = tab.entries.single.id;

      notifier.attachReceiptToEntry(
        tabId: tab.id,
        entryId: entryId,
        receiptUrl: 'user-me/$entryId.jpg',
      );

      final updated = notifier.state.tabs.single.entries.single;
      expect(updated.receiptUrl, 'user-me/$entryId.jpg');
      // No duplicate entries or activities created by the attachment.
      expect(notifier.state.tabs.single.entries, hasLength(1));
      expect(notifier.state.activities, hasLength(1));
    });

    test('activity feed stays stable under repeated dedup passes', () async {
      final notifier = TabbyNotifier(loadInitialData: false);
      addTearDown(notifier.dispose);

      await notifier.addExpense(
        counterpartId: 'friend-juan',
        counterpartName: 'Juan',
        title: 'Dinner',
        totalAmountCentavos: 50000,
        category: ExpenseCategory.food,
        paidByMe: true,
        isEqualSplit: false,
      );
      await notifier.settleTab(
        tabId: notifier.state.tabs.single.id,
        amountCentavos: 20000,
        method: PaymentMethod.gcash,
        isPayingMe: true,
      );

      final before = notifier.state.activities;
      final pass1 = TabbyNotifier.deduplicateActivities(before);
      final pass2 = TabbyNotifier.deduplicateActivities(pass1);
      expect(pass1, hasLength(before.length));
      expect(pass2, hasLength(before.length));
      // Ledger dedup is equally stable.
      final entries = notifier.state.tabs.single.entries;
      final clean = TabbyNotifier.deduplicateLedgerEntries(entries);
      expect(clean, hasLength(entries.length));
    });
  });
}
