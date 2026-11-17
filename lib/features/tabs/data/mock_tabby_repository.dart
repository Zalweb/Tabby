import '../domain/models.dart';
import '../domain/share_allocation.dart' as allocation;

/// In-memory repository seeded with realistic peer expenses and bilateral relationships.
/// Implements ADR-001 integer centavos and canonical balance formulas.
class MockTabbyRepository {
  /// A server row is authoritative for a known ID, including confirmation state.
  static List<LedgerEntry> mergeServerEntries(
      List<LedgerEntry> server, Iterable<LedgerEntry> local) {
    final ids = server.map((entry) => entry.id).toSet();
    return deduplicateLedgerEntries(
        [...server, ...local.where((entry) => !ids.contains(entry.id))]);
  }

  static List<BilateralTab> applyOperationResult(
    List<BilateralTab> tabs, {
    required String localEntryId,
    required String remoteTabId,
    required String remoteEntryId,
    required String currentUserId,
  }) =>
      tabs.map((tab) {
        if (!tab.entries.any((entry) => entry.id == localEntryId)) return tab;
        final entries = deduplicateLedgerEntries(tab.entries
            .map((entry) => entry.copyWith(
                tabId: remoteTabId,
                id: entry.id == localEntryId ? remoteEntryId : entry.id))
            .toList());
        return tab.copyWith(
            id: remoteTabId,
            isLocalOnly: false,
            entries: entries,
            itemCount: entries.length,
            netBalanceCentavos: calculateNetBalance(entries, currentUserId));
      }).toList();

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

  static List<BilateralTab> getInitialTabs() => const [];

  /// AGENTS.md Section 8 Canonical Balance Calculation Engine
  /// Net Balance_A = sum(Owed to A) - sum(Owed by A) - sum(Payments Received by A) + sum(Payments Made by A)
  static int calculateNetBalance(
      List<LedgerEntry> entries, String currentUserId) {
    int netCentavos = 0;

    for (final entry in entries) {
      if (entry.status == TransactionStatus.cancelled ||
          entry.status == TransactionStatus.disputed) {
        continue;
      }

      if (entry.isPayment) {
        if (entry.status != TransactionStatus.settled) continue;
        final payer = entry.payer ??
            PartyRef(kind: PartyKind.user, id: entry.paidByUserId);
        if (payer.kind == PartyKind.user && payer.id == currentUserId) {
          // Current user made payment -> reduces what user owes (positive offset)
          netCentavos += entry.totalAmountCentavos;
        } else if (entry.recipient?.kind == PartyKind.user &&
            entry.recipient?.id == currentUserId) {
          // Counterpart made payment -> reduces what counterpart owes (negative offset)
          netCentavos -= entry.totalAmountCentavos;
        }
        // An uninvolved member, or an ambiguous legacy recipient, has no
        // incoming payment. Refresh legacy rows to obtain explicit parties.
      } else {
        // Expense transaction
        if (entry.participants.isNotEmpty) {
          final ownShare = entry.participants
                  .where((p) => p.userId == currentUserId)
                  .firstOrNull
                  ?.shareAmountCentavos ??
              0;
          netCentavos += entry.paidByUserId == currentUserId
              ? entry.totalAmountCentavos - ownShare
              : -ownShare;
        } else if (entry.paidByUserId == currentUserId) {
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

  /// Allocates every centavo exactly once using a stable participant order.
  /// Earlier participants receive the remainder centavos.
  static Map<String, int> allocateEqualShares(
    int totalAmountCentavos,
    Iterable<String> participantIds,
  ) => allocation.allocateEqualShares(totalAmountCentavos, participantIds);

  static bool _isServerUuid(String id) {
    if (id.length != 36) return false;
    return RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
        .hasMatch(id);
  }

  /// Reconcile only stable transaction identities; similarity is not identity.
  static List<LedgerEntry> deduplicateLedgerEntries(List<LedgerEntry> list) {
    final result = <LedgerEntry>[];

    for (final candidate in list) {
      final duplicateIndex = result.indexWhere((existing) {
        // 1. Exact ID match (unconditional)
        if (candidate.id.isNotEmpty &&
            existing.id.isNotEmpty &&
            candidate.id == existing.id) {
          return true;
        }

        // A UUID-looking suffix is not an explicit operation-to-server mapping.
        // Preserve both records until the executor supplies the actual mapping.
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
            dueDate: preferred.dueDate ?? existing.dueDate ?? candidate.dueDate,
            note: preferred.note ?? existing.note ?? candidate.note,
          );
        }
      }
    }

    result.sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  /// Deduplicates bilateral tabs by immutable tab or counterpart ID,
  /// merging all entries cleanly without duplicates.
  static bool sameRelationship(BilateralTab a, BilateralTab b) {
    if (a.isGroupTab || b.isGroupTab) {
      return a.isGroupTab && b.isGroupTab && a.id.isNotEmpty && a.id == b.id;
    }
    return (a.id.isNotEmpty && a.id == b.id) ||
        (a.counterpart.id.isNotEmpty &&
            a.counterpart.id == b.counterpart.id &&
            a.isTabOnlyParticipant == b.isTabOnlyParticipant);
  }

  static List<BilateralTab> deduplicateTabs(
    List<BilateralTab> tabs, {
    String? currentUserId,
  }) {
    final result = <BilateralTab>[];

    for (final tab in tabs) {
      final matchIndex =
          result.indexWhere((existing) => sameRelationship(tab, existing));

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
        final canonicalId = (!tab.isLocalOnly && existing.isLocalOnly) ||
                (isTabServer && !isExistingServer)
            ? tab.id
            : existing.id;

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
          isLocalOnly: existing.isLocalOnly && tab.isLocalOnly,
          counterpart: counterpart,
          members: existing.members.isNotEmpty ? existing.members : tab.members,
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
