import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/tabby_colors.dart';
import '../../../core/utils/currency_formatter.dart';
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
      backgroundColor: TabbyColors.backgroundLight,
      appBar: AppBar(
        title: const Text(
          'My Tabs',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: TabbyColors.primaryCharcoal,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => AddExpenseModal.show(context),
            icon: const Icon(Icons.add_circle_outline_rounded, color: TabbyColors.primaryCharcoal),
            tooltip: 'Add Tab',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search & Filter Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Container(
                decoration: BoxDecoration(
                  color: TabbyColors.surfaceWhite,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: TabbyColors.borderGray),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) {
                    ref.read(tabSearchQueryProvider.notifier).state = val;
                  },
                  decoration: InputDecoration(
                    hintText: 'Search friend, barkada, or tab...',
                    prefixIcon: const Icon(Icons.search_rounded, color: TabbyColors.secondaryMuted, size: 20),
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
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),
            ),

            // Content Area
            Expanded(
              child: filteredTabs.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const TabbyMascotWidget(
                              emotion: MascotEmotion.sleeping,
                              size: 84,
                              showBubble: false,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Walang active tabs!',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: TabbyColors.primaryCharcoal,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'No active tabs found. You are completely settled up! Time for a cat nap. 😴',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: TabbyColors.secondaryMuted,
                              ),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: () => AddExpenseModal.show(context),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Log a New Tab'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: TabbyColors.primaryCharcoal,
                                foregroundColor: TabbyColors.surfaceWhite,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                      children: [
                        // Section 1: THEY OWE YOU
                        if (theyOweYouTabs.isNotEmpty) ...[
                          _buildSectionHeader(
                            title: 'THEY OWE YOU',
                            totalCentavos: totalTheyOweCentavos,
                            color: TabbyColors.successGreen,
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
                            color: TabbyColors.debtRed,
                            count: youOweTabs.length,
                          ),
                          const SizedBox(height: 8),
                          ...youOweTabs.map((tab) => _buildTabCard(context, tab)),
                          const SizedBox(height: 20),
                        ],

                        // Section 3: SETTLED TABS
                        if (settledTabs.isNotEmpty) ...[
                          _buildSectionHeader(
                            title: 'FULLY SETTLED (BAYAD NA)',
                            totalCentavos: 0,
                            color: TabbyColors.secondaryMuted,
                            count: settledTabs.length,
                          ),
                          const SizedBox(height: 8),
                          ...settledTabs.map((tab) => _buildTabCard(context, tab)),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => AddExpenseModal.show(context),
        backgroundColor: TabbyColors.primaryCharcoal,
        foregroundColor: TabbyColors.surfaceWhite,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Add Tab',
          style: TextStyle(fontWeight: FontWeight.w700),
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
        Row(
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
            Text(
              '$title ($count)',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: TabbyColors.primaryCharcoal,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
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
        ? TabbyColors.secondaryMuted
        : (isTheyOwe ? TabbyColors.successGreen : TabbyColors.debtRed);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: InkWell(
          onTap: () => context.go('/tabs/${tab.id}'),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 22,
                  backgroundColor: tab.isGroupTab
                      ? TabbyColors.pendingLight
                      : TabbyColors.backgroundLight,
                  child: Text(
                    tab.isGroupTab
                        ? '👥'
                        : tab.counterpart.displayName.substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: tab.isGroupTab ? 16 : 14,
                      color: tab.isGroupTab
                          ? TabbyColors.accentAmberDark
                          : TabbyColors.primaryCharcoal,
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
                          color: TabbyColors.primaryCharcoal,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (tab.isGroupTab) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: TabbyColors.chipBackground,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Group Tab',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: TabbyColors.textMuted,
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
                                color: TabbyColors.secondaryMuted,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Balance & Chevron
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
                          ? 'Bayad na'
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
                  color: TabbyColors.secondaryMuted,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
