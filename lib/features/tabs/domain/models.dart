import 'package:flutter/foundation.dart';

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

  String get emoji {
    switch (this) {
      case MascotEmotion.idleNeutral:
        return '🐱';
      case MascotEmotion.userOwes:
        return '🥺';
      case MascotEmotion.userIsOwed:
        return '👀';
      case MascotEmotion.calculating:
        return '🐾';
      case MascotEmotion.gentleNudge:
        return '🐾';
      case MascotEmotion.overdue:
        return '🥺';
      case MascotEmotion.paymentSubmitted:
        return '⏳';
      case MascotEmotion.celebrating:
        return '🎉';
      case MascotEmotion.sleeping:
        return '😴';
    }
  }

  String get microcopy {
    switch (this) {
      case MascotEmotion.idleNeutral:
        return 'Good day! All your tabs are organized and up to date.';
      case MascotEmotion.userOwes:
        return 'Psst... you have pending tabs to settle up.';
      case MascotEmotion.userIsOwed:
        return 'You have friends who still need to settle up with you!';
      case MascotEmotion.calculating:
        return 'Crunching the numbers with zero-centavo drift... 🐾';
      case MascotEmotion.gentleNudge:
        return 'Psst! Pasuyo nung tab natin pag convenient sa’yo 🐱';
      case MascotEmotion.overdue:
        return 'This one is a little past due date... maybe send a soft reminder?';
      case MascotEmotion.paymentSubmitted:
        return 'Payment sent! Waiting for your friend to confirm. ⏳';
      case MascotEmotion.celebrating:
        return 'Nice! One less tab! Tabby approves! 🎉';
      case MascotEmotion.sleeping:
        return 'All tabs cleared! Tabby can take a cozy cat nap. 😴';
    }
  }
}

/// Expense categories aligned with AGENTS.md
enum ExpenseCategory {
  food('Food', '🍔'),
  transportation('Fare / Transpo', '🚗'),
  borrowedCash('Borrowed Cash', '💳'),
  groceries('Groceries', '🛒'),
  bills('Utilities / Bills', '💡'),
  other('Other', '📦');

  const ExpenseCategory(this.displayName, this.emoji);
  final String displayName;
  final String emoji;
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
  gcash('GCash', '💙'),
  maya('Maya', '💚'),
  cash('Cash', '💵'),
  bankTransfer('Bank Transfer', '🏦'),
  other('Other', '🪙');

  const PaymentMethod(this.label, this.icon);
  final String label;
  final String icon;
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

  const TabbyUser({
    required this.id,
    required this.displayName,
    required this.email,
    required this.phone,
    this.avatarUrl,
    this.gcashNumber = '',
    this.mayaNumber = '',
  });
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

  const TabbyActivity({
    required this.id,
    required this.actorName,
    required this.description,
    required this.amountCentavos,
    required this.timestamp,
    required this.icon,
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
