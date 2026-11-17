import '../../tabs/application/tabby_state.dart';
import '../../tabs/domain/models.dart';
import 'activity_period.dart';

/// Read-only personal summary. No inferred payments or cross-party netting.
class HomeDashboardSummary {
  HomeDashboardSummary({
    required TabbyDashboardState state,
    required ActivityPeriod period,
    required DateTime now,
    required String viewerId,
  }) {
    totalTabs = state.tabs.length;
    for (final tab in state.tabs) {
      final own = TabbyDashboardState(
        viewerUserId: viewerId,
        tabs: [tab],
        activities: const [],
        reminders: const [],
      );
      if (own.youOweCentavos > 0 ||
          own.youAreOwedCentavos > 0 ||
          own.hasIncompleteGroupBalances) {
        activeTabs++;
      }
    }
    final seen = <String>{};
    for (final entry in state.tabs.expand((tab) => tab.entries)) {
      if (!entry.isPayment ||
          entry.status != TransactionStatus.settled ||
          !period.includes(entry.date, now) ||
          !seen.add(entry.id)) {
        continue;
      }
      final payer = entry.payer, recipient = entry.recipient;
      if (payer == null || recipient == null) {
        hasUnattributedPayments = true;
        continue;
      }
      if (payer.kind == PartyKind.user && payer.id == viewerId) {
        paidCentavos += entry.totalAmountCentavos;
      }
      if (recipient.kind == PartyKind.user && recipient.id == viewerId) {
        receivedCentavos += entry.totalAmountCentavos;
      }
    }
  }
  late final int totalTabs;
  int activeTabs = 0;
  int get clearTabs => totalTabs - activeTabs;
  double get clearance => totalTabs == 0 ? 0 : clearTabs / totalTabs;
  int receivedCentavos = 0, paidCentavos = 0;
  bool hasUnattributedPayments = false;
}
