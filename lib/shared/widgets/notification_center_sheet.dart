import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/tabby_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../features/tabs/application/tabby_providers.dart';
import '../../features/tabs/domain/models.dart';
import 'tabby_button.dart';
import 'tabby_mascot_widget.dart';

class NotificationCenterSheet extends ConsumerWidget {
  const NotificationCenterSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const NotificationCenterSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardState = ref.watch(tabbyProvider);
    final notifier = ref.read(tabbyProvider.notifier);
    final reminders = dashboardState.reminders;
    final activities = dashboardState.activities.take(6).toList();

    final hasNotifications = reminders.isNotEmpty || activities.isNotEmpty;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: const BoxDecoration(
        color: TabbyColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: TabbyColors.borderMint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: TabbyColors.iconBgMint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.notifications_rounded,
                      color: TabbyColors.brandEmerald,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Notifications',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: TabbyColors.brandDarkTeal,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        reminders.isNotEmpty
                            ? '${reminders.length} pending reminder${reminders.length > 1 ? 's' : ''}'
                            : 'All caught up',
                        style: const TextStyle(
                          fontSize: 11,
                          color: TabbyColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: TabbyColors.brandDarkTeal),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Content
          Expanded(
            child: !hasNotifications
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TabbyMascotWidget(
                          emotion: MascotEmotion.sleeping,
                          size: 70,
                          showBubble: false,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No New Notifications',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: TabbyColors.brandDarkTeal,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'You are all caught up! When friends send reminders or make payments, they will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: TabbyColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    children: [
                      if (reminders.isNotEmpty) ...[
                        const Text(
                          'UPCOMING & OVERDUE DUES',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: TabbyColors.brandDarkTeal,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...reminders.map((reminder) {
                          final isOverdue = reminder.dueDate.isBefore(DateTime.now());
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: TabbyColors.brandMintAccent,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: TabbyColors.borderMint),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: reminder.isIWhoOwe
                                      ? TabbyColors.iconBgBlue
                                      : TabbyColors.iconBgMint,
                                  child: Text(
                                    reminder.friendName.isNotEmpty
                                        ? reminder.friendName.substring(0, 1).toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                      color: reminder.isIWhoOwe
                                          ? TabbyColors.accentBlue
                                          : TabbyColors.brandEmerald,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        reminder.friendName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: TabbyColors.brandDarkTeal,
                                        ),
                                      ),
                                      Text(
                                        '${reminder.description} • ${CurrencyFormatter.formatCentavos(reminder.amountCentavos)}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: TabbyColors.textSecondary,
                                        ),
                                      ),
                                      if (isOverdue)
                                        const Text(
                                          'Past due date',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: TabbyColors.alertRed,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (reminder.isIWhoOwe)
                                  ElevatedButton(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      context.go('/tabs/${reminder.tabId}');
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: TabbyColors.brandEmerald,
                                      foregroundColor: TabbyColors.surfaceWhite,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      elevation: 0,
                                    ),
                                    child: const Text('Pay', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                                  )
                                else
                                  ElevatedButton(
                                    onPressed: () {
                                      notifier.sendGentleNudge(
                                        tabId: reminder.tabId,
                                        friendName: reminder.friendName,
                                        amountCentavos: reminder.amountCentavos,
                                      );
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Friendly reminder sent to ${reminder.friendName}!'),
                                          backgroundColor: TabbyColors.brandDarkTeal,
                                        ),
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: TabbyColors.surfaceWhite,
                                      foregroundColor: TabbyColors.brandDarkTeal,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      elevation: 0,
                                    ),
                                    child: const Text('Remind', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                                  ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 16),
                      ],
                      if (activities.isNotEmpty) ...[
                        const Text(
                          'RECENT ACTIVITY UPDATES',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: TabbyColors.brandDarkTeal,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...activities.map((act) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: TabbyColors.surfaceWhite,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: TabbyColors.borderMint),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: TabbyColors.iconBgBlue,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      act.iconData ?? Icons.notifications_active_outlined,
                                      color: TabbyColors.accentLightBlue,
                                      size: 16,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${(act.actorName == 'You' || act.actorName == ref.watch(currentUserProvider).displayName) ? 'You' : act.actorName} ${act.description}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: TabbyColors.brandDarkTeal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (act.amountCentavos > 0)
                                  Text(
                                    CurrencyFormatter.formatCentavos(act.amountCentavos),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: TabbyColors.brandDarkTeal,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          TabbyButton(
            label: 'Close',
            variant: TabbyButtonVariant.outline,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}
