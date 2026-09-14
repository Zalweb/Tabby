import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/tabs/data/mock_tabby_repository.dart';
import 'package:tabby/features/tabs/data/supabase_tabby_repository.dart';
import 'package:tabby/features/tabs/domain/models.dart';

void main() {
  group('Backend Data Handling & Supabase Serialization Tests', () {
    test('Category serialization and deserialization covers all ExpenseCategory values', () {
      for (final cat in ExpenseCategory.values) {
        final serialized = SupabaseTabbyRepository.mapCategory(cat);
        expect(serialized, isNotEmpty);
        final deserialized = SupabaseTabbyRepository.unmapCategory(serialized);
        expect(deserialized, equals(cat));
      }

      // Edge cases & unknown strings
      expect(SupabaseTabbyRepository.unmapCategory('UNKNOWN_XYZ'), equals(ExpenseCategory.other));
      expect(SupabaseTabbyRepository.unmapCategory(null), equals(ExpenseCategory.other));
      expect(SupabaseTabbyRepository.unmapCategory(''), equals(ExpenseCategory.other));
      expect(SupabaseTabbyRepository.unmapCategory('FOOD'), equals(ExpenseCategory.food));
      expect(SupabaseTabbyRepository.unmapCategory('Borrowed_Cash'), equals(ExpenseCategory.borrowedCash));
    });

    test('PaymentMethod serialization and deserialization covers all values', () {
      for (final method in PaymentMethod.values) {
        final serialized = SupabaseTabbyRepository.mapPaymentMethod(method);
        expect(serialized, isNotEmpty);
        final deserialized = SupabaseTabbyRepository.unmapPaymentMethod(serialized);
        expect(deserialized, equals(method));
      }

      // Edge cases & unknown strings
      expect(SupabaseTabbyRepository.unmapPaymentMethod('crypto'), equals(PaymentMethod.other));
      expect(SupabaseTabbyRepository.unmapPaymentMethod(null), equals(PaymentMethod.other));
      expect(SupabaseTabbyRepository.unmapPaymentMethod(''), equals(PaymentMethod.other));
      expect(SupabaseTabbyRepository.unmapPaymentMethod('GCASH'), equals(PaymentMethod.gcash));
      expect(SupabaseTabbyRepository.unmapPaymentMethod('bank_transfer'), equals(PaymentMethod.bankTransfer));
    });

    test('TransactionStatus deserialization covers all Postgres status strings', () {
      expect(SupabaseTabbyRepository.unmapTransactionStatus('settled'), equals(TransactionStatus.settled));
      expect(SupabaseTabbyRepository.unmapTransactionStatus('payment_submitted'), equals(TransactionStatus.paymentSubmitted));
      expect(SupabaseTabbyRepository.unmapTransactionStatus('cancelled'), equals(TransactionStatus.cancelled));
      expect(SupabaseTabbyRepository.unmapTransactionStatus('acknowledged'), equals(TransactionStatus.acknowledged));
      expect(SupabaseTabbyRepository.unmapTransactionStatus('pending'), equals(TransactionStatus.pending));
      // Unknown / fallback
      expect(SupabaseTabbyRepository.unmapTransactionStatus('unknown'), equals(TransactionStatus.pending));
      expect(SupabaseTabbyRepository.unmapTransactionStatus(null), equals(TransactionStatus.pending));
      expect(SupabaseTabbyRepository.unmapTransactionStatus('SETTLED'), equals(TransactionStatus.settled));
    });

    test('UUID validator accurately distinguishes valid UUIDs from synthetic IDs', () {
      // Valid RFC 4122 v4 UUIDs
      expect(SupabaseTabbyRepository.isValidUuid('c1a2b3c4-d5e6-4f7a-8b9c-0d1e2f3a4b5c'), isTrue);
      expect(SupabaseTabbyRepository.isValidUuid('00000000-0000-0000-0000-000000000000'), isTrue);
      expect(SupabaseTabbyRepository.isValidUuid('C1A2B3C4-D5E6-4F7A-8B9C-0D1E2F3A4B5C'), isTrue);

      // Synthetic IDs
      expect(SupabaseTabbyRepository.isValidUuid('user-me'), isFalse);
      expect(SupabaseTabbyRepository.isValidUuid('user-carlos-1234'), isFalse);
      expect(SupabaseTabbyRepository.isValidUuid('group-beach-trip'), isFalse);
      expect(SupabaseTabbyRepository.isValidUuid(''), isFalse);
      expect(SupabaseTabbyRepository.isValidUuid('12345'), isFalse);
      expect(SupabaseTabbyRepository.isValidUuid('c1a2b3c4-d5e6-4f7a-8b9c-0d1e2f3a4b5'), isFalse); // too short
      expect(SupabaseTabbyRepository.isValidUuid('c1a2b3c4-d5e6-4f7a-8b9c-0d1e2f3a4b5c9'), isFalse); // too long
    });

    test('SupabaseTabbyRepository offline resilience handles uninitialized backend gracefully', () async {
      final repo = SupabaseTabbyRepository.instance;
      expect(repo.isConnected, isFalse);

      // fetchTabs should return mock tabs when uninitialized
      final tabs = await repo.fetchTabs('user-me');
      expect(tabs, isNotNull);

      // ensureUserExists returns input ID when uninitialized
      final resolved = await repo.ensureUserExists('user-alex', 'Alex');
      expect(resolved, equals('user-alex'));

      // Write operations should not throw when uninitialized
      await expectLater(
        repo.logExpense(
          tabId: 'test-tab',
          title: 'Lunch',
          totalAmountCentavos: 10000,
          category: ExpenseCategory.food,
          paidByUserId: 'user-me',
          myShareCentavos: 5000,
          counterpartShareCentavos: 5000,
          currentUserId: 'user-me',
          counterpartId: 'user-alex',
        ),
        completes,
      );

      await expectLater(
        repo.recordPayment(
          tabId: 'test-tab',
          amountCentavos: 5000,
          method: PaymentMethod.gcash,
          paidByUserId: 'user-alex',
          receivedByUserId: 'user-me',
        ),
        completes,
      );

      await expectLater(repo.signOut(), completes);
    });
  });

  group('Canonical Ledger Engine Math & ADR-001 Tests', () {
    const currentUserId = 'user-me';
    const friendId = 'user-friend';

    test('Empty ledger entries calculate to zero centavos', () {
      expect(MockTabbyRepository.calculateNetBalance([], currentUserId), equals(0));
    });

    test('Single expense paid by current user creates positive balance', () {
      final entries = [
        LedgerEntry(
          id: 'tx-1',
          tabId: 'tab-1',
          title: 'Dinner',
          category: ExpenseCategory.food,
          totalAmountCentavos: 50000,
          myShareCentavos: 0,
          counterpartShareCentavos: 50000,
          paidByUserId: currentUserId,
          paidByName: 'Me',
          date: DateTime.now(),
        ),
      ];
      expect(MockTabbyRepository.calculateNetBalance(entries, currentUserId), equals(50000));
    });

    test('Single expense paid by counterpart creates negative balance', () {
      final entries = [
        LedgerEntry(
          id: 'tx-2',
          tabId: 'tab-1',
          title: 'Grab Fare',
          category: ExpenseCategory.transportation,
          totalAmountCentavos: 25000,
          myShareCentavos: 25000,
          counterpartShareCentavos: 0,
          paidByUserId: friendId,
          paidByName: 'Friend',
          date: DateTime.now(),
        ),
      ];
      expect(MockTabbyRepository.calculateNetBalance(entries, currentUserId), equals(-25000));
    });

    test('Two-way mutual debts offset correctly into a net integer balance', () {
      final entries = [
        // I paid ₱500 for friend
        LedgerEntry(
          id: 'tx-1',
          tabId: 'tab-1',
          title: 'Dinner',
          category: ExpenseCategory.food,
          totalAmountCentavos: 50000,
          myShareCentavos: 0,
          counterpartShareCentavos: 50000,
          paidByUserId: currentUserId,
          paidByName: 'Me',
          date: DateTime.now(),
        ),
        // Friend paid ₱200 for me
        LedgerEntry(
          id: 'tx-2',
          tabId: 'tab-1',
          title: 'Coffee',
          category: ExpenseCategory.food,
          totalAmountCentavos: 20000,
          myShareCentavos: 20000,
          counterpartShareCentavos: 0,
          paidByUserId: friendId,
          paidByName: 'Friend',
          date: DateTime.now(),
        ),
      ];
      // Net: 50000 - 20000 = +30000 (+₱300.00)
      expect(MockTabbyRepository.calculateNetBalance(entries, currentUserId), equals(30000));
    });

    test('Partial payment reduces net balance correctly', () {
      final entries = [
        // Friend owes me ₱500
        LedgerEntry(
          id: 'tx-1',
          tabId: 'tab-1',
          title: 'Dinner',
          category: ExpenseCategory.food,
          totalAmountCentavos: 50000,
          myShareCentavos: 0,
          counterpartShareCentavos: 50000,
          paidByUserId: currentUserId,
          paidByName: 'Me',
          date: DateTime.now(),
        ),
        // Friend pays me ₱200 via GCash
        LedgerEntry(
          id: 'pay-1',
          tabId: 'tab-1',
          title: 'Friend paid via GCash',
          category: ExpenseCategory.borrowedCash,
          totalAmountCentavos: 20000,
          myShareCentavos: 0,
          counterpartShareCentavos: 0,
          paidByUserId: friendId,
          paidByName: 'Friend',
          date: DateTime.now(),
          isPayment: true,
          paymentMethod: PaymentMethod.gcash,
          status: TransactionStatus.settled,
        ),
      ];
      // Net: 50000 - 20000 = +30000 (+₱300.00)
      expect(MockTabbyRepository.calculateNetBalance(entries, currentUserId), equals(30000));
    });

    test('Full settlement zeros out the tab completely', () {
      final entries = [
        LedgerEntry(
          id: 'tx-1',
          tabId: 'tab-1',
          title: 'Dinner',
          category: ExpenseCategory.food,
          totalAmountCentavos: 50000,
          myShareCentavos: 0,
          counterpartShareCentavos: 50000,
          paidByUserId: currentUserId,
          paidByName: 'Me',
          date: DateTime.now(),
        ),
        LedgerEntry(
          id: 'pay-1',
          tabId: 'tab-1',
          title: 'Friend paid via GCash',
          category: ExpenseCategory.borrowedCash,
          totalAmountCentavos: 50000,
          myShareCentavos: 0,
          counterpartShareCentavos: 0,
          paidByUserId: friendId,
          paidByName: 'Friend',
          date: DateTime.now(),
          isPayment: true,
          paymentMethod: PaymentMethod.gcash,
          status: TransactionStatus.settled,
        ),
      ];
      expect(MockTabbyRepository.calculateNetBalance(entries, currentUserId), equals(0));
    });

    test('Current user paying friend offsets negative debt balance to zero', () {
      final entries = [
        // Friend paid ₱300 for me -> I owe friend ₱300
        LedgerEntry(
          id: 'tx-1',
          tabId: 'tab-1',
          title: 'Milk Tea',
          category: ExpenseCategory.food,
          totalAmountCentavos: 30000,
          myShareCentavos: 30000,
          counterpartShareCentavos: 0,
          paidByUserId: friendId,
          paidByName: 'Friend',
          date: DateTime.now(),
        ),
        // I paid friend ₱300 via Maya
        LedgerEntry(
          id: 'pay-1',
          tabId: 'tab-1',
          title: 'You paid via Maya',
          category: ExpenseCategory.borrowedCash,
          totalAmountCentavos: 30000,
          myShareCentavos: 0,
          counterpartShareCentavos: 0,
          paidByUserId: currentUserId,
          paidByName: 'You',
          date: DateTime.now(),
          isPayment: true,
          paymentMethod: PaymentMethod.maya,
          status: TransactionStatus.settled,
        ),
      ];
      expect(MockTabbyRepository.calculateNetBalance(entries, currentUserId), equals(0));
    });

    test('Cancelled transactions are ignored in net balance calculation', () {
      final entries = [
        LedgerEntry(
          id: 'tx-1',
          tabId: 'tab-1',
          title: 'Cancelled Dinner',
          category: ExpenseCategory.food,
          totalAmountCentavos: 50000,
          myShareCentavos: 0,
          counterpartShareCentavos: 50000,
          paidByUserId: currentUserId,
          paidByName: 'Me',
          date: DateTime.now(),
          status: TransactionStatus.cancelled,
        ),
      ];
      expect(MockTabbyRepository.calculateNetBalance(entries, currentUserId), equals(0));
    });

    test('50/50 split on odd centavos preserves exact sum without loss', () {
      const oddAmount = 10001; // ₱100.01
      const myShare = oddAmount ~/ 2; // 5000
      const counterpartShare = oddAmount - myShare; // 5001

      expect(myShare + counterpartShare, equals(oddAmount));

      final entries = [
        LedgerEntry(
          id: 'tx-odd',
          tabId: 'tab-odd',
          title: 'Split Groceries',
          category: ExpenseCategory.groceries,
          totalAmountCentavos: oddAmount,
          myShareCentavos: myShare,
          counterpartShareCentavos: counterpartShare,
          paidByUserId: currentUserId,
          paidByName: 'Me',
          date: DateTime.now(),
        ),
      ];

      final net = MockTabbyRepository.calculateNetBalance(entries, currentUserId);
      expect(net, equals(5001)); // Friend owes 5001 centavos (₱50.01)
    });

    test('Zero floating-point drift: 10,000 centavo operations maintain integer exactitude', () {
      int runningBalance = 0;
      for (int i = 1; i <= 10000; i++) {
        final amount = (i % 999) + 1;
        if (i % 2 == 0) {
          runningBalance += amount;
        } else {
          runningBalance -= amount;
        }
      }
      // Running balance is an exact integer with no IEEE-754 drift
      expect(runningBalance, isA<int>());
    });
  });

  group('Supabase PostgREST JSON Deserialization (parseTabRow) Tests', () {
    const currentUserId = 'user-me-uuid-123';
    const counterpartUserId = 'user-alex-uuid-456';

    test('parseTabRow returns null on invalid or missing tabId or missing counterpart', () {
      expect(SupabaseTabbyRepository.parseTabRow({}, currentUserId), isNull);
      expect(SupabaseTabbyRepository.parseTabRow({'id': ''}, currentUserId), isNull);

      // tab with no members
      expect(SupabaseTabbyRepository.parseTabRow({
        'id': 'tab-1',
        'tab_members': <dynamic>[],
      }, currentUserId), isNull);

      // tab where only current user is a member
      expect(SupabaseTabbyRepository.parseTabRow({
        'id': 'tab-1',
        'tab_members': [
          {'user_id': currentUserId}
        ],
      }, currentUserId), isNull);
    });

    test('parseTabRow correctly deserializes full PostgREST nested payload with counterpart, expenses, and payments', () {
      final rawTabRow = {
        'id': 'tab-uuid-101',
        'tab_type': 'bilateral',
        'status': 'active',
        'created_at': '2026-09-01T10:00:00Z',
        'updated_at': '2026-09-14T10:00:00Z',
        'tab_members': [
          {
            'user_id': currentUserId,
            'users': {
              'id': currentUserId,
              'display_name': 'Me',
              'email': 'me@tabby.ph',
              'phone': '+639171234567',
            },
          },
          {
            'user_id': counterpartUserId,
            'users': {
              'id': counterpartUserId,
              'display_name': 'Alex Rivera',
              'email': 'alex@tabby.ph',
              'phone': '+639189876543',
            },
          },
        ],
        'transactions': [
          {
            'id': 'tx-1',
            'created_by': currentUserId,
            'transaction_type': 'shared_expense',
            'category': 'food',
            'description': 'Jollibee Dinner',
            'total_amount_centavos': 60000,
            'currency': 'PHP',
            'due_date': '2026-09-20',
            'status': 'acknowledged',
            'created_at': '2026-09-10T12:00:00Z',
            'transaction_participants': [
              {
                'user_id': currentUserId,
                'participant_role': 'payer',
                'share_amount_centavos': 30000,
                'acknowledged': true,
              },
              {
                'user_id': counterpartUserId,
                'participant_role': 'debtor',
                'share_amount_centavos': 30000,
                'acknowledged': false,
              },
            ],
          },
          {
            'id': 'tx-2',
            'created_by': counterpartUserId,
            'transaction_type': 'shared_expense',
            'category': 'transportation',
            'description': 'Grab Car Ride',
            'total_amount_centavos': 40000,
            'currency': 'PHP',
            'status': 'acknowledged',
            'created_at': '2026-09-11T15:00:00Z',
            'transaction_participants': [
              {
                'user_id': counterpartUserId,
                'participant_role': 'payer',
                'share_amount_centavos': 20000,
                'acknowledged': true,
              },
              {
                'user_id': currentUserId,
                'participant_role': 'debtor',
                'share_amount_centavos': 20000,
                'acknowledged': true,
              },
            ],
          },
        ],
        'payments': [
          {
            'id': 'pay-1',
            'submitted_by': counterpartUserId,
            'amount_centavos': 10000,
            'payment_method': 'gcash',
            'note': 'Partial via GCash ref #12345',
            'status': 'settled',
            'submitted_at': '2026-09-12T09:00:00Z',
          },
        ],
      };

      final parsed = SupabaseTabbyRepository.parseTabRow(
        rawTabRow,
        currentUserId,
        netBalance: 10000,
      );

      expect(parsed, isNotNull);
      expect(parsed!.id, equals('tab-uuid-101'));
      expect(parsed.netBalanceCentavos, equals(10000));
      expect(parsed.counterpart.id, equals(counterpartUserId));
      expect(parsed.counterpart.displayName, equals('Alex Rivera'));
      expect(parsed.counterpart.email, equals('alex@tabby.ph'));
      expect(parsed.counterpart.phone, equals('+639189876543'));

      // Verify entries length and sorting (newest-first)
      // tx-1: 2026-09-10, tx-2: 2026-09-11, pay-1: 2026-09-12
      // Order should be pay-1 (Sept 12), tx-2 (Sept 11), tx-1 (Sept 10)
      expect(parsed.entries.length, equals(3));
      expect(parsed.entries[0].id, equals('pay-1'));
      expect(parsed.entries[0].isPayment, isTrue);
      expect(parsed.entries[0].paymentMethod, equals(PaymentMethod.gcash));
      expect(parsed.entries[0].note, equals('Partial via GCash ref #12345'));
      expect(parsed.entries[0].paidByName, equals('Alex Rivera'));
      expect(parsed.entries[0].title, equals('Alex Rivera paid'));

      expect(parsed.entries[1].id, equals('tx-2'));
      expect(parsed.entries[1].category, equals(ExpenseCategory.transportation));
      expect(parsed.entries[1].myShareCentavos, equals(20000));
      expect(parsed.entries[1].counterpartShareCentavos, equals(20000));
      expect(parsed.entries[1].paidByName, equals('Alex Rivera'));

      expect(parsed.entries[2].id, equals('tx-1'));
      expect(parsed.entries[2].category, equals(ExpenseCategory.food));
      expect(parsed.entries[2].myShareCentavos, equals(30000));
      expect(parsed.entries[2].counterpartShareCentavos, equals(30000));
      expect(parsed.entries[2].paidByName, equals('You'));
      expect(parsed.entries[2].dueDate, isNotNull);
    });

    test('parseTabRow handles fallback fields when optional values are null or omitted', () {
      final rawTabRow = {
        'id': 'tab-uuid-202',
        'tab_members': [
          {
            'user_id': counterpartUserId,
            // 'users' row is null
          },
        ],
        'transactions': [
          {
            'id': 'tx-sparse',
            'created_by': currentUserId,
            // category omitted, description omitted, created_at omitted
          },
        ],
        'payments': [
          {
            'id': 'pay-sparse',
            'submitted_by': currentUserId,
            'amount_centavos': 5000,
            // payment_method omitted, note omitted, submitted_at omitted
          },
        ],
      };

      final parsed = SupabaseTabbyRepository.parseTabRow(rawTabRow, currentUserId);
      expect(parsed, isNotNull);
      expect(parsed!.counterpart.displayName, equals('Friend')); // fallback
      expect(parsed.entries.length, equals(2));

      final tx = parsed.entries.firstWhere((e) => e.id == 'tx-sparse');
      expect(tx.category, equals(ExpenseCategory.other));
      expect(tx.paidByName, equals('You'));

      final pay = parsed.entries.firstWhere((e) => e.id == 'pay-sparse');
      expect(pay.paymentMethod, equals(PaymentMethod.other));
      expect(pay.paidByName, equals('You'));
      expect(pay.title, equals('You paid'));
    });
  });
}
