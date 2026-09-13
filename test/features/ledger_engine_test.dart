import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/tabs/application/tabby_state.dart';
import 'package:tabby/features/tabs/data/mock_tabby_repository.dart';
import 'package:tabby/features/tabs/domain/models.dart';

void main() {
  group('Canonical Acceptance Test Scenarios (AGENTS.md Section 11.3)', () {
    const currentUserId = 'user-me';

    test('Scenario 1: Basic Debt Direction', () {
      // Frienzal pays ₱500.00 for Juan's dinner
      final entries = [
        LedgerEntry(
          id: 'test-1',
          tabId: 'tab-juan',
          title: 'Dinner',
          category: ExpenseCategory.food,
          totalAmountCentavos: 50000,
          myShareCentavos: 0,
          counterpartShareCentavos: 50000,
          paidByUserId: currentUserId,
          paidByName: 'Frienzal',
          date: DateTime.now(),
        ),
      ];

      final net = MockTabbyRepository.calculateNetBalance(entries, currentUserId);
      expect(net, 50000); // +₱500.00 (Juan owes Frienzal)
    });

    test('Scenario 2: Opposite Direction Balance Offset', () {
      // Juan owes Frienzal ₱500.00
      // Later, Frienzal owes Juan ₱100.00 for fare
      final entries = [
        LedgerEntry(
          id: 'test-1',
          tabId: 'tab-juan',
          title: 'Dinner',
          category: ExpenseCategory.food,
          totalAmountCentavos: 50000,
          myShareCentavos: 0,
          counterpartShareCentavos: 50000,
          paidByUserId: currentUserId,
          paidByName: 'Frienzal',
          date: DateTime.now(),
        ),
        LedgerEntry(
          id: 'test-2',
          tabId: 'tab-juan',
          title: 'Grab Fare',
          category: ExpenseCategory.transportation,
          totalAmountCentavos: 10000,
          myShareCentavos: 10000,
          counterpartShareCentavos: 0,
          paidByUserId: 'user-juan',
          paidByName: 'Juan Dela Cruz',
          date: DateTime.now(),
        ),
      ];

      final net = MockTabbyRepository.calculateNetBalance(entries, currentUserId);
      expect(net, 40000); // +₱400.00 (Juan owes Frienzal ₱400.00 net)
    });

    test('Scenario 3: Partial Payment Ledger Tracking', () {
      // Obligation: Juan owes Frienzal ₱500.00
      // Juan submits payment of ₱200.00 with GCash receipt; confirmed
      final entries = [
        LedgerEntry(
          id: 'test-1',
          tabId: 'tab-juan',
          title: 'Dinner',
          category: ExpenseCategory.food,
          totalAmountCentavos: 50000,
          myShareCentavos: 0,
          counterpartShareCentavos: 50000,
          paidByUserId: currentUserId,
          paidByName: 'Frienzal',
          date: DateTime.now(),
        ),
        LedgerEntry(
          id: 'payment-1',
          tabId: 'tab-juan',
          title: 'Juan paid via GCash',
          category: ExpenseCategory.borrowedCash,
          totalAmountCentavos: 20000,
          myShareCentavos: 0,
          counterpartShareCentavos: 0,
          paidByUserId: 'user-juan',
          paidByName: 'Juan Dela Cruz',
          date: DateTime.now(),
          isPayment: true,
          status: TransactionStatus.settled,
        ),
      ];

      final net = MockTabbyRepository.calculateNetBalance(entries, currentUserId);
      expect(net, 30000); // +₱300.00 remaining
    });

    test('KKB Equal Split Integer Arithmetic with Odd Centavos', () {
      const oddTotalCentavos = 10001; // ₱100.01
      const myShare = oddTotalCentavos ~/ 2; // 5000
      const counterpartShare = oddTotalCentavos - myShare; // 5001

      expect(myShare + counterpartShare, oddTotalCentavos);
      expect(myShare, 5000);
      expect(counterpartShare, 5001);
    });

    test('Mascot Emotion FSM State Derivation', () {
      // 1. Zero balances -> SLEEPING
      const stateSleeping = TabbyDashboardState(
        tabs: [],
        activities: [],
        reminders: [],
      );
      expect(stateSleeping.activeEmotion, MascotEmotion.sleeping);

      // 2. User owes -> USER_OWES
      final stateUserOwes = TabbyDashboardState(
        tabs: [
          BilateralTab(
            id: 'tab-mark',
            counterpart: MockTabbyRepository.sampleFriends[2],
            netBalanceCentavos: -25000, // user owes Mark ₱250.00
            itemCount: 1,
            entries: const [],
            lastUpdated: DateTime.now(),
          ),
        ],
        activities: const [],
        reminders: const [],
      );
      expect(stateUserOwes.activeEmotion, MascotEmotion.userOwes);

      // 3. User is owed -> USER_IS_OWED
      final stateUserIsOwed = TabbyDashboardState(
        tabs: [
          BilateralTab(
            id: 'tab-juan',
            counterpart: MockTabbyRepository.sampleFriends[0],
            netBalanceCentavos: 50000, // Juan owes user ₱500.00
            itemCount: 1,
            entries: const [],
            lastUpdated: DateTime.now(),
          ),
        ],
        activities: const [],
        reminders: const [],
      );
      expect(stateUserIsOwed.activeEmotion, MascotEmotion.userIsOwed);
    });
  });
}
