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

  static bool _isServerUuid(String id) {
    if (id.length != 36) return false;
    return RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
        .hasMatch(id);
  }

  static String _normalizeTitle(String title) {
    var s = title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (s.startsWith('settled ')) {
      s = s.substring(8).trim();
    }
    return s;
  }

  /// Deduplicates ledger entries by exact ID and semantic transaction signature,
  /// prioritizing server-confirmed UUIDs over optimistic/temporary local IDs.
  static List<LedgerEntry> deduplicateLedgerEntries(List<LedgerEntry> list) {
    final result = <LedgerEntry>[];

    for (final candidate in list) {
      final normCandidateTitle = _normalizeTitle(candidate.title);

      final duplicateIndex = result.indexWhere((existing) {
        // 1. Exact ID match
        if (candidate.id.isNotEmpty &&
            existing.id.isNotEmpty &&
            candidate.id == existing.id) {
          return true;
        }

        // 2. Financial transaction match
        if (candidate.totalAmountCentavos == existing.totalAmountCentavos &&
            candidate.isPayment == existing.isPayment) {
          final secondsDiff =
              candidate.date.difference(existing.date).abs().inSeconds;

          // Transactions within 24 hours (86,400 seconds)
          if (secondsDiff < 86400) {
            if (candidate.isPayment) {
              if (candidate.paymentMethod == existing.paymentMethod ||
                  candidate.paymentMethod == null ||
                  existing.paymentMethod == null) {
                return true;
              }
            } else {
              final normExistingTitle = _normalizeTitle(existing.title);
              final titlesMatch = normCandidateTitle == normExistingTitle ||
                  (normCandidateTitle.isNotEmpty &&
                      normExistingTitle.isNotEmpty &&
                      (normCandidateTitle.contains(normExistingTitle) ||
                          normExistingTitle.contains(normCandidateTitle)));
              final categoriesMatch = candidate.category == existing.category;

              if (titlesMatch) {
                return true;
              } else if (categoriesMatch && secondsDiff < 1800) {
                return true;
              }
            }
          }
        }

        return false;
      });

      if (duplicateIndex == -1) {
        result.add(candidate);
      } else {
        final existing = result[duplicateIndex];
        final isCandidateServer = _isServerUuid(candidate.id);
        final isExistingServer = _isServerUuid(existing.id);

        if (isCandidateServer && !isExistingServer) {
          result[duplicateIndex] = candidate.copyWith(
            receiptUrl: candidate.receiptUrl ?? existing.receiptUrl,
            dueDate: candidate.dueDate ?? existing.dueDate,
            note: candidate.note ?? existing.note,
          );
        } else if (!isCandidateServer && isExistingServer) {
          result[duplicateIndex] = existing.copyWith(
            receiptUrl: existing.receiptUrl ?? candidate.receiptUrl,
            dueDate: existing.dueDate ?? candidate.dueDate,
            note: existing.note ?? candidate.note,
          );
        } else {
          final preferred =
              candidate.date.isAfter(existing.date) ? candidate : existing;
          result[duplicateIndex] = preferred.copyWith(
            receiptUrl: preferred.receiptUrl ??
                existing.receiptUrl ??
                candidate.receiptUrl,
            dueDate: preferred.dueDate ??
                existing.dueDate ??
                candidate.dueDate,
            note: preferred.note ?? existing.note ?? candidate.note,
          );
        }
      }
    }

    result.sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  /// Deduplicates bilateral tabs by ID, counterpart ID, or counterpart name,
  /// merging all entries cleanly without duplicates.
  static List<BilateralTab> deduplicateTabs(
    List<BilateralTab> tabs, {
    String? currentUserId,
  }) {
    final result = <BilateralTab>[];

    for (final tab in tabs) {
      final matchIndex = result.indexWhere((existing) {
        // Group tab match
        if (tab.isGroupTab || existing.isGroupTab) {
          if (tab.isGroupTab && existing.isGroupTab) {
            if (tab.id.isNotEmpty &&
                existing.id.isNotEmpty &&
                tab.id == existing.id) {
              return true;
            }
            final tabGrpName = (tab.groupName ?? tab.counterpart.displayName)
                .trim()
                .toLowerCase();
            final exGrpName =
                (existing.groupName ?? existing.counterpart.displayName)
                    .trim()
                    .toLowerCase();
            if (tabGrpName.isNotEmpty && tabGrpName == exGrpName) {
              return true;
            }
          }
          return false;
        }

        // Bilateral individual tab match
        if (tab.id.isNotEmpty &&
            existing.id.isNotEmpty &&
            tab.id == existing.id) {
          return true;
        }
        if (tab.counterpart.id.isNotEmpty &&
            existing.counterpart.id.isNotEmpty &&
            tab.counterpart.id == existing.counterpart.id) {
          return true;
        }
        final tabName = tab.counterpart.displayName.trim().toLowerCase();
        final exName = existing.counterpart.displayName.trim().toLowerCase();
        if (tabName.isNotEmpty && tabName == exName) {
          return true;
        }

        return false;
      });

      if (matchIndex == -1) {
        final cleanEntries = deduplicateLedgerEntries(tab.entries);
        final effectiveBalance = currentUserId != null
            ? calculateNetBalance(cleanEntries, currentUserId)
            : tab.netBalanceCentavos;
        result.add(tab.copyWith(
          entries: cleanEntries,
          itemCount: cleanEntries.length,
          netBalanceCentavos: effectiveBalance,
        ));
      } else {
        final existing = result[matchIndex];
        final mergedEntries = deduplicateLedgerEntries([
          ...existing.entries,
          ...tab.entries,
        ]);
        final effectiveBalance = currentUserId != null
            ? calculateNetBalance(mergedEntries, currentUserId)
            : existing.netBalanceCentavos;

        final isTabServer = _isServerUuid(tab.id);
        final isExistingServer = _isServerUuid(existing.id);
        final canonicalId =
            (isTabServer && !isExistingServer) ? tab.id : existing.id;

        final counterpart = TabbyUser(
          id: existing.counterpart.id.isNotEmpty
              ? existing.counterpart.id
              : tab.counterpart.id,
          displayName: existing.counterpart.displayName.isNotEmpty
              ? existing.counterpart.displayName
              : tab.counterpart.displayName,
          email: existing.counterpart.email.isNotEmpty
              ? existing.counterpart.email
              : tab.counterpart.email,
          phone: existing.counterpart.phone.isNotEmpty
              ? existing.counterpart.phone
              : tab.counterpart.phone,
          avatarUrl:
              existing.counterpart.avatarUrl ?? tab.counterpart.avatarUrl,
          gcashNumber: existing.counterpart.gcashNumber.isNotEmpty
              ? existing.counterpart.gcashNumber
              : tab.counterpart.gcashNumber,
          mayaNumber: existing.counterpart.mayaNumber.isNotEmpty
              ? existing.counterpart.mayaNumber
              : tab.counterpart.mayaNumber,
          qrCodeUrl:
              existing.counterpart.qrCodeUrl ?? tab.counterpart.qrCodeUrl,
          friendCode:
              existing.counterpart.friendCode ?? tab.counterpart.friendCode,
        );

        final latestDate = tab.lastUpdated.isAfter(existing.lastUpdated)
            ? tab.lastUpdated
            : existing.lastUpdated;

        result[matchIndex] = existing.copyWith(
          id: canonicalId,
          counterpart: counterpart,
          entries: mergedEntries,
          itemCount: mergedEntries.length,
          netBalanceCentavos: effectiveBalance,
          lastUpdated: latestDate,
          isTabOnlyParticipant:
              existing.isTabOnlyParticipant && tab.isTabOnlyParticipant,
        );
      }
    }

    return result;
  }

  static List<TabbyActivity> getInitialActivities() => const [];

  static List<UpcomingReminder> getInitialReminders() => const [];
}
