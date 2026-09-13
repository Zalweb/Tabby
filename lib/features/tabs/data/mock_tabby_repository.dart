import '../domain/models.dart';

/// In-memory repository seeded with realistic Filipino peer expenses and bilateral relationships.
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
  );

  static final List<TabbyUser> sampleFriends = [
    const TabbyUser(
      id: 'user-juan',
      displayName: 'Juan Dela Cruz',
      email: 'juan@gmail.com',
      phone: '+63 917 111 2233',
      gcashNumber: '0917-111-2233',
      mayaNumber: '0917-111-2233',
    ),
    const TabbyUser(
      id: 'user-ana',
      displayName: 'Ana Santos',
      email: 'ana@gmail.com',
      phone: '+63 918 222 3344',
      gcashNumber: '0918-222-3344',
      mayaNumber: '0918-222-3344',
    ),
    const TabbyUser(
      id: 'user-mark',
      displayName: 'Mark Villanueva',
      email: 'mark@gmail.com',
      phone: '+63 919 333 4455',
      gcashNumber: '0919-333-4455',
      mayaNumber: '0919-333-4455',
    ),
    const TabbyUser(
      id: 'user-barkada',
      displayName: 'Barkada Weekend Outing',
      email: 'barkada@tabby.ph',
      phone: '+63 920 444 5566',
      gcashNumber: '0920-444-5566',
    ),
  ];

  static List<BilateralTab> getInitialTabs() {
    final now = DateTime.now();

    // 1. Juan's Tab: Frienzal paid dinner (₱1,000 total, ₱500 Juan's share), fare (₱100), Juan paid coffee (₱100)
    // Net: +₱500.00
    final juanEntries = [
      LedgerEntry(
        id: 'entry-juan-1',
        tabId: 'tab-juan',
        title: 'BGC Dinner & Sisig',
        category: ExpenseCategory.food,
        totalAmountCentavos: 100000,
        myShareCentavos: 50000,
        counterpartShareCentavos: 50000,
        paidByUserId: currentUser.id,
        paidByName: currentUser.displayName,
        date: now.subtract(const Duration(days: 2)),
        dueDate: now.add(const Duration(days: 3)),
        status: TransactionStatus.acknowledged,
      ),
      LedgerEntry(
        id: 'entry-juan-2',
        tabId: 'tab-juan',
        title: 'Grab Car to Poblacion',
        category: ExpenseCategory.transportation,
        totalAmountCentavos: 20000,
        myShareCentavos: 10000,
        counterpartShareCentavos: 10000,
        paidByUserId: currentUser.id,
        paidByName: currentUser.displayName,
        date: now.subtract(const Duration(days: 1)),
        status: TransactionStatus.acknowledged,
      ),
      LedgerEntry(
        id: 'entry-juan-3',
        tabId: 'tab-juan',
        title: 'Iced Spanish Latte',
        category: ExpenseCategory.food,
        totalAmountCentavos: 20000,
        myShareCentavos: 10000,
        counterpartShareCentavos: 10000,
        paidByUserId: 'user-juan',
        paidByName: 'Juan Dela Cruz',
        date: now.subtract(const Duration(hours: 12)),
        status: TransactionStatus.acknowledged,
      ),
    ];

    // 2. Ana's Tab: Milk tea & pastries (₱750)
    final anaEntries = [
      LedgerEntry(
        id: 'entry-ana-1',
        tabId: 'tab-ana',
        title: 'Milk Tea & Pastries',
        category: ExpenseCategory.food,
        totalAmountCentavos: 75000,
        myShareCentavos: 0,
        counterpartShareCentavos: 75000,
        paidByUserId: currentUser.id,
        paidByName: currentUser.displayName,
        date: now.subtract(const Duration(days: 3)),
        dueDate: now.subtract(const Duration(days: 1)), // overdue example
        status: TransactionStatus.acknowledged,
      ),
    ];

    // 3. Mark's Tab: Mark paid groceries (₱500 total, Frienzal's share ₱250). Frienzal owes Mark ₱250.
    final markEntries = [
      LedgerEntry(
        id: 'entry-mark-1',
        tabId: 'tab-mark',
        title: 'Supermarket Run',
        category: ExpenseCategory.groceries,
        totalAmountCentavos: 50000,
        myShareCentavos: 25000,
        counterpartShareCentavos: 25000,
        paidByUserId: 'user-mark',
        paidByName: 'Mark Villanueva',
        date: now.subtract(const Duration(days: 4)),
        dueDate: now.add(const Duration(days: 2)),
        status: TransactionStatus.acknowledged,
      ),
    ];

    // 4. Barkada Tab: Tagaytay trip cottage rental (+₱2,000)
    final barkadaEntries = [
      LedgerEntry(
        id: 'entry-barkada-1',
        tabId: 'tab-barkada',
        title: 'Tagaytay Cottage & Meals',
        category: ExpenseCategory.other,
        totalAmountCentavos: 400000,
        myShareCentavos: 200000,
        counterpartShareCentavos: 200000,
        paidByUserId: currentUser.id,
        paidByName: currentUser.displayName,
        date: now.subtract(const Duration(days: 5)),
        status: TransactionStatus.acknowledged,
      ),
    ];

    return [
      BilateralTab(
        id: 'tab-juan',
        counterpart: sampleFriends[0],
        netBalanceCentavos: calculateNetBalance(juanEntries, currentUser.id),
        itemCount: juanEntries.length,
        entries: juanEntries,
        lastUpdated: now.subtract(const Duration(hours: 12)),
      ),
      BilateralTab(
        id: 'tab-ana',
        counterpart: sampleFriends[1],
        netBalanceCentavos: calculateNetBalance(anaEntries, currentUser.id),
        itemCount: anaEntries.length,
        entries: anaEntries,
        lastUpdated: now.subtract(const Duration(days: 3)),
      ),
      BilateralTab(
        id: 'tab-mark',
        counterpart: sampleFriends[2],
        netBalanceCentavos: calculateNetBalance(markEntries, currentUser.id),
        itemCount: markEntries.length,
        entries: markEntries,
        lastUpdated: now.subtract(const Duration(days: 4)),
      ),
      BilateralTab(
        id: 'tab-barkada',
        counterpart: sampleFriends[3],
        netBalanceCentavos: calculateNetBalance(barkadaEntries, currentUser.id),
        itemCount: barkadaEntries.length,
        entries: barkadaEntries,
        lastUpdated: now.subtract(const Duration(days: 5)),
        isGroupTab: true,
        groupName: 'Barkada Weekend Outing',
      ),
    ];
  }

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

  static List<TabbyActivity> getInitialActivities() {
    final now = DateTime.now();
    return [
      TabbyActivity(
        id: 'act-1',
        actorName: 'Juan Dela Cruz',
        description: 'acknowledged BGC Dinner & Sisig (₱500.00)',
        amountCentavos: 50000,
        timestamp: now.subtract(const Duration(hours: 2)),
        icon: '✅',
      ),
      TabbyActivity(
        id: 'act-2',
        actorName: 'Frienzal',
        description: 'logged Grab Car to Poblacion with Juan',
        amountCentavos: 10000,
        timestamp: now.subtract(const Duration(days: 1)),
        icon: '🚗',
      ),
      TabbyActivity(
        id: 'act-3',
        actorName: 'Ana Santos',
        description: 'Milk Tea & Pastries pending settlement',
        amountCentavos: 75000,
        timestamp: now.subtract(const Duration(days: 2)),
        icon: '🧋',
      ),
      TabbyActivity(
        id: 'act-4',
        actorName: 'Mark Villanueva',
        description: 'logged Supermarket Run (You owe ₱250.00)',
        amountCentavos: 25000,
        timestamp: now.subtract(const Duration(days: 4)),
        icon: '🛒',
      ),
    ];
  }

  static List<UpcomingReminder> getInitialReminders() {
    final now = DateTime.now();
    return [
      UpcomingReminder(
        id: 'rem-1',
        tabId: 'tab-ana',
        friendName: 'Ana Santos',
        description: 'Milk Tea & Pastries',
        amountCentavos: 75000,
        dueDate: now.subtract(const Duration(days: 1)),
        isIWhoOwe: false, // Ana owes me
      ),
      UpcomingReminder(
        id: 'rem-2',
        tabId: 'tab-mark',
        friendName: 'Mark Villanueva',
        description: 'Supermarket Run',
        amountCentavos: 25000,
        dueDate: now.add(const Duration(days: 2)),
        isIWhoOwe: true, // I owe Mark
      ),
      UpcomingReminder(
        id: 'rem-3',
        tabId: 'tab-juan',
        friendName: 'Juan Dela Cruz',
        description: 'BGC Dinner & Sisig',
        amountCentavos: 50000,
        dueDate: now.add(const Duration(days: 3)),
        isIWhoOwe: false, // Juan owes me
      ),
    ];
  }
}
