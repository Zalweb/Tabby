import 'package:flutter/foundation.dart';
import '../domain/models.dart';

@immutable
class TabbyDashboardState {
  final List<BilateralTab> tabs;
  final List<TabbyActivity> activities;
  final List<UpcomingReminder> reminders;
  final List<FriendRequest> friendRequests;
  final List<AppNotification> notifications;
  final MascotEmotion? emotionOverride;
  final String? emotionCustomMessage;

  const TabbyDashboardState({
    required this.tabs,
    required this.activities,
    required this.reminders,
    this.friendRequests = const [],
    this.notifications = const [],
    this.emotionOverride,
    this.emotionCustomMessage,
  });

  /// Total count of unread real-time notifications
  int get unreadNotificationCount =>
      notifications.where((n) => !n.isRead).length;

  /// Total centavos you owe others across all tabs
  int get youOweCentavos {
    int total = 0;
    for (final tab in tabs) {
      if (tab.netBalanceCentavos < 0) {
        total += tab.netBalanceCentavos.abs();
      }
    }
    return total;
  }

  /// Total centavos friends owe you across all tabs
  int get youAreOwedCentavos {
    int total = 0;
    for (final tab in tabs) {
      if (tab.netBalanceCentavos > 0) {
        total += tab.netBalanceCentavos;
      }
    }
    return total;
  }

  /// Net position from user's perspective
  int get netBalanceCentavos => youAreOwedCentavos - youOweCentavos;

  /// Effective mascot emotion governed by financial standing FSM
  MascotEmotion get activeEmotion {
    if (emotionOverride != null) return emotionOverride!;

    // If completely settled or no tabs
    if (tabs.isEmpty || (youOweCentavos == 0 && youAreOwedCentavos == 0)) {
      return MascotEmotion.sleeping;
    }

    // If user has debt to settle
    if (youOweCentavos > 0 && youOweCentavos >= youAreOwedCentavos) {
      return MascotEmotion.userOwes;
    }

    // If user is owed money
    if (youAreOwedCentavos > 0) {
      return MascotEmotion.userIsOwed;
    }

    return MascotEmotion.idleNeutral;
  }

  /// Effective microcopy based on mascot state and balances (clean English, no emojis, no Tagalog)
  String get mascotMessage {
    if (emotionCustomMessage != null && emotionCustomMessage!.isNotEmpty) {
      return emotionCustomMessage!;
    }

    switch (activeEmotion) {
      case MascotEmotion.sleeping:
        return 'All tabs cleared! You are completely settled up.';
      case MascotEmotion.userOwes:
        return 'You have ₱${(youOweCentavos / 100).toStringAsFixed(2)} in active tabs to settle up.';
      case MascotEmotion.userIsOwed:
        return 'You are owed ₱${(youAreOwedCentavos / 100).toStringAsFixed(2)} across your shared tabs.';
      case MascotEmotion.celebrating:
        return 'All set! Balance updated successfully.';
      case MascotEmotion.calculating:
        return 'Calculating balances with exact centavo precision.';
      case MascotEmotion.gentleNudge:
        return 'Here is a friendly reminder for our shared tab whenever you are ready.';
      case MascotEmotion.overdue:
        return 'Some tabs are past their due date. A gentle reminder can help.';
      case MascotEmotion.paymentSubmitted:
        return 'Payment submitted! Awaiting your friend\'s confirmation.';
      case MascotEmotion.idleNeutral:
        return 'Good day! All your tabs are organized and up to date.';
    }
  }

  TabbyDashboardState copyWith({
    List<BilateralTab>? tabs,
    List<TabbyActivity>? activities,
    List<UpcomingReminder>? reminders,
    List<FriendRequest>? friendRequests,
    List<AppNotification>? notifications,
    MascotEmotion? emotionOverride,
    bool clearOverride = false,
    String? emotionCustomMessage,
  }) {
    return TabbyDashboardState(
      tabs: tabs ?? this.tabs,
      activities: activities ?? this.activities,
      reminders: reminders ?? this.reminders,
      friendRequests: friendRequests ?? this.friendRequests,
      notifications: notifications ?? this.notifications,
      emotionOverride: clearOverride ? null : (emotionOverride ?? this.emotionOverride),
      emotionCustomMessage: clearOverride ? null : (emotionCustomMessage ?? this.emotionCustomMessage),
    );
  }
}
