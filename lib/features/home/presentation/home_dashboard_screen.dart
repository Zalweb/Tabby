import '../../../shared/widgets/tabby_feedback.dart';
import '../../../core/theme/motion_preferences.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tabby_colors.dart';
import '../../../core/theme/tabby_palette.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../shared/widgets/notification_center_sheet.dart';
import '../../tabs/application/tabby_providers.dart';
import '../../tabs/domain/models.dart';
import '../../tabs/presentation/add_expense_modal.dart';
import '../domain/activity_period.dart';
import '../domain/home_dashboard_summary.dart';
import 'home_summary_cards.dart';

class HomeDashboardScreen extends ConsumerStatefulWidget {
  const HomeDashboardScreen({super.key, this.now});
  final DateTime Function()? now;
  @override
  ConsumerState<HomeDashboardScreen> createState() =>
      _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends ConsumerState<HomeDashboardScreen> {
  ActivityPeriod _selectedFilter = ActivityPeriod.thisMonth;
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tabbyProvider),
        user = ref.watch(currentUserProvider);
    final now = (widget.now ?? DateTime.now)();
    final p = TabbyPalette.of(context);
    final summary = HomeDashboardSummary(
      state: state,
      period: _selectedFilter,
      now: now,
      viewerId: state.viewerUserId ?? user.id,
    );
    final reminders = [...state.reminders]
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final activities = TabbyNotifier.deduplicateActivities(
      activitiesForPeriod(state.activities, _selectedFilter, now),
    );
    final firstName = user.displayName.trim().isEmpty
        ? 'Friend'
        : user.displayName.trim().split(RegExp(r'\s+')).first;
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => Future.wait<void>([
            ref.read(tabbyProvider.notifier).refreshTabs(),
            ref.read(currentUserProvider.notifier).loadFromSupabase(),
          ]),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 960),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Hi, Welcome Back',
                                      style: TextStyle(
                                        color: p.secondaryText,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      firstName,
                                      style: TextStyle(
                                        color: p.text,
                                        fontSize: 30,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.8,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Material(
                                color: p.surface,
                                shape: CircleBorder(
                                  side: BorderSide(color: p.border),
                                ),
                                child: IconButton(
                                  tooltip: 'Notifications',
                                  onPressed: () =>
                                      NotificationCenterSheet.show(context),
                                  icon: Badge(
                                    isLabelVisible:
                                        state.unreadNotificationCount > 0,
                                    backgroundColor: TabbyColors.brandAmber,
                                    textColor: TabbyColors.brandInk,
                                    label: Text(
                                      state.unreadNotificationCount > 9
                                          ? '9+'
                                          : '${state.unreadNotificationCount}',
                                    ),
                                    child: Icon(
                                      state.unreadNotificationCount > 0
                                          ? Icons.notifications_active_rounded
                                          : Icons.notifications_none_rounded,
                                      color: p.text,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          HomeBalanceHero(state: state, summary: summary),
                          if (state.hasIncompleteGroupBalances)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                'Some older group shares need review before every member balance is available.',
                                style: TextStyle(
                                  color: p.secondaryText,
                                  fontSize: 12,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          HomeTabsSummary(
                            summary: summary,
                            onCreate: () => AddExpenseModal.show(context),
                            onOpen: () => context.go('/tabs'),
                          ),
                          const SizedBox(height: 20),
                          _periodSelector(),
                          const SizedBox(height: 12),
                          HomePaymentSummary(summary: summary),
                          const SizedBox(height: 26),
                          _sectionTitle(
                            'Upcoming & Reminders',
                            reminders.length,
                            reminders.length == 1 ? 'item' : 'items',
                          ),
                          const SizedBox(height: 12),
                          if (reminders.isEmpty)
                            _empty('No pending dues. All caught up!')
                          else
                            HomeSurfaceCard(
                              padding: EdgeInsets.zero,
                              child: Column(
                                children: [
                                  for (
                                    var i = 0;
                                    i < reminders.length;
                                    i++
                                  ) ...[
                                    if (i > 0) Divider(color: p.border),
                                    _reminder(reminders[i]),
                                  ],
                                ],
                              ),
                            ),
                          const SizedBox(height: 26),
                          _sectionTitle(
                            'Recent Activity',
                            activities.length,
                            activities.length == 1 ? 'log' : 'logs',
                          ),
                          const SizedBox(height: 12),
                          if (activities.isEmpty)
                            _empty(
                              state.activities.isEmpty
                                  ? 'No recent activity yet. Log an expense to get started!'
                                  : 'No activity for ${_selectedFilter.label.toLowerCase()}.',
                            )
                          else
                            HomeSurfaceCard(
                              padding: EdgeInsets.zero,
                              child: Column(
                                children: [
                                  for (
                                    var i = 0;
                                    i < activities.length;
                                    i++
                                  ) ...[
                                    if (i > 0)
                                      Divider(color: p.border, indent: 62),
                                    _activity(activities[i]),
                                  ],
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _periodSelector() {
    final p = TabbyPalette.of(context);
    return Material(
      color: p.soft,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (final period in ActivityPeriod.values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Semantics(
                    selected: _selectedFilter == period,
                    button: true,
                    child: InkWell(
                      onTap: () => setState(() => _selectedFilter = period),
                      borderRadius: BorderRadius.circular(20),
                      child: Ink(
                        decoration: BoxDecoration(
                          color: _selectedFilter == period
                              ? TabbyColors.brandAmber
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 12,
                        ),
                        child: Text(
                          period.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _selectedFilter == period
                                ? TabbyColors.brandInk
                                : p.text,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, int count, String unit) {
    final p = TabbyPalette.of(context);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: TextStyle(
                color: p.text,
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$count $unit',
          style: TextStyle(color: p.secondaryText, fontSize: 12),
        ),
      ],
    );
  }

  Widget _empty(String message) {
    final p = TabbyPalette.of(context);
    return HomeSurfaceCard(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: p.secondaryText, fontSize: 13, height: 1.5),
      ),
    );
  }

  Widget _reminder(UpcomingReminder reminder) {
    final p = TabbyPalette.of(context);
    final tab = ref
        .read(tabbyProvider)
        .tabs
        .where((t) => t.id == reminder.tabId)
        .firstOrNull;
    final title = tab?.isGroupTab == true
        ? (tab!.groupName ?? reminder.friendName)
        : reminder.friendName;
    final now = (widget.now ?? DateTime.now)().toLocal(),
        due = reminder.dueDate.toLocal();
    final days = DateTime(
      due.year,
      due.month,
      due.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
    final when = days == 0
        ? 'Due today'
        : days == 1
        ? 'Due tomorrow'
        : days < 0
        ? 'Due ${-days} ${days == -1 ? 'day' : 'days'} ago'
        : 'Due in $days days';
    return InkWell(
      onTap: () => context.push('/tabs/${reminder.tabId}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _icon(
              tab?.isGroupTab == true
                  ? Icons.people_outline_rounded
                  : Icons.person_outline_rounded,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: p.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${reminder.isIWhoOwe ? 'You owe' : 'You are owed'} ${CurrencyFormatter.formatCentavos(reminder.amountCentavos)}',
                    style: TextStyle(
                      color: p.link,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    when,
                    style: TextStyle(color: p.secondaryText, fontSize: 12),
                  ),
                  if (!reminder.isIWhoOwe)
                    TextButton(
                      onPressed: () => _sendReminder(reminder),
                      child: const Text('Remind'),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: p.secondaryText, size: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _sendReminder(UpcomingReminder reminder) async {
    final messenger = TabbyFeedback.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      const SnackBar(content: Text('Waiting for reminder acceptance…')),
    );
    final result = await ref
        .read(tabbyProvider.notifier)
        .sendGentleNudge(
          tabId: reminder.tabId,
          recipientUserId: reminder.counterparty?.kind == PartyKind.user
              ? reminder.counterparty!.id
              : null,
          friendName: reminder.friendName,
          amountCentavos: reminder.amountCentavos,
          description: reminder.description,
        );
    if (!mounted) return;
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(result.message)));
  }

  Widget _icon(IconData icon) {
    final p = TabbyPalette.of(context);
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: p.soft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: p.link, size: 20),
    );
  }

  Widget _activity(TabbyActivity activity) {
    final p = TabbyPalette.of(context);
    final amount = Text(
      activity.amountCentavos == 0
          ? '—'
          : CurrencyFormatter.formatCentavos(activity.amountCentavos),
      style: TextStyle(
        color: p.text,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    );
    return InkWell(
      onTap: () => _showActivityDetailSheet(context, activity),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, c) {
            final stacked =
                c.maxWidth < 280 ||
                MediaQuery.textScalerOf(context).scale(16) > 23;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _icon(activity.iconData ?? Icons.receipt_long_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activity.description,
                        style: TextStyle(
                          color: p.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${activity.actorName} · ${_formatTimestamp(activity.timestamp)}',
                        style: TextStyle(
                          color: p.secondaryText,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                      if (stacked) ...[const SizedBox(height: 8), amount],
                    ],
                  ),
                ),
                if (!stacked) ...[
                  const SizedBox(width: 10),
                  Flexible(child: amount),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime date) {
    final age = (widget.now ?? DateTime.now)().difference(date);
    return age.inMinutes < 1
        ? 'Just now'
        : age.inHours < 1
        ? '${age.inMinutes}m ago'
        : age.inDays < 1
        ? '${age.inHours}h ago'
        : '${age.inDays}d ago';
  }

  void _showActivityDetailSheet(BuildContext context, TabbyActivity act) {
    showTabbyBottomSheet(
      sheetAnimationStyle: TabbyMotion.style(context),
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: TabbyPalette.of(context).surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Activity Details',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: TabbyPalette.of(context).text,
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
                        color: TabbyPalette.of(context).accentTint,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Icon(
                          act.iconData ?? Icons.receipt_rounded,
                          color: TabbyPalette.of(context).link,
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
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: TabbyPalette.of(context).text,
                            ),
                          ),
                          Text(
                            act.description,
                            style: TextStyle(
                              fontSize: 13,
                              color: TabbyPalette.of(context).secondaryText,
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
                      color: TabbyPalette.of(context).soft,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Amount Recorded',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: TabbyPalette.of(context).text,
                          ),
                        ),
                        Text(
                          CurrencyFormatter.formatCentavos(act.amountCentavos),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: TabbyPalette.of(context).text,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 16,
                      color: TabbyPalette.of(context).secondaryText,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Recorded ${_formatTimestamp(act.timestamp)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: TabbyPalette.of(context).secondaryText,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TabbyColors.brandAmber,
                    foregroundColor: TabbyColors.brandInk,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
