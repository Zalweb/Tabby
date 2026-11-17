import 'tabby_feedback.dart';
import '../../core/theme/motion_preferences.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tabby_colors.dart';
import '../../core/theme/tabby_palette.dart';
import '../../core/utils/currency_formatter.dart';
import '../../features/tabs/application/tabby_providers.dart';
import '../../features/tabs/domain/models.dart';
import 'tabby_button.dart';
import 'tabby_mascot_widget.dart';

class NotificationCenterSheet extends ConsumerWidget {
  const NotificationCenterSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showTabbyBottomSheet(
      sheetAnimationStyle: TabbyMotion.style(context),
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
    final notifications = dashboardState.notifications;
    final unreadCount = dashboardState.unreadNotificationCount;
    final reminders = dashboardState.reminders;
    final uniqueActivities = TabbyNotifier.deduplicateActivities(
      dashboardState.activities,
    );
    final activities = uniqueActivities.take(6).toList();

    final hasNotifications =
        notifications.isNotEmpty ||
        reminders.isNotEmpty ||
        activities.isNotEmpty;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        color: TabbyPalette.of(context).surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
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
                color: TabbyPalette.of(context).border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: TabbyPalette.of(context).soft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.notifications_rounded,
                        color: TabbyPalette.of(context).link,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Notifications',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: TabbyPalette.of(context).text,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            unreadCount > 0
                                ? '$unreadCount unread notification${unreadCount > 1 ? 's' : ''}'
                                : (reminders.isNotEmpty
                                      ? '${reminders.length} pending reminder${reminders.length > 1 ? 's' : ''}'
                                      : 'All caught up'),
                            style: TextStyle(
                              fontSize: 11,
                              color: TabbyPalette.of(context).secondaryText,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (unreadCount > 0) ...[
                    TextButton(
                      onPressed: () => notifier.markAllNotificationsAsRead(),
                      style: TextButton.styleFrom(
                        foregroundColor: TabbyPalette.of(context).link,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Mark all read',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                  ],
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color: TabbyPalette.of(context).text,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Content
          Expanded(
            child: !hasNotifications
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const TabbyMascotWidget(
                          emotion: MascotEmotion.sleeping,
                          size: 70,
                          showBubble: false,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No New Notifications',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: TabbyPalette.of(context).text,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'You are all caught up! When friends send reminders or make payments, they will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: TabbyPalette.of(context).secondaryText,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    children: [
                      if (notifications.isNotEmpty) ...[
                        Text(
                          'ALERTS & NOTIFICATIONS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: TabbyPalette.of(context).text,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...notifications.map((notif) {
                          IconData iconData;
                          Color iconColor = TabbyPalette.of(context).link;
                          Color iconBg = TabbyPalette.of(context).soft;

                          if (notif.type == 'payment_confirmed' ||
                              notif.type == 'payment_submitted') {
                            iconData = Icons.payments_rounded;
                          } else if (notif.type == 'debt_created' ||
                              notif.type == 'expense_added') {
                            iconData = Icons.receipt_long_rounded;
                          } else if (notif.type == 'friend_request') {
                            iconData = Icons.person_add_rounded;
                            iconColor = TabbyPalette.of(context).link;
                            iconBg = TabbyPalette.of(context).accentTint;
                          } else if (notif.type == 'tab_reminder' ||
                              notif.type == 'manual_nudge' ||
                              notif.type == 'reminder') {
                            iconData = Icons.alarm_rounded;
                            iconColor = TabbyPalette.of(context).text;
                            iconBg = TabbyPalette.of(context).soft;
                          } else {
                            iconData = Icons.notifications_active_rounded;
                          }

                          final hasTab =
                              notif.relatedTabId != null &&
                              notif.relatedTabId!.isNotEmpty;

                          return InkWell(
                            onTap: () {
                              if (!notif.isRead) {
                                notifier.markNotificationAsRead(notif.id);
                              }
                              if (hasTab) {
                                Navigator.pop(context);
                                context.push('/tabs/${notif.relatedTabId}');
                              } else if (notif.type == 'friend_request') {
                                Navigator.pop(context);
                                context.push('/profile/connections');
                              }
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: notif.isRead
                                    ? TabbyPalette.of(context).surface
                                    : TabbyPalette.of(context).soft
                                          .withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: notif.isRead
                                      ? TabbyPalette.of(context).border
                                      : TabbyColors.brandAmber.withValues(
                                          alpha: 0.5,
                                        ),
                                  width: notif.isRead ? 1 : 1.5,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: iconBg,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      iconData,
                                      color: iconColor,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                notif.title,
                                                style: TextStyle(
                                                  fontWeight: notif.isRead
                                                      ? FontWeight.w600
                                                      : FontWeight.w800,
                                                  fontSize: 13,
                                                  color: TabbyPalette.of(
                                                    context,
                                                  ).text,
                                                ),
                                              ),
                                            ),
                                            if (!notif.isRead)
                                              Container(
                                                width: 7,
                                                height: 7,
                                                margin: const EdgeInsets.only(
                                                  left: 6,
                                                ),
                                                decoration: const BoxDecoration(
                                                  color: TabbyColors.alertRed,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          notif.body,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: TabbyPalette.of(context)
                                                .secondaryText,
                                            height: 1.3,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _formatTimeAgo(notif.createdAt),
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: TabbyPalette.of(context)
                                                .secondaryText,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (hasTab) ...[
                                    const SizedBox(width: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed: () {
                                          if (!notif.isRead) {
                                            notifier.markNotificationAsRead(
                                              notif.id,
                                            );
                                          }
                                          Navigator.pop(context);
                                          context.push(
                                            '/tabs/${notif.relatedTabId}',
                                          );
                                        },
                                        style: TextButton.styleFrom(
                                          foregroundColor:
                                              TabbyColors.brandAmber,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: const Text(
                                          'View',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 16),
                      ],
                      if (reminders.isNotEmpty) ...[
                        Text(
                          'UPCOMING & OVERDUE DUES',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: TabbyPalette.of(context).text,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...reminders.map((reminder) {
                          final isOverdue = reminder.dueDate.isBefore(
                            DateTime.now(),
                          );
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: TabbyPalette.of(context).soft,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: TabbyPalette.of(context).border,
                              ),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: reminder.isIWhoOwe
                                      ? TabbyPalette.of(context).accentTint
                                      : TabbyPalette.of(context).soft,
                                  child: Text(
                                    reminder.friendName.isNotEmpty
                                        ? reminder.friendName
                                              .substring(0, 1)
                                              .toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                      color: reminder.isIWhoOwe
                                          ? TabbyPalette.of(context).link
                                          : TabbyPalette.of(context).link,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        reminder.friendName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: TabbyPalette.of(context).text,
                                        ),
                                      ),
                                      Text(
                                        '${reminder.description} • ${CurrencyFormatter.formatCentavos(reminder.amountCentavos)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: TabbyPalette.of(context)
                                              .secondaryText,
                                        ),
                                      ),
                                      if (isOverdue)
                                        Text(
                                          'Past due date',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: TabbyPalette.of(context)
                                                .errorText,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (reminder.isIWhoOwe)
                                  ElevatedButton(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      context.push('/tabs/${reminder.tabId}');
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: TabbyColors.brandAmber,
                                      foregroundColor: TabbyColors.brandInk,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: const Text(
                                      'Pay',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  )
                                else
                                  ElevatedButton(
                                    onPressed: () async {
                                      final messenger = TabbyFeedback.of(
                                        context,
                                      );
                                      messenger.clearSnackBars();
                                      messenger.showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Waiting for reminder acceptance…',
                                          ),
                                        ),
                                      );
                                      final result = await notifier
                                          .sendGentleNudge(
                                            tabId: reminder.tabId,
                                            recipientUserId:
                                                reminder.counterparty?.kind ==
                                                    PartyKind.user
                                                ? reminder.counterparty!.id
                                                : null,
                                            friendName: reminder.friendName,
                                            amountCentavos:
                                                reminder.amountCentavos,
                                          );
                                      if (!context.mounted) return;
                                      messenger.clearSnackBars();
                                      TabbyFeedback.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(content: Text(result.message)),
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: TabbyPalette.of(context)
                                          .surface,
                                      foregroundColor: TabbyPalette.of(context)
                                          .text,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: const Text(
                                      'Remind',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 16),
                      ],
                      if (activities.isNotEmpty) ...[
                        Text(
                          'RECENT ACTIVITY UPDATES',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: TabbyPalette.of(context).text,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...activities.map((act) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: TabbyPalette.of(context).surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: TabbyPalette.of(context).border,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: TabbyPalette.of(context).accentTint,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      act.iconData ??
                                          Icons.notifications_active_outlined,
                                      color: TabbyPalette.of(context).link,
                                      size: 16,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${(act.actorName == 'You' || act.actorName == ref.watch(currentUserProvider).displayName) ? 'You' : act.actorName} ${act.description}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: TabbyPalette.of(context).text,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (act.amountCentavos > 0)
                                  Text(
                                    CurrencyFormatter.formatCentavos(
                                      act.amountCentavos,
                                    ),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: TabbyPalette.of(context).text,
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

  static String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }
}
