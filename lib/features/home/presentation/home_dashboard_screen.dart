import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/tabby_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../shared/widgets/currency_card.dart';
import '../../../shared/widgets/tabby_mascot_widget.dart';
import '../../tabs/application/tabby_providers.dart';
import '../../tabs/domain/models.dart';
import '../../tabs/presentation/add_expense_modal.dart';

class HomeDashboardScreen extends ConsumerWidget {
  const HomeDashboardScreen({super.key});

  String _getTimeOfDayGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Magandang umaga ☀️';
    } else if (hour < 18) {
      return 'Magandang hapon ⛅';
    } else {
      return 'Good evening 🌙';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardState = ref.watch(tabbyProvider);
    final notifier = ref.read(tabbyProvider.notifier);

    return Scaffold(
      backgroundColor: TabbyColors.backgroundLight,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            // Simulated pull-to-refresh
            await Future.delayed(const Duration(milliseconds: 600));
          },
          color: TabbyColors.primaryCharcoal,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Top Bar with Greeting & Notification Bell
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getTimeOfDayGreeting(),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: TabbyColors.secondaryMuted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Frienzal 👋',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: TabbyColors.primaryCharcoal,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                      // Notification Bell
                      IconButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Walang bagong notifications! All tabs updated.'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: Stack(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: TabbyColors.surfaceWhite,
                                shape: BoxShape.circle,
                                border: Border.all(color: TabbyColors.borderGray),
                              ),
                              child: const Icon(
                                Icons.notifications_none_rounded,
                                size: 22,
                                color: TabbyColors.primaryCharcoal,
                              ),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: Container(
                                width: 9,
                                height: 9,
                                decoration: const BoxDecoration(
                                  color: TabbyColors.accentAmber,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Mascot Mood Reflection Speech Bubble
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: TabbyMascotWidget(
                    emotion: dashboardState.activeEmotion,
                    customMessage: dashboardState.mascotMessage,
                    size: 60,
                    onTap: () {
                      notifier.setTemporaryEmotion(
                        MascotEmotion.celebrating,
                        message: 'Meow! Keep tabs, settle up! 🐾',
                        durationSeconds: 3,
                      );
                    },
                  ),
                ),
              ),

              // Balances Overview (You Owe / You're Owed)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      CurrencyCard(
                        title: 'YOU OWE',
                        centavos: dashboardState.youOweCentavos,
                        subtitle: dashboardState.youOweCentavos > 0
                            ? 'Active tabs to settle'
                            : 'All clear! 🎉',
                        isDebt: true,
                        icon: Icons.arrow_outward_rounded,
                        onTap: () => context.go('/tabs'),
                      ),
                      const SizedBox(width: 12),
                      CurrencyCard(
                        title: "YOU'RE OWED",
                        centavos: dashboardState.youAreOwedCentavos,
                        subtitle: dashboardState.youAreOwedCentavos > 0
                            ? 'Across ${dashboardState.tabs.where((t) => t.netBalanceCentavos > 0).length} tabs'
                            : 'Zero pending credits',
                        isDebt: false,
                        icon: Icons.arrow_downward_rounded,
                        onTap: () => context.go('/tabs'),
                      ),
                    ],
                  ),
                ),
              ),

              // Net Balance Highlight Banner
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: dashboardState.netBalanceCentavos >= 0
                          ? TabbyColors.successLight
                          : TabbyColors.debtLight,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: dashboardState.netBalanceCentavos >= 0
                            ? TabbyColors.successGreen.withValues(alpha: 0.3)
                            : TabbyColors.debtRed.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              dashboardState.netBalanceCentavos >= 0
                                  ? Icons.account_balance_wallet_outlined
                                  : Icons.receipt_long_outlined,
                              size: 18,
                              color: dashboardState.netBalanceCentavos >= 0
                                  ? TabbyColors.successGreen
                                  : TabbyColors.debtRed,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              dashboardState.netBalanceCentavos >= 0
                                  ? 'Net Position (They owe you overall)'
                                  : 'Net Position (You owe overall)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: dashboardState.netBalanceCentavos >= 0
                                    ? TabbyColors.successGreen
                                    : TabbyColors.debtRed,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          CurrencyFormatter.formatCentavos(
                            dashboardState.netBalanceCentavos,
                            showSign: true,
                          ),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: dashboardState.netBalanceCentavos >= 0
                                ? TabbyColors.successGreen
                                : TabbyColors.debtRed,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Upcoming Dues & Reminders Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Upcoming & Reminders',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: TabbyColors.primaryCharcoal,
                        ),
                      ),
                      Text(
                        '${dashboardState.reminders.length} items',
                        style: const TextStyle(
                          fontSize: 12,
                          color: TabbyColors.secondaryMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Upcoming Items List
              if (dashboardState.reminders.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Text('😴', style: TextStyle(fontSize: 20)),
                            SizedBox(width: 12),
                            Text(
                              'Walang pending dues! All caught up.',
                              style: TextStyle(
                                fontSize: 13,
                                color: TabbyColors.secondaryMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final reminder = dashboardState.reminders[index];
                      final isOverdue = reminder.dueDate.isBefore(DateTime.now());

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: reminder.isIWhoOwe
                                      ? TabbyColors.debtLight
                                      : TabbyColors.pendingLight,
                                  child: Text(
                                    reminder.friendName.substring(0, 1).toUpperCase(),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: reminder.isIWhoOwe
                                          ? TabbyColors.debtRed
                                          : TabbyColors.accentAmberDark,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        reminder.friendName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: TabbyColors.primaryCharcoal,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        reminder.description,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: TabbyColors.secondaryMuted,
                                        ),
                                      ),
                                      if (isOverdue) ...[
                                        const SizedBox(height: 2),
                                        const Text(
                                          '⚠️ Overdue commitment',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: TabbyColors.debtRed,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      CurrencyFormatter.formatCentavos(reminder.amountCentavos),
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: reminder.isIWhoOwe
                                            ? TabbyColors.debtRed
                                            : TabbyColors.primaryCharcoal,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    if (reminder.isIWhoOwe)
                                      InkWell(
                                        onTap: () => context.go('/tabs/${reminder.tabId}'),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: TabbyColors.primaryCharcoal,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Text(
                                            'Bayad na',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: TabbyColors.surfaceWhite,
                                            ),
                                          ),
                                        ),
                                      )
                                    else
                                      InkWell(
                                        onTap: () {
                                          notifier.sendGentleNudge(
                                            tabId: reminder.tabId,
                                            friendName: reminder.friendName,
                                            amountCentavos: reminder.amountCentavos,
                                          );
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                '🐾 Gentle Nudge sent to ${reminder.friendName}!',
                                              ),
                                              backgroundColor: TabbyColors.primaryCharcoal,
                                              duration: const Duration(seconds: 2),
                                            ),
                                          );
                                        },
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: TabbyColors.accentAmber,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Text(
                                            'Remind 🐾',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: TabbyColors.primaryCharcoal,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: dashboardState.reminders.length,
                  ),
                ),

              // Recent Activity Feed Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Recent Activity',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: TabbyColors.primaryCharcoal,
                        ),
                      ),
                      Text(
                        '${dashboardState.activities.length} logs',
                        style: const TextStyle(
                          fontSize: 12,
                          color: TabbyColors.secondaryMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Recent Activity Items
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final act = dashboardState.activities[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: TabbyColors.surfaceWhite,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: TabbyColors.borderGray),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: TabbyColors.backgroundLight,
                                shape: BoxShape.circle,
                                border: Border.all(color: TabbyColors.borderGray),
                              ),
                              child: Center(
                                child: Text(act.icon, style: const TextStyle(fontSize: 18)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  RichText(
                                    text: TextSpan(
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: TabbyColors.primaryCharcoal,
                                        fontFamily: 'Inter',
                                      ),
                                      children: [
                                        TextSpan(
                                          text: act.actorName,
                                          style: const TextStyle(fontWeight: FontWeight.w700),
                                        ),
                                        const TextSpan(text: ' '),
                                        TextSpan(text: act.description),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatTimestamp(act.timestamp),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: TabbyColors.secondaryMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (act.amountCentavos > 0)
                              Text(
                                CurrencyFormatter.formatCentavos(act.amountCentavos),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: TabbyColors.primaryCharcoal,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: dashboardState.activities.length,
                ),
              ),

              const SliverToBoxAdapter(
                child: SizedBox(height: 90),
              ),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          AddExpenseModal.show(context);
        },
        backgroundColor: TabbyColors.primaryCharcoal,
        foregroundColor: TabbyColors.surfaceWhite,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.add_rounded, size: 22),
        label: const Text(
          'Log Expense',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }
}
