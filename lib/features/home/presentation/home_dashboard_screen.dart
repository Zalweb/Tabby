import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/tabby_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../shared/widgets/currency_card.dart';
import '../../../shared/widgets/notification_center_sheet.dart';
import '../../../shared/widgets/tabby_mascot_widget.dart';
import '../../tabs/application/tabby_providers.dart';
import '../../tabs/domain/models.dart';
import '../../tabs/presentation/add_expense_modal.dart';

class HomeDashboardScreen extends ConsumerStatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  ConsumerState<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends ConsumerState<HomeDashboardScreen> {
  String _selectedFilter = 'Monthly';

  @override
  Widget build(BuildContext context) {
    final dashboardState = ref.watch(tabbyProvider);
    final notifier = ref.read(tabbyProvider.notifier);
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: TabbyColors.brandEmerald,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await Future.wait([
              ref.read(tabbyProvider.notifier).refreshTabs(),
              ref.read(currentUserProvider.notifier).loadFromSupabase(),
            ]);
          },
          color: TabbyColors.brandEmerald,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // 1. Top Header & KPI Hero Section (Figma home_7033_352)
              SliverToBoxAdapter(
                child: Container(
                  color: TabbyColors.brandEmerald,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Row: Greeting, Name, Notification Bell
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Hi, Welcome Back',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: TabbyColors.brandDarkTeal,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  currentUser.displayName.split(' ').first,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: TabbyColors.brandDarkTeal,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Circular White Notification Button
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: TabbyColors.surfaceWhite,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: IconButton(
                              icon: const Icon(
                                Icons.notifications_none_rounded,
                                color: TabbyColors.brandDarkTeal,
                                size: 22,
                              ),
                              onPressed: () => NotificationCenterSheet.show(context),
                              tooltip: 'Notifications',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // KPI Row: Total Balance vs Total Expense (Dual column)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left Column: Total Balance (You're Owed)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 20,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        color: TabbyColors.surfaceWhite.withValues(alpha: 0.25),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: const Icon(
                                        Icons.north_east_rounded,
                                        size: 14,
                                        color: TabbyColors.brandDarkTeal,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Expanded(
                                      child: Text(
                                        'Total Balance',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: TabbyColors.brandDarkTeal,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    CurrencyFormatter.formatCentavos(dashboardState.youAreOwedCentavos),
                                    style: const TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w900,
                                      color: TabbyColors.brandDarkTeal,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Thin Vertical Divider
                          Container(
                            height: 48,
                            width: 1.2,
                            color: TabbyColors.brandDarkTeal.withValues(alpha: 0.2),
                            margin: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          // Right Column: Total Expense (You Owe)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 20,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        color: TabbyColors.surfaceWhite.withValues(alpha: 0.25),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: const Icon(
                                        Icons.south_west_rounded,
                                        size: 14,
                                        color: TabbyColors.accentBlue,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Expanded(
                                      child: Text(
                                        'Total Expense',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: TabbyColors.brandDarkTeal,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '-${CurrencyFormatter.formatCentavos(dashboardState.youOweCentavos)}',
                                    style: const TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w900,
                                      color: TabbyColors.accentBlue,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // FinWise Progress Bar Capsule (Figma home_7033_352 & AST 7342:2869 / 7342:2871)
                      Container(
                        height: 36,
                        decoration: BoxDecoration(
                          color: TabbyColors.brandDeepForest,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 18),
                              child: Text(
                                dashboardState.tabs.isEmpty ? '0%' : '100%',
                                style: const TextStyle(
                                  color: TabbyColors.bgCanvas,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Container(
                              height: 30,
                              margin: const EdgeInsets.only(right: 3),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: TabbyColors.bgCanvas,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Center(
                                child: Text(
                                  CurrencyFormatter.formatCentavos(dashboardState.netBalanceCentavos.abs()),
                                  style: const TextStyle(
                                    color: TabbyColors.brandDeepForest,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // FinWise Status Check Line
                      Row(
                        children: [
                          const Icon(
                            Icons.check_box_outlined,
                            size: 16,
                            color: TabbyColors.brandDarkTeal,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              dashboardState.tabs.isEmpty
                                  ? 'All tabs cleared. Ready for your first expense.'
                                  : 'Active tabs in progress. Keep tabs and settle up.',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: TabbyColors.brandDarkTeal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // 2. Main Body with Top Rounded Sheet Geometry (FinWise Canvas)
              SliverToBoxAdapter(
                child: Container(
                  decoration: const BoxDecoration(
                    color: TabbyColors.bgCanvas,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // FinWise Savings / Quick KPI Card (home_7033_352)
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: TabbyColors.brandEmerald,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: TabbyColors.brandEmerald.withValues(alpha: 0.25),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            // Left: Circular Progress Ring with Mascot Indicator
                            Expanded(
                              flex: 4,
                              child: Column(
                                children: [
                                  Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: TabbyColors.surfaceWhite,
                                        width: 3.5,
                                      ),
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        Icons.receipt_long_rounded,
                                        color: TabbyColors.surfaceWhite,
                                        size: 28,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Active Tabs',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: TabbyColors.brandDarkTeal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Vertical Divider
                            Container(
                              height: 60,
                              width: 1,
                              color: TabbyColors.surfaceWhite.withValues(alpha: 0.4),
                              margin: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            // Right: Stats breakdown
                            Expanded(
                              flex: 6,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.arrow_upward_rounded, size: 16, color: TabbyColors.brandDarkTeal),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Total Owed to You',
                                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: TabbyColors.brandDarkTeal),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                CurrencyFormatter.formatCentavos(dashboardState.youAreOwedCentavos),
                                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: TabbyColors.brandDarkTeal),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(color: Colors.white24, height: 16),
                                  Row(
                                    children: [
                                      const Icon(Icons.arrow_downward_rounded, size: 16, color: TabbyColors.accentBlue),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Total You Owe',
                                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: TabbyColors.brandDarkTeal),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                '-${CurrencyFormatter.formatCentavos(dashboardState.youOweCentavos)}',
                                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: TabbyColors.accentBlue),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Segmented Filter Pills (Daily, Weekly, Monthly) matching Figma Switch-2
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: TabbyColors.brandMintAccent,
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: Row(
                          children: ['Daily', 'Weekly', 'Monthly'].map((filter) {
                            final isSelected = _selectedFilter == filter;
                            return Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _selectedFilter = filter),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected ? TabbyColors.brandEmerald : Colors.transparent,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Center(
                                    child: Text(
                                      filter,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: isSelected ? TabbyColors.surfaceWhite : TabbyColors.brandDarkTeal,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Dual Currency Cards (YOU OWE / YOU'RE OWED)
                      Row(
                        children: [
                          Expanded(
                            child: CurrencyCard(
                              title: 'YOU OWE',
                              centavos: dashboardState.youOweCentavos,
                              subtitle: dashboardState.youOweCentavos > 0
                                  ? 'Active tabs to settle'
                                  : 'All clear',
                              isDebt: true,
                              icon: Icons.arrow_outward_rounded,
                              onTap: () => context.go('/tabs'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: CurrencyCard(
                              title: "YOU'RE OWED",
                              centavos: dashboardState.youAreOwedCentavos,
                              subtitle: dashboardState.youAreOwedCentavos > 0
                                  ? 'Across active tabs'
                                  : 'Zero pending credits',
                              isDebt: false,
                              icon: Icons.arrow_downward_rounded,
                              onTap: () => context.go('/tabs'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Tabby Mascot Companion Speech Card
                      TabbyMascotWidget(
                        emotion: dashboardState.activeEmotion,
                        customMessage: dashboardState.mascotMessage,
                        size: 56,
                        onTap: () {
                          notifier.setTemporaryEmotion(
                            MascotEmotion.celebrating,
                            message: 'All tabs in order. Keep tabs and settle up!',
                            durationSeconds: 3,
                          );
                        },
                      ),
                      const SizedBox(height: 24),

                      // Upcoming & Reminders Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Text(
                              'Upcoming & Reminders',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: TabbyColors.brandDarkTeal,
                                letterSpacing: -0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${dashboardState.reminders.length} items',
                            style: const TextStyle(
                              fontSize: 12,
                              color: TabbyColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Upcoming Reminders List
                      if (dashboardState.reminders.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: TabbyColors.surfaceWhite,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: TabbyColors.borderMint),
                          ),
                          child: const Center(
                            child: Text(
                              'No pending dues. All caught up!',
                              style: TextStyle(
                                fontSize: 13,
                                color: TabbyColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        )
                      else
                        ...dashboardState.reminders.map((reminder) {
                          final isOverdue = reminder.dueDate.isBefore(DateTime.now());

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: TabbyColors.surfaceWhite,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: TabbyColors.borderMint),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x04000000),
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: reminder.isIWhoOwe
                                      ? TabbyColors.iconBgBlue
                                      : TabbyColors.iconBgMint,
                                   child: Text(
                                    reminder.friendName.isNotEmpty
                                        ? reminder.friendName.substring(0, 1).toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: reminder.isIWhoOwe
                                          ? TabbyColors.accentBlue
                                          : TabbyColors.brandEmerald,
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
                                          color: TabbyColors.brandDarkTeal,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        reminder.description,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: TabbyColors.textSecondary,
                                        ),
                                      ),
                                      if (isOverdue) ...[
                                        const SizedBox(height: 2),
                                        const Text(
                                          'Past due date',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: TabbyColors.alertRed,
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
                                        fontWeight: FontWeight.w800,
                                        color: reminder.isIWhoOwe
                                            ? TabbyColors.accentBlue
                                            : TabbyColors.brandDarkTeal,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    if (reminder.isIWhoOwe)
                                      InkWell(
                                        onTap: () => context.go('/tabs/${reminder.tabId}'),
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: TabbyColors.brandEmerald,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Text(
                                            'Pay',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
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
                                              content: Text('Friendly reminder sent to ${reminder.friendName}!'),
                                              backgroundColor: TabbyColors.brandDarkTeal,
                                              duration: const Duration(seconds: 2),
                                            ),
                                          );
                                        },
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: TabbyColors.brandMintAccent,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Text(
                                            'Remind',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: TabbyColors.brandDarkTeal,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                      const SizedBox(height: 24),

                      // Recent Activity Feed Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Text(
                              'Recent Activity',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: TabbyColors.brandDarkTeal,
                                letterSpacing: -0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${dashboardState.activities.length} logs',
                            style: const TextStyle(
                              fontSize: 12,
                              color: TabbyColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      // FinWise 3-Column Transaction / Activity List (home_7033_352)
                      Builder(
                        builder: (context) {
                          final filteredActivities = dashboardState.activities.where((act) {
                            if (_selectedFilter == 'Daily') {
                              return DateTime.now().difference(act.timestamp).inHours < 24;
                            } else if (_selectedFilter == 'Weekly') {
                              return DateTime.now().difference(act.timestamp).inDays < 7;
                            }
                            return true;
                          }).toList();

                          if (filteredActivities.isEmpty) {
                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: TabbyColors.surfaceWhite,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: TabbyColors.borderMint),
                              ),
                              child: Center(
                                child: Text(
                                  _selectedFilter == 'Monthly'
                                      ? 'No recent activity yet. Log an expense to get started!'
                                      : 'No activity found for $_selectedFilter filter.',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: TabbyColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            );
                          }

                          return Column(
                            children: filteredActivities.map((act) {
                              final displayName = (act.actorName == 'You' || act.actorName == currentUser.displayName)
                                  ? 'You'
                                  : act.actorName;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: TabbyColors.surfaceWhite,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: TabbyColors.borderMint),
                                ),
                                child: InkWell(
                                  onTap: () => _showActivityDetailSheet(context, act),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      children: [
                                        // Circular Icon Squircle Container (Figma 40x40)
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: TabbyColors.iconBgBlue,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Center(
                                            child: Icon(
                                              act.iconData ?? Icons.receipt_rounded,
                                              color: TabbyColors.accentLightBlue,
                                              size: 20,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // Column 1: Title & Time
                                        Expanded(
                                          flex: 4,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                displayName,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: TabbyColors.brandDarkTeal,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _formatTimestamp(act.timestamp),
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: TabbyColors.accentLightBlue,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Column Divider
                                        Container(
                                          height: 28,
                                          width: 1,
                                          color: TabbyColors.borderMint,
                                          margin: const EdgeInsets.symmetric(horizontal: 8),
                                        ),
                                        // Column 2: Category / Context
                                        Expanded(
                                          flex: 3,
                                          child: Text(
                                            act.description,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: TabbyColors.textSecondary,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        // Column Divider
                                        Container(
                                          height: 28,
                                          width: 1,
                                          color: TabbyColors.borderMint,
                                          margin: const EdgeInsets.symmetric(horizontal: 8),
                                        ),
                                        // Column 3: Currency Amount
                                        Expanded(
                                          flex: 3,
                                          child: Text(
                                            act.amountCentavos > 0
                                                ? CurrencyFormatter.formatCentavos(act.amountCentavos)
                                                : 'Settled',
                                            textAlign: TextAlign.end,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800,
                                              color: TabbyColors.brandDarkTeal,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_home_dashboard',
        onPressed: () => AddExpenseModal.show(context),
        backgroundColor: TabbyColors.brandEmerald,
        foregroundColor: TabbyColors.surfaceWhite,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: const Icon(Icons.add_rounded, size: 22),
        label: const Text(
          'Log Expense',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
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

  void _showActivityDetailSheet(BuildContext context, TabbyActivity act) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: TabbyColors.surfaceWhite,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Activity Details',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: TabbyColors.brandDarkTeal,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: TabbyColors.iconBgBlue,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Icon(
                        act.iconData ?? Icons.receipt_rounded,
                        color: TabbyColors.accentLightBlue,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          act.actorName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: TabbyColors.brandDarkTeal,
                          ),
                        ),
                        Text(
                          act.description,
                          style: const TextStyle(
                            fontSize: 13,
                            color: TabbyColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (act.amountCentavos > 0) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: TabbyColors.brandMintAccent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Amount Recorded',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TabbyColors.brandDarkTeal),
                      ),
                      Text(
                        CurrencyFormatter.formatCentavos(act.amountCentavos),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: TabbyColors.brandDarkTeal),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.schedule_rounded, size: 16, color: TabbyColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    'Recorded ${_formatTimestamp(act.timestamp)}',
                    style: const TextStyle(fontSize: 12, color: TabbyColors.textSecondary, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: TabbyColors.brandEmerald,
                  foregroundColor: TabbyColors.surfaceWhite,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
    },
  );
}
}
