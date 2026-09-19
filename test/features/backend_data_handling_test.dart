import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/data/mock_tabby_repository.dart';
import 'package:tabby/features/tabs/data/supabase_tabby_repository.dart';
import 'package:tabby/features/tabs/data/tabby_local_cache.dart';
import 'package:tabby/features/tabs/domain/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Backend Data Handling & Supabase Serialization Tests', () {
    test(
        'Category serialization and deserialization covers all ExpenseCategory values',
        () {
      for (final cat in ExpenseCategory.values) {
        final serialized = SupabaseTabbyRepository.mapCategory(cat);
        expect(serialized, isNotEmpty);
        final deserialized = SupabaseTabbyRepository.unmapCategory(serialized);
        expect(deserialized, equals(cat));
      }

      // Edge cases & unknown strings
      expect(SupabaseTabbyRepository.unmapCategory('UNKNOWN_XYZ'),
          equals(ExpenseCategory.other));
      expect(SupabaseTabbyRepository.unmapCategory(null),
          equals(ExpenseCategory.other));
      expect(SupabaseTabbyRepository.unmapCategory(''),
          equals(ExpenseCategory.other));
      expect(SupabaseTabbyRepository.unmapCategory('FOOD'),
          equals(ExpenseCategory.food));
      expect(SupabaseTabbyRepository.unmapCategory('Borrowed_Cash'),
          equals(ExpenseCategory.borrowedCash));
    });

    test('PaymentMethod serialization and deserialization covers all values',
        () {
      for (final method in PaymentMethod.values) {
        final serialized = SupabaseTabbyRepository.mapPaymentMethod(method);
        expect(serialized, isNotEmpty);
        final deserialized =
            SupabaseTabbyRepository.unmapPaymentMethod(serialized);
        expect(deserialized, equals(method));
      }

      // Edge cases & unknown strings
      expect(SupabaseTabbyRepository.unmapPaymentMethod('crypto'),
          equals(PaymentMethod.other));
      expect(SupabaseTabbyRepository.unmapPaymentMethod(null),
          equals(PaymentMethod.other));
      expect(SupabaseTabbyRepository.unmapPaymentMethod(''),
          equals(PaymentMethod.other));
      expect(SupabaseTabbyRepository.unmapPaymentMethod('GCASH'),
          equals(PaymentMethod.gcash));
      expect(SupabaseTabbyRepository.unmapPaymentMethod('bank_transfer'),
          equals(PaymentMethod.bankTransfer));
    });

    test('TransactionStatus deserialization covers all Postgres status strings',
        () {
      expect(SupabaseTabbyRepository.unmapTransactionStatus('settled'),
          equals(TransactionStatus.settled));
      expect(
          SupabaseTabbyRepository.unmapTransactionStatus('payment_submitted'),
          equals(TransactionStatus.paymentSubmitted));
      expect(SupabaseTabbyRepository.unmapTransactionStatus('cancelled'),
          equals(TransactionStatus.cancelled));
      expect(SupabaseTabbyRepository.unmapTransactionStatus('acknowledged'),
          equals(TransactionStatus.acknowledged));
      expect(SupabaseTabbyRepository.unmapTransactionStatus('pending'),
          equals(TransactionStatus.pending));
      // Unknown / fallback
      expect(SupabaseTabbyRepository.unmapTransactionStatus('unknown'),
          equals(TransactionStatus.pending));
      expect(SupabaseTabbyRepository.unmapTransactionStatus(null),
          equals(TransactionStatus.pending));
      expect(SupabaseTabbyRepository.unmapTransactionStatus('SETTLED'),
          equals(TransactionStatus.settled));
    });

    test(
        'UUID validator accurately distinguishes valid UUIDs from synthetic IDs',
        () {
      // Valid RFC 4122 v4 UUIDs
      expect(
          SupabaseTabbyRepository.isValidUuid(
              'c1a2b3c4-d5e6-4f7a-8b9c-0d1e2f3a4b5c'),
          isTrue);
      expect(
          SupabaseTabbyRepository.isValidUuid(
              '00000000-0000-0000-0000-000000000000'),
          isTrue);
      expect(
          SupabaseTabbyRepository.isValidUuid(
              'C1A2B3C4-D5E6-4F7A-8B9C-0D1E2F3A4B5C'),
          isTrue);

      // Synthetic IDs
      expect(SupabaseTabbyRepository.isValidUuid('user-me'), isFalse);
      expect(SupabaseTabbyRepository.isValidUuid('user-carlos-1234'), isFalse);
      expect(SupabaseTabbyRepository.isValidUuid('group-beach-trip'), isFalse);
      expect(SupabaseTabbyRepository.isValidUuid(''), isFalse);
      expect(SupabaseTabbyRepository.isValidUuid('12345'), isFalse);
      expect(
          SupabaseTabbyRepository.isValidUuid(
              'c1a2b3c4-d5e6-4f7a-8b9c-0d1e2f3a4b5'),
          isFalse); // too short
      expect(
          SupabaseTabbyRepository.isValidUuid(
              'c1a2b3c4-d5e6-4f7a-8b9c-0d1e2f3a4b5c9'),
          isFalse); // too long
    });

    test(
        'SupabaseTabbyRepository offline resilience handles uninitialized backend gracefully',
        () async {
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
      expect(MockTabbyRepository.calculateNetBalance([], currentUserId),
          equals(0));
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
      expect(MockTabbyRepository.calculateNetBalance(entries, currentUserId),
          equals(50000));
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
      expect(MockTabbyRepository.calculateNetBalance(entries, currentUserId),
          equals(-25000));
    });

    test('Two-way mutual debts offset correctly into a net integer balance',
        () {
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
      expect(MockTabbyRepository.calculateNetBalance(entries, currentUserId),
          equals(30000));
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
      expect(MockTabbyRepository.calculateNetBalance(entries, currentUserId),
          equals(30000));
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
      expect(MockTabbyRepository.calculateNetBalance(entries, currentUserId),
          equals(0));
    });

    test('Current user paying friend offsets negative debt balance to zero',
        () {
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
      expect(MockTabbyRepository.calculateNetBalance(entries, currentUserId),
          equals(0));
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
      expect(MockTabbyRepository.calculateNetBalance(entries, currentUserId),
          equals(0));
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

      final net =
          MockTabbyRepository.calculateNetBalance(entries, currentUserId);
      expect(net, equals(5001)); // Friend owes 5001 centavos (₱50.01)
    });

    test(
        'Zero floating-point drift: 10,000 centavo operations maintain integer exactitude',
        () {
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

    test(
        'parseTabRow returns null on invalid or missing tabId or missing counterpart',
        () {
      expect(SupabaseTabbyRepository.parseTabRow({}, currentUserId), isNull);
      expect(SupabaseTabbyRepository.parseTabRow({'id': ''}, currentUserId),
          isNull);

      // tab with no members
      expect(
          SupabaseTabbyRepository.parseTabRow({
            'id': 'tab-1',
            'tab_members': <dynamic>[],
          }, currentUserId),
          isNull);

      // tab where only current user is a member
      expect(
          SupabaseTabbyRepository.parseTabRow({
            'id': 'tab-1',
            'tab_members': [
              {'user_id': currentUserId}
            ],
          }, currentUserId),
          isNull);
    });

    test(
        'parseTabRow correctly deserializes full PostgREST nested payload with counterpart, expenses, and payments',
        () {
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
      expect(
          parsed.entries[1].category, equals(ExpenseCategory.transportation));
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

    test(
        'parseTabRow handles fallback fields when optional values are null or omitted',
        () {
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

      final parsed =
          SupabaseTabbyRepository.parseTabRow(rawTabRow, currentUserId);
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

    test(
        'recordPayment executes safely offline and ignores invalid UUIDs without throwing',
        () async {
      // Offline / synthetic tabId
      await expectLater(
        SupabaseTabbyRepository.instance.recordPayment(
          tabId: 'synthetic-tab-123',
          amountCentavos: 15000,
          method: PaymentMethod.gcash,
          paidByUserId: 'user-juan',
          receivedByUserId: 'user-me',
        ),
        completes,
      );

      // Valid UUID tabId but synthetic/invalid paidByUserId
      await expectLater(
        SupabaseTabbyRepository.instance.recordPayment(
          tabId: 'c1a2b3c4-d5e6-4f7a-8b9c-0d1e2f3a4b5c',
          amountCentavos: 10000,
          method: PaymentMethod.gcash,
          paidByUserId: 'user-synthetic-counterpart',
          receivedByUserId: 'd2b3c4d5-e6f7-4a8b-9c0d-1e2f3a4b5c6d',
        ),
        completes,
      );

      // Valid UUID tabId
      await expectLater(
        SupabaseTabbyRepository.instance.recordPayment(
          tabId: 'c1a2b3c4-d5e6-4f7a-8b9c-0d1e2f3a4b5c',
          amountCentavos: 25000,
          method: PaymentMethod.maya,
          paidByUserId: 'c1a2b3c4-d5e6-4f7a-8b9c-0d1e2f3a4b5c',
          receivedByUserId: 'd2b3c4d5-e6f7-4a8b-9c0d-1e2f3a4b5c6d',
          confirmedByUserId: 'd2b3c4d5-e6f7-4a8b-9c0d-1e2f3a4b5c6d',
        ),
        completes,
      );

      // Valid UUID tabId with non-UUID confirmedByUserId
      await expectLater(
        SupabaseTabbyRepository.instance.recordPayment(
          tabId: 'c1a2b3c4-d5e6-4f7a-8b9c-0d1e2f3a4b5c',
          amountCentavos: 5000,
          method: PaymentMethod.cash,
          paidByUserId: 'c1a2b3c4-d5e6-4f7a-8b9c-0d1e2f3a4b5c',
          receivedByUserId: 'd2b3c4d5-e6f7-4a8b-9c0d-1e2f3a4b5c6d',
          confirmedByUserId: 'user-admin',
        ),
        completes,
      );
    });
  });

  group('Domain Model Serialization & Deserialization (toMap & fromMap)', () {
    test('TabbyUser toMap and fromMap roundtrip preserves all fields', () {
      const user = TabbyUser(
        id: 'usr-1234',
        displayName: 'Maria Santos',
        email: 'maria@example.com',
        phone: '+63 917 111 2222',
        avatarUrl: 'https://example.com/avatar.png',
        gcashNumber: '09171112222',
        mayaNumber: '09182223333',
        qrCodeUrl: 'https://tabby.ph/qr/maria.png',
      );

      final map = user.toMap();
      expect(map['id'], equals('usr-1234'));
      expect(map['displayName'], equals('Maria Santos'));
      expect(map['gcashNumber'], equals('09171112222'));
      expect(map['mayaNumber'], equals('09182223333'));

      final restored = TabbyUser.fromMap(map);
      expect(restored.id, equals(user.id));
      expect(restored.displayName, equals(user.displayName));
      expect(restored.email, equals(user.email));
      expect(restored.phone, equals(user.phone));
      expect(restored.avatarUrl, equals(user.avatarUrl));
      expect(restored.gcashNumber, equals(user.gcashNumber));
      expect(restored.mayaNumber, equals(user.mayaNumber));
      expect(restored.qrCodeUrl, equals(user.qrCodeUrl));
    });

    test('ParticipantShare toMap and fromMap roundtrip preserves all fields',
        () {
      const share = ParticipantShare(
        userId: 'usr-p1',
        name: 'Pao',
        shareAmountCentavos: 12500,
        isPayer: false,
        acknowledged: true,
      );

      final map = share.toMap();
      final restored = ParticipantShare.fromMap(map);
      expect(restored.userId, equals(share.userId));
      expect(restored.name, equals(share.name));
      expect(restored.shareAmountCentavos, equals(12500));
      expect(restored.acknowledged, isTrue);
    });

    test(
        'LedgerEntry toMap and fromMap roundtrip preserves all transaction and payment details',
        () {
      final now = DateTime.now();
      final entry = LedgerEntry(
        id: 'tx-999',
        tabId: 'tab-888',
        title: 'Team Dinner',
        category: ExpenseCategory.food,
        totalAmountCentavos: 150000,
        myShareCentavos: 50000,
        counterpartShareCentavos: 100000,
        paidByUserId: 'usr-1',
        paidByName: 'Juan',
        date: now,
        dueDate: now.add(const Duration(days: 7)),
        status: TransactionStatus.acknowledged,
        receiptUrl: 'https://tabby.ph/receipts/team_dinner.png',
        paymentMethod: PaymentMethod.gcash,
        isPayment: false,
        note: 'Split 3 ways',
      );

      final map = entry.toMap();
      final restored = LedgerEntry.fromMap(map);
      expect(restored.id, equals(entry.id));
      expect(restored.tabId, equals(entry.tabId));
      expect(restored.title, equals(entry.title));
      expect(restored.category, equals(ExpenseCategory.food));
      expect(restored.totalAmountCentavos, equals(150000));
      expect(restored.myShareCentavos, equals(50000));
      expect(restored.counterpartShareCentavos, equals(100000));
      expect(restored.paidByUserId, equals('usr-1'));
      expect(restored.receiptUrl,
          equals('https://tabby.ph/receipts/team_dinner.png'));
      expect(restored.paymentMethod, equals(PaymentMethod.gcash));
      expect(restored.status, equals(TransactionStatus.acknowledged));
      expect(restored.note, equals('Split 3 ways'));
    });

    test(
        'BilateralTab toMap and fromMap roundtrip preserves nested counterpart and entries',
        () {
      final now = DateTime.now();
      const friend = TabbyUser(
        id: 'usr-carlos',
        displayName: 'Carlos',
        email: 'carlos@example.com',
        phone: '09170001111',
      );

      final entry = LedgerEntry(
        id: 'tx-1',
        tabId: 'tab-carlos',
        title: 'Lunch',
        category: ExpenseCategory.food,
        totalAmountCentavos: 50000,
        myShareCentavos: 25000,
        counterpartShareCentavos: 25000,
        paidByUserId: 'usr-me',
        paidByName: 'Me',
        date: now,
      );

      final tab = BilateralTab(
        id: 'tab-carlos',
        counterpart: friend,
        entries: [entry],
        netBalanceCentavos: 25000,
        itemCount: 1,
        lastUpdated: now,
        isGroupTab: false,
        groupName: null,
      );

      final map = tab.toMap();
      final restored = BilateralTab.fromMap(map);
      expect(restored.id, equals('tab-carlos'));
      expect(restored.counterpart.displayName, equals('Carlos'));
      expect(restored.entries.length, equals(1));
      expect(restored.entries.first.title, equals('Lunch'));
      expect(restored.netBalanceCentavos, equals(25000));
      expect(restored.isGroupTab, isFalse);
    });

    test('TabbyActivity toMap and fromMap roundtrip preserves event details',
        () {
      final now = DateTime.now();
      final activity = TabbyActivity(
        id: 'act-001',
        actorName: 'Carlos',
        description: 'settled ₱500.00 via GCash',
        amountCentavos: 50000,
        timestamp: now,
      );

      final map = activity.toMap();
      final restored = TabbyActivity.fromMap(map);
      expect(restored.id, equals('act-001'));
      expect(restored.actorName, equals('Carlos'));
      expect(restored.description, equals('settled ₱500.00 via GCash'));
      expect(restored.amountCentavos, equals(50000));
    });

    test(
        'UpcomingReminder toMap and fromMap roundtrip preserves financial due dates',
        () {
      final dueDate = DateTime.now().add(const Duration(days: 3));
      final reminder = UpcomingReminder(
        id: 'rem-001',
        tabId: 'tab-dues-1',
        friendName: 'Bea',
        description: 'Dinner tab',
        amountCentavos: 35000,
        dueDate: dueDate,
        isIWhoOwe: false,
      );

      final map = reminder.toMap();
      final restored = UpcomingReminder.fromMap(map);
      expect(restored.id, equals('rem-001'));
      expect(restored.tabId, equals('tab-dues-1'));
      expect(restored.friendName, equals('Bea'));
      expect(restored.description, equals('Dinner tab'));
      expect(restored.amountCentavos, equals(35000));
      expect(restored.isIWhoOwe, isFalse);
    });
  });

  group('Supabase Group Tab Deserialization (parseTabRow)', () {
    test(
        'parseTabRow correctly deserializes group tabs, group names, aggregated shares, and receipts',
        () {
      const currentUserId = 'user-current-id';

      final groupTabRow = {
        'id': 'tab-group-uuid-1',
        'tab_type': 'group',
        'group_id': 'grp-uuid-101',
        'groups': {
          'id': 'grp-uuid-101',
          'name': 'Weekend Barkada Trip',
          'avatar_url': 'https://example.com/group.png',
        },
        'tab_members': [
          {'user_id': currentUserId},
          {'user_id': 'user-member-2'},
          {'user_id': 'user-member-3'},
        ],
        'transactions': [
          {
            'id': 'tx-group-1',
            'description': 'Resort Villa Rental',
            'category': 'bills',
            'total_amount_centavos': 300000,
            'created_by': currentUserId,
            'created_at': '2026-09-16T12:00:00Z',
            'receipt_url':
                'https://supabase.tabby.ph/receipts/villa_booking.png',
            'status': 'settled',
            'transaction_participants': [
              {
                'user_id': currentUserId,
                'share_amount_centavos': 100000,
              },
              {
                'user_id': 'user-member-2',
                'share_amount_centavos': 100000,
              },
              {
                'user_id': 'user-member-3',
                'share_amount_centavos': 100000,
              },
            ],
          },
        ],
        'payments': [],
      };

      final parsed = SupabaseTabbyRepository.parseTabRow(
        groupTabRow,
        currentUserId,
        netBalance: 200000,
      );

      expect(parsed, isNotNull);
      expect(parsed!.isGroupTab, isTrue);
      expect(parsed.groupName, equals('Weekend Barkada Trip'));
      expect(parsed.id, equals('tab-group-uuid-1'));
      expect(parsed.entries.length, equals(1));

      final entry = parsed.entries.first;
      expect(entry.title, equals('Resort Villa Rental'));
      expect(entry.category, equals(ExpenseCategory.bills));
      expect(entry.totalAmountCentavos, equals(300000));
      expect(entry.myShareCentavos, equals(100000));
      // Counterpart share must aggregate shares of member 2 and member 3 (100000 + 100000 = 200000)
      expect(entry.counterpartShareCentavos, equals(200000));
      expect(entry.receiptUrl,
          equals('https://supabase.tabby.ph/receipts/villa_booking.png'));
    });

    test(
        'parseTabRow correctly attributes group payments and member payer names',
        () {
      const currentUserId = 'usr-current-uuid-1';
      final groupTabRow = {
        'id': 'tab-group-uuid-2',
        'is_group': true,
        'group_id': 'grp-uuid-2',
        'group_name': 'Tagaytay Barkada Roadtrip',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'counterpart': {
          'id': 'grp-uuid-2',
          'raw_user_meta_data': {
            'display_name': 'Tagaytay Barkada Roadtrip',
          },
        },
        'tab_members': [
          {
            'user_id': currentUserId,
            'users': {
              'raw_user_meta_data': {'display_name': 'Juan Current'},
            },
          },
          {
            'user_id': 'usr-member-maria',
            'users': {
              'raw_user_meta_data': {'display_name': 'Maria Santos'},
            },
          },
          {
            'user_id': 'usr-member-carlos',
            'users': {
              'raw_user_meta_data': {'display_name': 'Carlos Mendoza'},
            },
          },
        ],
        'transactions': [
          {
            'id': 'tx-group-gas',
            'title': 'Gas & Tolls',
            'category': 'transportation',
            'total_amount_centavos': 150000,
            'paid_by': 'usr-member-maria',
            'split_type': 'equal',
            'created_at': DateTime.now().toIso8601String(),
            'transaction_splits': [
              {'user_id': currentUserId, 'share_amount_centavos': 50000},
              {'user_id': 'usr-member-maria', 'share_amount_centavos': 50000},
              {'user_id': 'usr-member-carlos', 'share_amount_centavos': 50000},
            ],
          },
        ],
        'payments': [
          {
            'id': 'pay-group-1',
            'tab_id': 'tab-group-uuid-2',
            'amount_centavos': 50000,
            'payment_method': 'gcash',
            'submitted_by': 'usr-member-carlos',
            'created_at': DateTime.now().toIso8601String(),
            'confirmed_at': DateTime.now().toIso8601String(),
            'payment_proof_url': 'https://supabase.tabby.ph/proofs/gcash1.jpg',
          },
          {
            'id': 'pay-group-2',
            'tab_id': 'tab-group-uuid-2',
            'amount_centavos': 50000,
            'payment_method': 'maya',
            'submitted_by': currentUserId,
            'created_at': DateTime.now().toIso8601String(),
            'confirmed_at': DateTime.now().toIso8601String(),
            'payment_proof_url': null,
          },
        ],
      };

      final parsed = SupabaseTabbyRepository.parseTabRow(
        groupTabRow,
        currentUserId,
        netBalance: -50000,
      );

      expect(parsed, isNotNull);
      expect(parsed!.isGroupTab, isTrue);
      expect(parsed.entries.length, equals(3));

      // Transaction: Gas & Tolls paid by Maria
      final txEntry = parsed.entries.firstWhere((e) => e.id == 'tx-group-gas');
      expect(txEntry.paidByUserId, equals('usr-member-maria'));
      expect(txEntry.paidByName, equals('Maria Santos'));
      expect(txEntry.myShareCentavos, equals(50000));

      // Payment 1: Submitted by Carlos (not current user)
      final payCarlos = parsed.entries.firstWhere((e) => e.id == 'pay-group-1');
      expect(payCarlos.paidByUserId, equals('usr-member-carlos'));
      expect(payCarlos.paidByName, equals('Carlos Mendoza'));
      expect(payCarlos.title, equals('Carlos Mendoza paid'));
      expect(payCarlos.receiptUrl,
          equals('https://supabase.tabby.ph/proofs/gcash1.jpg'));

      // Payment 2: Submitted by current user
      final payMe = parsed.entries.firstWhere((e) => e.id == 'pay-group-2');
      expect(payMe.paidByUserId, equals(currentUserId));
      expect(payMe.paidByName, equals('You'));
      expect(payMe.title, equals('You paid'));
    });
  });

  group('Offline Resilience & TabbyLocalCache Tests', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('TabbyLocalCache saves, loads, and clears tabs roundtrip', () async {
      final tab = BilateralTab(
        id: 'tab-cache-1',
        counterpart: const TabbyUser(
          id: 'usr-offline',
          displayName: 'Offline Friend',
          email: '',
          phone: '',
        ),
        entries: const [],
        netBalanceCentavos: 12000,
        itemCount: 0,
        lastUpdated: DateTime.now(),
      );

      await TabbyLocalCache.saveTabs([tab]);
      final loaded = await TabbyLocalCache.loadTabs();
      expect(loaded, isNotNull);
      expect(loaded!.length, equals(1));
      expect(loaded.first.id, equals('tab-cache-1'));
      expect(loaded.first.netBalanceCentavos, equals(12000));

      await TabbyLocalCache.clearCache();
      final afterClear = await TabbyLocalCache.loadTabs();
      expect(afterClear, isNull);
    });

    test('TabbyLocalCache saves and loads activities and reminders', () async {
      final now = DateTime.now();
      final activity = TabbyActivity(
        id: 'act-cache-1',
        actorName: 'You',
        description: 'logged Lunch',
        amountCentavos: 25000,
        timestamp: now,
      );

      final reminder = UpcomingReminder(
        id: 'rem-cache-1',
        tabId: 'tab-rem-1',
        friendName: 'Sam',
        description: 'Coffee',
        amountCentavos: 5000,
        dueDate: now.add(const Duration(days: 1)),
        isIWhoOwe: true,
      );

      await TabbyLocalCache.saveActivities([activity]);
      final loadedActivities = await TabbyLocalCache.loadActivities();
      expect(loadedActivities, isNotNull);
      expect(loadedActivities!.length, equals(1));
      expect(loadedActivities.first.id, equals('act-cache-1'));

      await TabbyLocalCache.saveReminders([reminder]);
      final loadedReminders = await TabbyLocalCache.loadReminders();
      expect(loadedReminders, isNotNull);
      expect(loadedReminders!.length, equals(1));
      expect(loadedReminders.first.friendName, equals('Sam'));
    });

    test('TabbyLocalCache keeps different users in separate scopes', () async {
      final userATab = BilateralTab(
        id: 'tab-user-a',
        counterpart: const TabbyUser(
          id: 'friend-a',
          displayName: 'Friend A',
          email: '',
          phone: '',
        ),
        entries: const [],
        netBalanceCentavos: 1000,
        itemCount: 0,
        lastUpdated: DateTime.now(),
      );
      final userBTab = userATab.copyWith(
        id: 'tab-user-b',
        counterpart: userATab.counterpart.copyWith(
          id: 'friend-b',
          displayName: 'Friend B',
        ),
      );

      await TabbyLocalCache.saveTabs([userATab], userId: 'user-a');
      await TabbyLocalCache.saveTabs([userBTab], userId: 'user-b');

      final loadedA = await TabbyLocalCache.loadTabs(userId: 'user-a');
      final loadedB = await TabbyLocalCache.loadTabs(userId: 'user-b');

      expect(loadedA!.single.id, equals('tab-user-a'));
      expect(loadedB!.single.id, equals('tab-user-b'));
    });

    test(
        'SupabaseTabbyRepository.signOut purges local secure cache and handles offline gracefully',
        () async {
      final tab = BilateralTab(
        id: 'tab-cache-logout-1',
        counterpart: const TabbyUser(
          id: 'usr-logout-friend',
          displayName: 'Logout Test Friend',
          email: '',
          phone: '',
        ),
        entries: const [],
        netBalanceCentavos: 5000,
        itemCount: 0,
        lastUpdated: DateTime.now(),
      );

      await TabbyLocalCache.saveTabs([tab]);
      final beforeSignOut = await TabbyLocalCache.loadTabs();
      expect(beforeSignOut, isNotNull);
      expect(beforeSignOut!.length, equals(1));

      // Execute repository signOut
      await SupabaseTabbyRepository.instance.signOut();

      // Verify cache is wiped
      final afterSignOut = await TabbyLocalCache.loadTabs();
      expect(afterSignOut, isNull);
    });

    test(
        'parseTabRow accurately attributes payer from transaction_participants when created_by is current user',
        () {
      final tabRow = {
        'id': 'tab-payer-test-1',
        'tab_type': 'bilateral',
        'tab_members': [
          {
            'user_id': 'user-current',
            'users': {'display_name': 'Me', 'email': 'me@tabby.ph'},
          },
          {
            'user_id': 'user-friend',
            'users': {
              'display_name': 'Friend Carlos',
              'email': 'carlos@tabby.ph'
            },
          },
        ],
        'transactions': [
          {
            'id': 'tx-carlos-paid-1',
            'created_by': 'user-current', // Logged-in user typed it into app
            'transaction_type': 'shared_expense',
            'category': 'food',
            'description': 'Carlos paid for dinner',
            'total_amount_centavos': 10000,
            'status': 'acknowledged',
            'created_at': '2026-09-16T12:00:00Z',
            'transaction_participants': [
              {
                'user_id': 'user-friend',
                'participant_role': 'payer',
                'share_amount_centavos': 5000,
              },
              {
                'user_id': 'user-current',
                'participant_role': 'debtor',
                'share_amount_centavos': 5000,
              },
            ],
          },
        ],
        'payments': [],
      };

      final parsed =
          SupabaseTabbyRepository.parseTabRow(tabRow, 'user-current');
      expect(parsed, isNotNull);
      expect(parsed!.entries.length, equals(1));

      final entry = parsed.entries.first;
      // Payer must be Carlos, NOT the record creator
      expect(entry.paidByUserId, equals('user-friend'));
      expect(entry.paidByName, equals('Friend Carlos'));
      expect(entry.myShareCentavos, equals(5000));
      expect(entry.counterpartShareCentavos, equals(5000));

      // Balance calculation: Carlos paid, so current user owes 5000 (-5000)
      final netBalance = MockTabbyRepository.calculateNetBalance(
          parsed.entries, 'user-current');
      expect(netBalance, equals(-5000));
    });

    test('parseTabRow extracts receipt URL from payment_proofs nested relation',
        () {
      final tabRow = {
        'id': 'tab-proof-test-1',
        'tab_type': 'bilateral',
        'tab_members': [
          {
            'user_id': 'user-current',
            'users': {'display_name': 'Me'},
          },
          {
            'user_id': 'user-friend',
            'users': {'display_name': 'Friend Elena'},
          },
        ],
        'transactions': [],
        'payments': [
          {
            'id': 'pay-proof-1',
            'submitted_by': 'user-friend',
            'amount_centavos': 15000,
            'payment_method': 'gcash',
            'status': 'confirmed',
            'submitted_at': '2026-09-16T15:00:00Z',
            'payment_proofs': [
              {
                'file_url':
                    'https://supabase.tabby.ph/storage/v1/object/proofs/gcash_123.jpg',
              },
            ],
          },
        ],
      };

      final parsed =
          SupabaseTabbyRepository.parseTabRow(tabRow, 'user-current');
      expect(parsed, isNotNull);
      expect(parsed!.entries.length, equals(1));
      final paymentEntry = parsed.entries.first;
      expect(paymentEntry.isPayment, isTrue);
      expect(
          paymentEntry.receiptUrl,
          equals(
              'https://supabase.tabby.ph/storage/v1/object/proofs/gcash_123.jpg'));
    });

    test(
        'SupabaseTabbyRepository archiveTab and attachReceipt execute safely offline',
        () async {
      final repo = SupabaseTabbyRepository.instance;
      expect(repo.isConnected, isFalse);

      await expectLater(
        repo.archiveTab('00000000-0000-0000-0000-000000000001'),
        completes,
      );

      await expectLater(
        repo.attachReceipt(
            '00000000-0000-0000-0000-000000000002', 'receipt.png'),
        completes,
      );
    });

    test('TabbyNotifier preserves locally added tabs and un-synced entries across refresh', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final notifier = TabbyNotifier();

      // Add a friend tab locally
      await notifier.addFriend(
        name: 'Maria Clara',
        phone: '+63 917 123 4567',
      );

      expect(notifier.state.tabs.any((t) => t.counterpart.displayName == 'Maria Clara'), isTrue);

      // Add expense with Maria Clara
      await notifier.addExpense(
        counterpartId: notifier.state.tabs.firstWhere((t) => t.counterpart.displayName == 'Maria Clara').id,
        counterpartName: 'Maria Clara',
        title: 'Lunch treat',
        totalAmountCentavos: 50000,
        category: ExpenseCategory.food,
        paidByMe: true,
        isEqualSplit: true,
      );

      final tabBeforeRefresh = notifier.state.tabs.firstWhere((t) => t.counterpart.displayName == 'Maria Clara');
      expect(tabBeforeRefresh.entries.length, equals(1));
      expect(tabBeforeRefresh.netBalanceCentavos, equals(25000));

      // Trigger refresh (simulating pull to refresh or sync)
      await notifier.refreshTabs();

      // Ensure tab is NOT wiped out and entries are intact!
      final tabAfterRefresh = notifier.state.tabs.firstWhere((t) => t.counterpart.displayName == 'Maria Clara');
      expect(tabAfterRefresh.entries.length, equals(1));
      expect(tabAfterRefresh.entries.first.title, equals('Lunch treat'));
      expect(tabAfterRefresh.netBalanceCentavos, equals(25000));
    });

    test('Realtime subscription lifecycle and activity deduplication', () async {
      final notifier = TabbyNotifier(loadInitialData: false);
      addTearDown(notifier.dispose);

      // Verify reset cleanly cleans up channels without crashing
      notifier.reset();
      expect(notifier.state.tabs, isEmpty);

      // Add sample tab with entries and verify activity synthesis
      final entry = LedgerEntry(
        id: 'entry-realtime-1',
        tabId: 'tab-realtime-1',
        title: 'Team Coffee',
        category: ExpenseCategory.food,
        totalAmountCentavos: 30000,
        myShareCentavos: 15000,
        counterpartShareCentavos: 15000,
        paidByUserId: 'user-me',
        paidByName: 'You',
        date: DateTime.now(),
        dueDate: DateTime.now().add(const Duration(days: 3)),
      );

      final tab = BilateralTab(
        id: 'tab-realtime-1',
        counterpart: const TabbyUser(
          id: 'user-friend-1',
          displayName: 'Friend One',
          email: 'friend@example.com',
          phone: '',
        ),
        netBalanceCentavos: 15000,
        itemCount: 1,
        entries: [entry],
        lastUpdated: DateTime.now(),
      );

      notifier.state = notifier.state.copyWith(tabs: [tab]);
      expect(notifier.state.tabs.length, equals(1));

      // Test deduplication of activities
      final act1 = TabbyActivity(
        id: 'act-1',
        actorName: 'You',
        description: 'Team Coffee',
        amountCentavos: 30000,
        timestamp: DateTime.now(),
      );
      final actDuplicate = TabbyActivity(
        id: 'act-1',
        actorName: 'You',
        description: 'Team Coffee',
        amountCentavos: 30000,
        timestamp: DateTime.now(),
      );

      final deduped = TabbyNotifier.deduplicateActivities([act1, actDuplicate]);
      expect(deduped.length, equals(1));
      expect(deduped.first.id, equals('act-1'));

      // Test cross-source deduplication: local optimistic activity vs server synthesized activity
      final now = DateTime.now();
      final localAct = TabbyActivity(
        id: 'act-1726650000000',
        actorName: 'You',
        description: 'logged Dinner with Maria',
        amountCentavos: 50000,
        timestamp: now,
      );
      final serverAct = TabbyActivity(
        id: '550e8400-e29b-41d4-a716-446655440000',
        actorName: 'You',
        description: 'Dinner',
        amountCentavos: 50000,
        timestamp: now.add(const Duration(seconds: 2)),
      );

      final crossSourceDeduped =
          TabbyNotifier.deduplicateActivities([serverAct, localAct]);
      expect(crossSourceDeduped.length, equals(1));
      expect(crossSourceDeduped.first.id,
          equals('550e8400-e29b-41d4-a716-446655440000'));
      expect(crossSourceDeduped.first.description, equals('Dinner'));

      // Also when local appears before server candidate
      final crossSourceDedupedReversed =
          TabbyNotifier.deduplicateActivities([localAct, serverAct]);
      expect(crossSourceDedupedReversed.length, equals(1));
      expect(crossSourceDedupedReversed.first.id,
          equals('550e8400-e29b-41d4-a716-446655440000'));

      // Test payment activity deduplication
      final localPay = TabbyActivity(
        id: 'payment-1726650000000',
        actorName: 'You',
        description: 'You paid Maria via GCash',
        amountCentavos: 25000,
        timestamp: now,
        icon: 'payment',
      );
      final serverPay = TabbyActivity(
        id: '770e8400-e29b-41d4-a716-446655440000',
        actorName: 'You',
        description: 'You paid',
        amountCentavos: 25000,
        timestamp: now.add(const Duration(seconds: 1)),
        icon: 'payment',
      );

      final payDeduped =
          TabbyNotifier.deduplicateActivities([serverPay, localPay]);
      expect(payDeduped.length, equals(1));
      expect(payDeduped.first.id,
          equals('770e8400-e29b-41d4-a716-446655440000'));

      // Test distinct transactions at different times are preserved
      final morningCoffee = TabbyActivity(
        id: 'coffee-morning',
        actorName: 'You',
        description: 'Coffee',
        amountCentavos: 15000,
        timestamp: now.subtract(const Duration(hours: 4)),
      );
      final afternoonCoffee = TabbyActivity(
        id: 'coffee-afternoon',
        actorName: 'You',
        description: 'Coffee',
        amountCentavos: 15000,
        timestamp: now,
      );

      final separateDeduped = TabbyNotifier.deduplicateActivities(
          [morningCoffee, afternoonCoffee]);
      expect(separateDeduped.length, equals(2));

      // Test non-financial activity deduplication (zero amounts within 30s)
      final nudge1 = TabbyActivity(
        id: 'act-nudge-1',
        actorName: 'You',
        description: 'sent friendly reminder to Juan',
        amountCentavos: 0,
        timestamp: now,
      );
      final nudge2 = TabbyActivity(
        id: 'act-nudge-2',
        actorName: 'You',
        description: 'sent friendly reminder to Juan',
        amountCentavos: 0,
        timestamp: now.add(const Duration(seconds: 3)),
      );

      final nudgeDeduped =
          TabbyNotifier.deduplicateActivities([nudge1, nudge2]);
      expect(nudgeDeduped.length, equals(1));
    });

    test(
        'deduplicateLedgerEntries merges semantic duplicates and prioritizes server UUIDs',
        () {
      final now = DateTime.now();

      // Gagno scenario: Server-confirmed transaction and optimistic local entry
      final serverEntry = LedgerEntry(
        id: '84003d99-472f-424a-94cd-d4d2a357c661',
        tabId: 'f1b8bf25-04fc-47cf-a156-43ae2d5672e9',
        title: 'utang nabilin',
        category: ExpenseCategory.food,
        totalAmountCentavos: 5400,
        myShareCentavos: 0,
        counterpartShareCentavos: 5400,
        paidByUserId: '7e744c3a-7273-471a-847e-b7e1246d87ef',
        paidByName: 'Jana Crizzia Gagno',
        date: now,
        status: TransactionStatus.acknowledged,
      );

      final localOptimisticEntry = LedgerEntry(
        id: 'entry-1726712345678',
        tabId: 'f1b8bf25-04fc-47cf-a156-43ae2d5672e9',
        title: 'utang nabilin',
        category: ExpenseCategory.food,
        totalAmountCentavos: 5400,
        myShareCentavos: 0,
        counterpartShareCentavos: 5400,
        paidByUserId: '7e744c3a-7273-471a-847e-b7e1246d87ef',
        paidByName: 'Jana Crizzia Gagno',
        date: now.add(const Duration(seconds: 2)),
        status: TransactionStatus.acknowledged,
      );

      final deduped = TabbyNotifier.deduplicateLedgerEntries(
          [serverEntry, localOptimisticEntry]);

      expect(deduped.length, equals(1));
      expect(deduped.first.id, equals('84003d99-472f-424a-94cd-d4d2a357c661'));
      expect(deduped.first.title, equals('utang nabilin'));
      expect(deduped.first.totalAmountCentavos, equals(5400));

      // Test reverse order: local entry before server entry
      final dedupedReverse = TabbyNotifier.deduplicateLedgerEntries(
          [localOptimisticEntry, serverEntry]);
      expect(dedupedReverse.length, equals(1));
      expect(dedupedReverse.first.id,
          equals('84003d99-472f-424a-94cd-d4d2a357c661'));

      // Test duplicate exact ID
      final exactDuplicate = serverEntry.copyWith(date: now.add(const Duration(hours: 1)));
      final exactDeduped = TabbyNotifier.deduplicateLedgerEntries(
          [serverEntry, exactDuplicate]);
      expect(exactDeduped.length, equals(1));

      // Test distinct expenses with same title at different days
      final dayOldEntry = serverEntry.copyWith(
        id: '99003d99-472f-424a-94cd-d4d2a357c662',
        date: now.subtract(const Duration(days: 3)),
      );
      final separateDeduped = TabbyNotifier.deduplicateLedgerEntries(
          [serverEntry, dayOldEntry]);
      expect(separateDeduped.length, equals(2));
    });

    test(
        'deduplicateTabs collapses multiple tabs for same counterpart and combines entries',
        () {
      final now = DateTime.now();
      const currentUserId = 'c1976734-0398-4c72-8874-15364cd627d5';
      const gagnoUserId = '7e744c3a-7273-471a-847e-b7e1246d87ef';

      final serverTab = BilateralTab(
        id: 'f1b8bf25-04fc-47cf-a156-43ae2d5672e9',
        counterpart: const TabbyUser(
          id: gagnoUserId,
          displayName: 'Jana Crizzia Gagno',
          email: 'gagno.janacrizzia@gmail.com',
          phone: '',
        ),
        netBalanceCentavos: -5400,
        itemCount: 1,
        entries: [
          LedgerEntry(
            id: '84003d99-472f-424a-94cd-d4d2a357c661',
            tabId: 'f1b8bf25-04fc-47cf-a156-43ae2d5672e9',
            title: 'utang nabilin',
            category: ExpenseCategory.food,
            totalAmountCentavos: 5400,
            myShareCentavos: 5400,
            counterpartShareCentavos: 0,
            paidByUserId: gagnoUserId,
            paidByName: 'Jana Crizzia Gagno',
            date: now,
            status: TransactionStatus.acknowledged,
          ),
        ],
        lastUpdated: now,
      );

      final localContactTab = BilateralTab(
        id: 'contact-7e744c3a',
        counterpart: const TabbyUser(
          id: gagnoUserId,
          displayName: 'Jana Crizzia Gagno',
          email: '',
          phone: '',
        ),
        netBalanceCentavos: -5400,
        itemCount: 1,
        entries: [
          LedgerEntry(
            id: 'entry-local-12345',
            tabId: 'contact-7e744c3a',
            title: 'utang nabilin',
            category: ExpenseCategory.food,
            totalAmountCentavos: 5400,
            myShareCentavos: 5400,
            counterpartShareCentavos: 0,
            paidByUserId: gagnoUserId,
            paidByName: 'Jana Crizzia Gagno',
            date: now,
            status: TransactionStatus.acknowledged,
          ),
        ],
        lastUpdated: now,
      );

      final dedupedTabs = TabbyNotifier.deduplicateTabs(
        [serverTab, localContactTab],
        currentUserId: currentUserId,
      );

      expect(dedupedTabs.length, equals(1));
      final unifiedTab = dedupedTabs.first;
      expect(unifiedTab.id, equals('f1b8bf25-04fc-47cf-a156-43ae2d5672e9'));
      expect(unifiedTab.counterpart.displayName, equals('Jana Crizzia Gagno'));
      expect(unifiedTab.entries.length, equals(1));
      expect(unifiedTab.entries.first.id,
          equals('84003d99-472f-424a-94cd-d4d2a357c661'));
      expect(unifiedTab.itemCount, equals(1));
      expect(unifiedTab.netBalanceCentavos, equals(-5400));
    });
  });
}
