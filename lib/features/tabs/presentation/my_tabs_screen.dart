import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/tabby_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../shared/widgets/notification_center_sheet.dart';
import '../../../shared/widgets/tabby_mascot_widget.dart';
import '../application/tabby_providers.dart';
import '../domain/models.dart';
import 'add_expense_modal.dart';

class MyTabsScreen extends ConsumerStatefulWidget {
  const MyTabsScreen({super.key});

  @override
  ConsumerState<MyTabsScreen> createState() => _MyTabsScreenState();
}

class _MyTabsScreenState extends ConsumerState<MyTabsScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredTabs = ref.watch(filteredTabsProvider);
    final dashboardState = ref.watch(tabbyProvider);

    // Group tabs into "They Owe You", "You Owe", and "Settled"
    final theyOweYouTabs = filteredTabs.where((t) => t.netBalanceCentavos > 0).toList();
    final youOweTabs = filteredTabs.where((t) => t.netBalanceCentavos < 0).toList();
    final settledTabs = filteredTabs.where((t) => t.netBalanceCentavos == 0).toList();

    final totalTheyOweCentavos = theyOweYouTabs.fold<int>(
      0,
      (sum, item) => sum + item.netBalanceCentavos,
    );
    final totalYouOweCentavos = youOweTabs.fold<int>(
      0,
      (sum, item) => sum + item.netBalanceCentavos.abs(),
    );

    return Scaffold(
      backgroundColor: TabbyColors.brandEmerald,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top Green Hero Section (Figma transactions_7035_978)
            Container(
              color: TabbyColors.brandEmerald,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                children: [
                  // App Bar Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'My Tabs',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: TabbyColors.brandDarkTeal,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: TabbyColors.surfaceWhite,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.add_rounded, size: 22, color: TabbyColors.brandDarkTeal),
                              onPressed: () => AddExpenseModal.show(context),
                              tooltip: 'Add Tab',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: TabbyColors.surfaceWhite,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: IconButton(
                              icon: const Icon(
                                Icons.notifications_none_rounded,
                                size: 22,
                                color: TabbyColors.brandDarkTeal,
                              ),
                              onPressed: () => NotificationCenterSheet.show(context),
                              tooltip: 'Notifications',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Total Balance Card (Figma transactions_7035_978)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: TabbyColors.surfaceWhite,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Total Balance',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: TabbyColors.textSecondary,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          CurrencyFormatter.formatCentavos(dashboardState.netBalanceCentavos.abs()),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: dashboardState.netBalanceCentavos >= 0
                                ? TabbyColors.brandDarkTeal
                                : TabbyColors.accentBlue,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Dual Cards: Income (They Owe You) & Expense (You Owe) matching Figma 7110:3203 & 7110:3210
                  Row(
                    children: [
                      // Card 1: They Owe You (Income style)
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: TabbyColors.surfaceWhite,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: TabbyColors.iconBgMint,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.north_east_rounded,
                                  size: 16,
                                  color: TabbyColors.brandEmerald,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'They Owe You',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: TabbyColors.brandDarkTeal,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  CurrencyFormatter.formatCentavos(totalTheyOweCentavos),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: TabbyColors.brandDarkTeal,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Card 2: You Owe (Expense style)
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: TabbyColors.surfaceWhite,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: TabbyColors.iconBgBlue,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.south_west_rounded,
                                  size: 16,
                                  color: TabbyColors.accentBlue,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'You Owe',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: TabbyColors.brandDarkTeal,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '-${CurrencyFormatter.formatCentavos(totalYouOweCentavos)}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: TabbyColors.accentBlue,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Main Curved Content Container
            Expanded(
              child: Material(
                color: TabbyColors.bgCanvas,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    // Search Bar & Calendar Quick Filter (Figma 7043:3390)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: TabbyColors.brandMintAccent,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (val) {
                            ref.read(tabSearchQueryProvider.notifier).state = val;
                          },
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: TabbyColors.brandDarkTeal,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search friends or tabs...',
                            prefixIcon: const Icon(Icons.search_rounded, color: TabbyColors.textSecondary, size: 22),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      ref.read(tabSearchQueryProvider.notifier).state = '';
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            filled: false,
                          ),
                        ),
                      ),
                    ),

                    // Content Area
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () async {
                          await ref.read(tabbyProvider.notifier).refreshTabs();
                        },
                        color: TabbyColors.brandEmerald,
                        child: filteredTabs.isEmpty
                            ? SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const TabbyMascotWidget(
                                        emotion: MascotEmotion.sleeping,
                                        size: 70,
                                        showBubble: false,
                                      ),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'No Active Tabs',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: TabbyColors.brandDarkTeal,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Start keeping tabs with your friends!',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: TabbyColors.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      ElevatedButton.icon(
                                        onPressed: () => AddExpenseModal.show(context),
                                        icon: const Icon(Icons.add_rounded, size: 18),
                                        label: const Text('Add Your First Tab'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: TabbyColors.brandEmerald,
                                          foregroundColor: TabbyColors.surfaceWhite,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Section 1: THEY OWE YOU
                                    if (theyOweYouTabs.isNotEmpty) ...[
                                      _buildSectionHeader(
                                        title: 'THEY OWE YOU',
                                        totalCentavos: totalTheyOweCentavos,
                                        color: TabbyColors.brandEmerald,
                                        count: theyOweYouTabs.length,
                                      ),
                                      const SizedBox(height: 8),
                                      ...theyOweYouTabs.map((tab) => _buildTabCard(context, tab)),
                                      const SizedBox(height: 20),
                                    ],

                                    // Section 2: YOU OWE
                                    if (youOweTabs.isNotEmpty) ...[
                                      _buildSectionHeader(
                                        title: 'YOU OWE',
                                        totalCentavos: totalYouOweCentavos,
                                        color: TabbyColors.accentBlue,
                                        count: youOweTabs.length,
                                      ),
                                      const SizedBox(height: 8),
                                      ...youOweTabs.map((tab) => _buildTabCard(context, tab)),
                                      const SizedBox(height: 20),
                                    ],

                                    // Section 3: FULLY SETTLED
                                    if (settledTabs.isNotEmpty) ...[
                                      _buildSectionHeader(
                                        title: 'FULLY SETTLED',
                                        totalCentavos: 0,
                                        color: TabbyColors.textSecondary,
                                        count: settledTabs.length,
                                      ),
                                      const SizedBox(height: 8),
                                      ...settledTabs.map((tab) => _buildTabCard(context, tab)),
                                    ],
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_my_tabs',
        onPressed: () => AddExpenseModal.show(context),
        backgroundColor: TabbyColors.brandEmerald,
        foregroundColor: TabbyColors.surfaceWhite,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Add Tab',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required int totalCentavos,
    required Color color,
    required int count,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: [
              Container(
                width: 4,
                height: 14,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$title ($count)',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: TabbyColors.brandDarkTeal,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          CurrencyFormatter.formatCentavos(totalCentavos),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildTabCard(BuildContext context, BilateralTab tab) {
    final isTheyOwe = tab.netBalanceCentavos > 0;
    final isSettled = tab.netBalanceCentavos == 0;
    final balanceColor = isSettled
        ? TabbyColors.textSecondary
        : (isTheyOwe ? TabbyColors.brandEmerald : TabbyColors.accentBlue);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: TabbyColors.surfaceWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TabbyColors.borderMint),
        boxShadow: const [
          BoxShadow(
            color: Color(0x04000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => context.go('/tabs/${tab.id}'),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 22,
                backgroundColor: tab.isGroupTab
                    ? TabbyColors.iconBgMint
                    : TabbyColors.iconBgBlue,
                child: Text(
                  tab.isGroupTab
                      ? 'G'
                      : (tab.counterpart.displayName.isNotEmpty
                          ? tab.counterpart.displayName.substring(0, 1).toUpperCase()
                          : '?'),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: tab.isGroupTab
                        ? TabbyColors.brandEmerald
                        : TabbyColors.accentLightBlue,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Name & Item Count
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tab.isGroupTab
                          ? (tab.groupName ?? tab.counterpart.displayName)
                          : tab.counterpart.displayName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: TabbyColors.brandDarkTeal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (tab.isGroupTab) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: TabbyColors.brandMintAccent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Group',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: TabbyColors.brandDarkTeal,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            '${tab.itemCount} ${tab.itemCount == 1 ? 'item' : 'items'}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: TabbyColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Balance & Subtitle
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.formatCentavos(tab.netBalanceCentavos.abs()),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: balanceColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isSettled
                        ? 'Settled'
                        : (isTheyOwe ? 'Owes you' : 'You owe'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: balanceColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                color: TabbyColors.textSecondary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
