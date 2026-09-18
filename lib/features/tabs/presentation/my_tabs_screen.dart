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
  bool _showGroups = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredTabs = ref.watch(filteredTabsProvider);
    final activeTabs = filteredTabs
        .where((tab) => !tab.isGroupTab && tab.netBalanceCentavos != 0)
        .toList();
    final settledTabs = filteredTabs
        .where((tab) => !tab.isGroupTab && tab.netBalanceCentavos == 0)
        .toList();
    final groups = filteredTabs.where((tab) => tab.isGroupTab).toList();

    return Scaffold(
      backgroundColor: TabbyColors.brandEmerald,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildEmeraldHeader(context),
            Expanded(
              child: Material(
                color: TabbyColors.bgCanvas,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(36)),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    _buildViewSwitcher(),
                    _buildSearchBar(),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () =>
                            ref.read(tabbyProvider.notifier).refreshTabs(),
                        color: TabbyColors.brandEmerald,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
                          child: _showGroups
                              ? _buildGroupsView(groups)
                              : _buildActiveView(
                                  activeTabs: activeTabs,
                                  groups: groups,
                                  settledTabs: settledTabs,
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
    );
  }

  Widget _buildEmeraldHeader(BuildContext context) {
    return Container(
      color: TabbyColors.brandEmerald,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'My Tabs',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: TabbyColors.brandDarkTeal,
                letterSpacing: -0.5,
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => AddExpenseModal.show(context),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Create Tab'),
            style: ElevatedButton.styleFrom(
              backgroundColor: TabbyColors.surfaceWhite,
              foregroundColor: TabbyColors.brandDarkTeal,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
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
              tooltip: 'Notifications',
              icon: const Icon(
                Icons.notifications_none_rounded,
                size: 21,
                color: TabbyColors.brandDarkTeal,
              ),
              onPressed: () => NotificationCenterSheet.show(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewSwitcher() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: TabbyColors.brandMintAccent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment<bool>(
              value: false,
              label: Text('Active'),
            ),
            ButtonSegment<bool>(
              value: true,
              label: Text('Groups'),
            ),
          ],
          selected: {_showGroups},
          showSelectedIcon: false,
          onSelectionChanged: (selection) {
            setState(() => _showGroups = selection.first);
          },
          style: ButtonStyle(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(vertical: 9),
            ),
            side: WidgetStateProperty.all(BorderSide.none),
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? TabbyColors.brandEmerald
                  : Colors.transparent;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? TabbyColors.surfaceWhite
                  : TabbyColors.brandDarkTeal;
            }),
            textStyle: WidgetStateProperty.resolveWith((states) {
              return TextStyle(
                fontSize: 12,
                fontWeight: states.contains(WidgetState.selected)
                    ? FontWeight.w800
                    : FontWeight.w600,
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Container(
        decoration: BoxDecoration(
          color: TabbyColors.brandMintAccent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (value) {
            ref.read(tabSearchQueryProvider.notifier).state = value;
          },
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: TabbyColors.brandDarkTeal,
          ),
          decoration: InputDecoration(
            hintText: 'Search friends or tabs...',
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: TabbyColors.textSecondary,
              size: 20,
            ),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      ref.read(tabSearchQueryProvider.notifier).state = '';
                      setState(() {});
                    },
                  ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            filled: false,
          ),
        ),
      ),
    );
  }

  Widget _buildActiveView({
    required List<BilateralTab> activeTabs,
    required List<BilateralTab> groups,
    required List<BilateralTab> settledTabs,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeading('Active Tabs'),
        const SizedBox(height: 8),
        if (activeTabs.isEmpty)
          _buildEmptyState(
            title: 'No Active Tabs',
            subtitle: 'Start keeping tabs with your friends!',
            buttonLabel: 'Create your first tab',
          )
        else
          ...activeTabs.map((tab) => _buildTabCard(tab)),
        if (groups.isNotEmpty) ...[
          const SizedBox(height: 18),
          _buildSectionHeading(
            'Groups',
            action: 'View all',
            onAction: () => setState(() => _showGroups = true),
          ),
          const SizedBox(height: 8),
          ...groups.map((tab) => _buildTabCard(tab)),
        ],
        if (settledTabs.isNotEmpty) ...[
          const SizedBox(height: 18),
          _buildSectionHeading('Settled Tabs'),
          const SizedBox(height: 8),
          ...settledTabs.map((tab) => _buildTabCard(tab)),
        ],
      ],
    );
  }

  Widget _buildGroupsView(List<BilateralTab> groups) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeading('Groups'),
        const SizedBox(height: 8),
        if (groups.isEmpty)
          _buildEmptyState(
            title: 'No Groups Yet',
            subtitle: 'Create a group tab for shared expenses.',
            buttonLabel: 'Create a group tab',
          )
        else
          ...groups.map((tab) => _buildTabCard(tab)),
      ],
    );
  }

  Widget _buildSectionHeading(
    String title, {
    String? action,
    VoidCallback? onAction,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: TabbyColors.brandDarkTeal,
            ),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: TabbyColors.brandEmerald,
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  action,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 17),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTabCard(BilateralTab tab) {
    final isSettled = tab.netBalanceCentavos == 0;
    final title = tab.isGroupTab
        ? (tab.groupName ?? tab.counterpart.displayName)
        : tab.counterpart.displayName;
    final amount = _tabAmountCentavos(tab);
    final amountLabel = CurrencyFormatter.formatCentavos(amount);
    final peopleLabel = _peopleLabel(tab);
    final statusLabel = isSettled ? 'Settled' : 'Open';
    final category = tab.entries.isEmpty ? null : tab.entries.first.category;

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
          padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
          child: Row(
            children: [
              _buildTabIcon(tab, category),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: TabbyColors.brandDarkTeal,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$amountLabel · $peopleLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: TabbyColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildParticipantBubbles(tab),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSettled
                          ? TabbyColors.borderMint
                          : TabbyColors.brandMintAccent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: isSettled
                            ? TabbyColors.textSecondary
                            : TabbyColors.brandEmerald,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: TabbyColors.textSecondary,
                    size: 19,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabIcon(BilateralTab tab, ExpenseCategory? category) {
    final icon = tab.isGroupTab
        ? Icons.groups_rounded
        : (category?.icon ?? Icons.receipt_long_rounded);
    final background =
        tab.isGroupTab ? TabbyColors.iconBgMint : TabbyColors.iconBgBlue;
    final foreground =
        tab.isGroupTab ? TabbyColors.alertRed : TabbyColors.accentLightBlue;

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Icon(icon, color: foreground, size: 24),
    );
  }

  Widget _buildParticipantBubbles(BilateralTab tab) {
    final names = _participantNames(tab);
    final visibleNames = names.take(4).toList();
    final remaining = names.length - visibleNames.length;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...visibleNames.map(
          (name) => Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _avatarColor(name),
                shape: BoxShape.circle,
                border: Border.all(
                  color: TabbyColors.surfaceWhite,
                  width: 1.5,
                ),
              ),
              child: Text(
                _initial(name),
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: TabbyColors.brandDarkTeal,
                ),
              ),
            ),
          ),
        ),
        if (remaining > 0)
          Text(
            '+$remaining',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: TabbyColors.textSecondary,
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState({
    required String title,
    required String subtitle,
    required String buttonLabel,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 12),
      child: Center(
        child: Column(
          children: [
            const TabbyMascotWidget(
              emotion: MascotEmotion.sleeping,
              size: 64,
              showBubble: false,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: TabbyColors.brandDarkTeal,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: TabbyColors.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: () => AddExpenseModal.show(context),
              icon: const Icon(Icons.add_rounded, size: 17),
              label: Text(buttonLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: TabbyColors.brandEmerald,
                foregroundColor: TabbyColors.surfaceWhite,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _tabAmountCentavos(BilateralTab tab) {
    final total = tab.entries.fold<int>(
      0,
      (sum, entry) => sum + entry.totalAmountCentavos,
    );
    return total == 0 ? tab.netBalanceCentavos.abs() : total;
  }

  String _peopleLabel(BilateralTab tab) {
    final count = _participantNames(tab).length;
    return '$count ${count == 1 ? 'person' : 'people'}';
  }

  List<String> _participantNames(BilateralTab tab) {
    if (!tab.isGroupTab) {
      return ['You', tab.counterpart.displayName];
    }

    final memberNames = tab.counterpart.phone
        .split(',')
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    return ['You', ...memberNames];
  }

  String _initial(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? '?' : normalized.substring(0, 1).toUpperCase();
  }

  Color _avatarColor(String value) {
    final colors = <Color>[
      TabbyColors.iconBgBlue,
      TabbyColors.brandMintAccent,
      const Color(0xFFFFE7D6),
      const Color(0xFFE9E1FF),
    ];
    final normalized = value.trim();
    final index = normalized.isEmpty ? 0 : normalized.codeUnitAt(0);
    return colors[index % colors.length];
  }
}
