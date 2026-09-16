import '../domain/models.dart';

/// In-memory repository seeded with realistic peer expenses and bilateral relationships.
/// Implements ADR-001 integer centavos and canonical balance formulas.
class MockTabbyRepository {
  static const TabbyUser currentUser = TabbyUser(
    id: 'user-me',
    displayName: 'Frienzal',
    email: 'frienzal@tabby.ph',
    phone: '+63 917 888 1234',
    avatarUrl: null,
    gcashNumber: '0917-888-1234',
    mayaNumber: '0917-888-1234',
    friendCode: 'TAB-9N6R3Q',
  );

  static final List<TabbyUser> sampleFriends = [];

  static List<BilateralTab> getInitialTabs() => const [];

  /// AGENTS.md Section 8 Canonical Balance Calculation Engine
  /// Net Balance_A = sum(Owed to A) - sum(Owed by A) - sum(Payments Received by A) + sum(Payments Made by A)
  static int calculateNetBalance(List<LedgerEntry> entries, String currentUserId) {
    int netCentavos = 0;

    for (final entry in entries) {
      if (entry.status == TransactionStatus.cancelled) continue;

      if (entry.isPayment) {
        // Payment record
        if (entry.paidByUserId == currentUserId) {
          // Current user made payment -> reduces what user owes (positive offset)
          netCentavos += entry.totalAmountCentavos;
        } else {
          // Counterpart made payment -> reduces what counterpart owes (negative offset)
          netCentavos -= entry.totalAmountCentavos;
        }
      } else {
        // Expense transaction
        if (entry.paidByUserId == currentUserId) {
          // Current user paid upfront -> counterpart owes their share
          netCentavos += entry.counterpartShareCentavos;
        } else {
          // Counterpart paid upfront -> current user owes their share
          netCentavos -= entry.myShareCentavos;
        }
      }
    }

    return netCentavos;
  }

  static List<TabbyActivity> getInitialActivities() => const [];

  static List<UpcomingReminder> getInitialReminders() => const [];
}
