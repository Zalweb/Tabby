import 'package:flutter/material.dart';

/// 9 Emotional Mascot States defined in AGENTS.md Section 4
enum MascotEmotion {
  idleNeutral,
  userOwes,
  userIsOwed,
  calculating,
  gentleNudge,
  overdue,
  paymentSubmitted,
  celebrating,
  sleeping,
}

extension MascotEmotionExtension on MascotEmotion {
  String get stateKey {
    switch (this) {
      case MascotEmotion.idleNeutral:
        return 'IDLE_NEUTRAL';
      case MascotEmotion.userOwes:
        return 'USER_OWES';
      case MascotEmotion.userIsOwed:
        return 'USER_IS_OWED';
      case MascotEmotion.calculating:
        return 'CALCULATING';
      case MascotEmotion.gentleNudge:
        return 'GENTLE_NUDGE';
      case MascotEmotion.overdue:
        return 'OVERDUE';
      case MascotEmotion.paymentSubmitted:
        return 'PAYMENT_SUBMITTED';
      case MascotEmotion.celebrating:
        return 'CELEBRATING';
      case MascotEmotion.sleeping:
        return 'SLEEPING';
    }
  }

  /// Clean empty string — Absolutely NO emojis in text anywhere in the app
  String get emoji => '';

  /// Clean Material Icon replacement for emotional status badges
  IconData get icon {
    switch (this) {
      case MascotEmotion.idleNeutral:
        return Icons.check_circle_outline_rounded;
      case MascotEmotion.userOwes:
        return Icons.arrow_outward_rounded;
      case MascotEmotion.userIsOwed:
        return Icons.arrow_downward_rounded;
      case MascotEmotion.calculating:
        return Icons.calculate_outlined;
      case MascotEmotion.gentleNudge:
        return Icons.send_rounded;
      case MascotEmotion.overdue:
        return Icons.warning_amber_rounded;
      case MascotEmotion.paymentSubmitted:
        return Icons.schedule_rounded;
      case MascotEmotion.celebrating:
        return Icons.task_alt_rounded;
      case MascotEmotion.sleeping:
        return Icons.nightlight_round;
    }
  }

  /// Professional, friendly conversational English microcopy without any Tagalog or emojis
  String get microcopy {
    switch (this) {
      case MascotEmotion.idleNeutral:
        return 'Good day! All your tabs are organized and up to date.';
      case MascotEmotion.userOwes:
        return 'You have active pending tabs to settle up.';
      case MascotEmotion.userIsOwed:
        return 'You have friends who still need to settle up with you.';
      case MascotEmotion.calculating:
        return 'Calculating balances with exact centavo precision.';
      case MascotEmotion.gentleNudge:
        return 'Here is a friendly reminder for our shared tab whenever you are ready.';
      case MascotEmotion.overdue:
        return 'This tab is past the due date. A friendly reminder can help.';
      case MascotEmotion.paymentSubmitted:
        return 'Payment sent! Waiting for confirmation.';
      case MascotEmotion.celebrating:
        return 'All set! Tab confirmed and balance updated.';
      case MascotEmotion.sleeping:
        return 'All tabs cleared! You are completely settled up.';
    }
  }
}

/// Expense categories aligned with FinWise UI and AGENTS.md
enum ExpenseCategory {
  food('Food', '', Icons.restaurant_rounded),
  transportation('Transportation', '', Icons.directions_car_rounded),
  borrowedCash('Borrowed Cash', '', Icons.credit_card_rounded),
  groceries('Groceries', '', Icons.shopping_basket_rounded),
  bills('Utilities and Bills', '', Icons.lightbulb_rounded),
  other('Other', '', Icons.inventory_2_rounded);

  const ExpenseCategory(this.displayName, this.emoji, this.icon);
  final String displayName;
  final String emoji;
  final IconData icon;
}

/// Transaction lifecycle status
enum TransactionStatus {
  pending('Pending Acknowledgment'),
  acknowledged('Acknowledged'),
  paymentSubmitted('Payment Submitted'),
  settled('Settled'),
  cancelled('Cancelled');

  const TransactionStatus(this.label);
  final String label;
}

/// Settlement payment methods
enum PaymentMethod {
  gcash('GCash', '', Icons.account_balance_wallet_rounded),
  maya('Maya', '', Icons.credit_card_rounded),
  cash('Cash', '', Icons.payments_rounded),
  bankTransfer('Bank Transfer', '', Icons.account_balance_rounded),
  other('Other', '', Icons.receipt_long_rounded);

  const PaymentMethod(this.label, this.icon, this.iconData);
  final String label;
  final String icon;
  final IconData iconData;
}

/// Tabby User Profile
@immutable
class TabbyUser {
  final String id;
  final String displayName;
  final String email;
  final String phone;
  final String? avatarUrl;
  final String gcashNumber;
  final String mayaNumber;

  final String? qrCodeUrl;

  const TabbyUser({
    required this.id,
    required this.displayName,
    required this.email,
    required this.phone,
    this.avatarUrl,
    this.gcashNumber = '',
    this.mayaNumber = '',
    this.qrCodeUrl,
  });

  TabbyUser copyWith({
    String? id,
    String? displayName,
    String? email,
    String? phone,
    String? avatarUrl,
    String? gcashNumber,
    String? mayaNumber,
    String? qrCodeUrl,
  }) {
    return TabbyUser(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      gcashNumber: gcashNumber ?? this.gcashNumber,
      mayaNumber: mayaNumber ?? this.mayaNumber,
      qrCodeUrl: qrCodeUrl ?? this.qrCodeUrl,
    );
  }
}

/// Participant in a split transaction
@immutable
class ParticipantShare {
  final String userId;
  final String name;
  final int shareAmountCentavos;
  final bool isPayer;
  final bool acknowledged;

  const ParticipantShare({
    required this.userId,
    required this.name,
    required this.shareAmountCentavos,
    this.isPayer = false,
    this.acknowledged = false,
  });

  ParticipantShare copyWith({
    String? userId,
    String? name,
    int? shareAmountCentavos,
    bool? isPayer,
    bool? acknowledged,
  }) {
    return ParticipantShare(
      userId: userId ?? this.userId,
      name: name ?? this.name,
      shareAmountCentavos: shareAmountCentavos ?? this.shareAmountCentavos,
      isPayer: isPayer ?? this.isPayer,
      acknowledged: acknowledged ?? this.acknowledged,
    );
  }
}

/// Ledger item (Transaction or Payment) in a Tab
@immutable
class LedgerEntry {
  final String id;
  final String tabId;
  final String title;
  final ExpenseCategory category;
  final int totalAmountCentavos;
  final int myShareCentavos;
  final int counterpartShareCentavos;
  final String paidByUserId;
  final String paidByName;
  final DateTime date;
  final DateTime? dueDate;
  final TransactionStatus status;
  final bool isPayment;
  final PaymentMethod? paymentMethod;
  final String? note;
  final String? receiptUrl;

  const LedgerEntry({
    required this.id,
    required this.tabId,
    required this.title,
    required this.category,
    required this.totalAmountCentavos,
    required this.myShareCentavos,
    required this.counterpartShareCentavos,
    required this.paidByUserId,
    required this.paidByName,
    required this.date,
    this.dueDate,
    this.status = TransactionStatus.acknowledged,
    this.isPayment = false,
    this.paymentMethod,
    this.note,
    this.receiptUrl,
  });

  LedgerEntry copyWith({
    String? id,
    String? tabId,
    String? title,
    ExpenseCategory? category,
    int? totalAmountCentavos,
    int? myShareCentavos,
    int? counterpartShareCentavos,
    String? paidByUserId,
    String? paidByName,
    DateTime? date,
    DateTime? dueDate,
    TransactionStatus? status,
    bool? isPayment,
    PaymentMethod? paymentMethod,
    String? note,
    String? receiptUrl,
  }) {
    return LedgerEntry(
      id: id ?? this.id,
      tabId: tabId ?? this.tabId,
      title: title ?? this.title,
      category: category ?? this.category,
      totalAmountCentavos: totalAmountCentavos ?? this.totalAmountCentavos,
      myShareCentavos: myShareCentavos ?? this.myShareCentavos,
      counterpartShareCentavos: counterpartShareCentavos ?? this.counterpartShareCentavos,
      paidByUserId: paidByUserId ?? this.paidByUserId,
      paidByName: paidByName ?? this.paidByName,
      date: date ?? this.date,
      dueDate: dueDate ?? this.dueDate,
      status: status ?? this.status,
      isPayment: isPayment ?? this.isPayment,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      note: note ?? this.note,
      receiptUrl: receiptUrl ?? this.receiptUrl,
    );
  }
}

/// Bilateral Tab representation between Current User and Counterpart
@immutable
class BilateralTab {
  final String id;
  final TabbyUser counterpart;
  final int netBalanceCentavos; // > 0: Counterpart owes user; < 0: User owes counterpart; 0: settled
  final int itemCount;
  final List<LedgerEntry> entries;
  final DateTime lastUpdated;
  final bool isGroupTab;
  final String? groupName;

  const BilateralTab({
    required this.id,
    required this.counterpart,
    required this.netBalanceCentavos,
    required this.itemCount,
    required this.entries,
    required this.lastUpdated,
    this.isGroupTab = false,
    this.groupName,
  });

  BilateralTab copyWith({
    String? id,
    TabbyUser? counterpart,
    int? netBalanceCentavos,
    int? itemCount,
    List<LedgerEntry>? entries,
    DateTime? lastUpdated,
    bool? isGroupTab,
    String? groupName,
  }) {
    return BilateralTab(
      id: id ?? this.id,
      counterpart: counterpart ?? this.counterpart,
      netBalanceCentavos: netBalanceCentavos ?? this.netBalanceCentavos,
      itemCount: itemCount ?? this.itemCount,
      entries: entries ?? this.entries,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      isGroupTab: isGroupTab ?? this.isGroupTab,
      groupName: groupName ?? this.groupName,
    );
  }
}

/// Recent activity item for the feed
@immutable
class TabbyActivity {
  final String id;
  final String actorName;
  final String description;
  final int amountCentavos;
  final DateTime timestamp;
  final String icon;
  final IconData? iconData;

  const TabbyActivity({
    required this.id,
    required this.actorName,
    required this.description,
    required this.amountCentavos,
    required this.timestamp,
    this.icon = '',
    this.iconData,
  });
}

/// Upcoming reminder item
@immutable
class UpcomingReminder {
  final String id;
  final String tabId;
  final String friendName;
  final String description;
  final int amountCentavos;
  final DateTime dueDate;
  final bool isIWhoOwe; // true if current user owes; false if friend owes current user

  const UpcomingReminder({
    required this.id,
    required this.tabId,
    required this.friendName,
    required this.description,
    required this.amountCentavos,
    required this.dueDate,
    required this.isIWhoOwe,
  });
}
