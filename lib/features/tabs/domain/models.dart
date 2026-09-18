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
  final String? friendCode;

  const TabbyUser({
    required this.id,
    required this.displayName,
    required this.email,
    required this.phone,
    this.avatarUrl,
    this.gcashNumber = '',
    this.mayaNumber = '',
    this.qrCodeUrl,
    this.friendCode,
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
    String? friendCode,
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
      friendCode: friendCode ?? this.friendCode,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'displayName': displayName,
        'email': email,
        'phone': phone,
        'avatarUrl': avatarUrl,
        'gcashNumber': gcashNumber,
        'mayaNumber': mayaNumber,
        'qrCodeUrl': qrCodeUrl,
        'friendCode': friendCode,
      };

  factory TabbyUser.fromMap(Map<String, dynamic> map) => TabbyUser(
        id: map['id'] as String? ?? '',
        displayName:
            (map['displayName'] ?? map['display_name']) as String? ?? '',
        email: map['email'] as String? ?? '',
        phone: map['phone'] as String? ?? '',
        avatarUrl: (map['avatarUrl'] ?? map['avatar_url']) as String?,
        gcashNumber:
            (map['gcashNumber'] ?? map['gcash_number']) as String? ?? '',
        mayaNumber: (map['mayaNumber'] ?? map['maya_number']) as String? ?? '',
        qrCodeUrl: (map['qrCodeUrl'] ?? map['qr_code_url']) as String?,
        friendCode: (map['friendCode'] ?? map['friend_code']) as String?,
      );
}

/// Normalizes a copied or typed Tabby ID without exposing a database UUID.
///
/// IDs use the format TAB-XXXXXX. The payload alphabet excludes ambiguous
/// characters (0, 1, I, and O) so a code can be read aloud or shared in chat.
String? normalizeFriendCode(String value) {
  var normalized = value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  normalized = normalized.replaceFirst(RegExp(r'^TAB-?'), '');

  if (!RegExp(r'^[A-HJ-NP-Z2-9]{6}$').hasMatch(normalized)) {
    return null;
  }

  return 'TAB-$normalized';
}

enum FriendRequestStatus {
  pending,
  accepted,
  declined,
  blocked;

  static FriendRequestStatus fromValue(dynamic value) {
    switch ((value as String? ?? '').toLowerCase()) {
      case 'accepted':
        return FriendRequestStatus.accepted;
      case 'declined':
        return FriendRequestStatus.declined;
      case 'blocked':
        return FriendRequestStatus.blocked;
      default:
        return FriendRequestStatus.pending;
    }
  }
}

@immutable
class FriendRequest {
  final String id;
  final String requesterId;
  final String addresseeId;
  final TabbyUser requester;
  final TabbyUser addressee;
  final FriendRequestStatus status;
  final DateTime createdAt;
  final DateTime? respondedAt;
  final String? currentUserId;

  const FriendRequest({
    required this.id,
    required this.requesterId,
    required this.addresseeId,
    required this.requester,
    required this.addressee,
    required this.status,
    required this.createdAt,
    this.respondedAt,
    this.currentUserId,
  });

  bool get isIncoming => currentUserId != null && addresseeId == currentUserId;

  TabbyUser get otherUser => isIncoming ? requester : addressee;

  factory FriendRequest.fromMap(
    Map<String, dynamic> map, {
    String? currentUserId,
  }) {
    final requesterMap = map['requester'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(map['requester'] as Map)
        : <String, dynamic>{
            'id': map['requester_id'],
            'display_name': map['requester_display_name'],
            'avatar_url': map['requester_avatar_url'],
            'friend_code': map['requester_friend_code'],
          };
    final addresseeMap = map['addressee'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(map['addressee'] as Map)
        : <String, dynamic>{
            'id': map['addressee_id'],
            'display_name': map['addressee_display_name'],
            'avatar_url': map['addressee_avatar_url'],
            'friend_code': map['addressee_friend_code'],
          };
    final createdAt = DateTime.tryParse(map['created_at'] as String? ?? '');

    return FriendRequest(
      id: map['id'] as String? ?? '',
      requesterId:
          map['requester_id'] as String? ?? requesterMap['id'] as String? ?? '',
      addresseeId:
          map['addressee_id'] as String? ?? addresseeMap['id'] as String? ?? '',
      requester: TabbyUser.fromMap(requesterMap),
      addressee: TabbyUser.fromMap(addresseeMap),
      status: FriendRequestStatus.fromValue(map['status']),
      createdAt: createdAt ?? DateTime.now(),
      respondedAt: map['responded_at'] is String
          ? DateTime.tryParse(map['responded_at'] as String)
          : null,
      currentUserId: currentUserId,
    );
  }
}

/// Returns the registered user IDs that are eligible for group membership.
/// Only accepted Friendship records qualify; pending and declined requests do
/// not grant group access.
Set<String> acceptedFriendUserIds(Iterable<FriendRequest> friendRequests) {
  return friendRequests
      .where((request) => request.status == FriendRequestStatus.accepted)
      .map((request) => request.otherUser.id)
      .where((id) => id.isNotEmpty)
      .toSet();
}

/// Filters requested group members to accepted registered Friends only.
List<String> filterEligibleGroupMemberIds({
  required Iterable<String> requestedIds,
  required Iterable<FriendRequest> friendRequests,
}) {
  final eligibleIds = acceptedFriendUserIds(friendRequests);
  return requestedIds.where(eligibleIds.contains).toList();
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

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'name': name,
        'shareAmountCentavos': shareAmountCentavos,
        'isPayer': isPayer,
        'acknowledged': acknowledged,
      };

  factory ParticipantShare.fromMap(Map<String, dynamic> map) =>
      ParticipantShare(
        userId: map['userId'] as String? ?? '',
        name: map['name'] as String? ?? '',
        shareAmountCentavos: (map['shareAmountCentavos'] as num?)?.toInt() ?? 0,
        isPayer: map['isPayer'] as bool? ?? false,
        acknowledged: map['acknowledged'] as bool? ?? false,
      );
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
      counterpartShareCentavos:
          counterpartShareCentavos ?? this.counterpartShareCentavos,
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

  Map<String, dynamic> toMap() => {
        'id': id,
        'tabId': tabId,
        'title': title,
        'category': category.name,
        'totalAmountCentavos': totalAmountCentavos,
        'myShareCentavos': myShareCentavos,
        'counterpartShareCentavos': counterpartShareCentavos,
        'paidByUserId': paidByUserId,
        'paidByName': paidByName,
        'date': date.toIso8601String(),
        'dueDate': dueDate?.toIso8601String(),
        'status': status.name,
        'isPayment': isPayment,
        'paymentMethod': paymentMethod?.name,
        'note': note,
        'receiptUrl': receiptUrl,
      };

  factory LedgerEntry.fromMap(Map<String, dynamic> map) {
    ExpenseCategory cat = ExpenseCategory.other;
    final catName = map['category'] as String?;
    if (catName != null) {
      for (final c in ExpenseCategory.values) {
        if (c.name == catName) {
          cat = c;
          break;
        }
      }
    }

    TransactionStatus st = TransactionStatus.acknowledged;
    final stName = map['status'] as String?;
    if (stName != null) {
      for (final s in TransactionStatus.values) {
        if (s.name == stName) {
          st = s;
          break;
        }
      }
    }

    PaymentMethod? pm;
    final pmName = map['paymentMethod'] as String?;
    if (pmName != null) {
      for (final p in PaymentMethod.values) {
        if (p.name == pmName) {
          pm = p;
          break;
        }
      }
    }

    return LedgerEntry(
      id: map['id'] as String? ?? '',
      tabId: map['tabId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      category: cat,
      totalAmountCentavos: (map['totalAmountCentavos'] as num?)?.toInt() ?? 0,
      myShareCentavos: (map['myShareCentavos'] as num?)?.toInt() ?? 0,
      counterpartShareCentavos:
          (map['counterpartShareCentavos'] as num?)?.toInt() ?? 0,
      paidByUserId: map['paidByUserId'] as String? ?? '',
      paidByName: map['paidByName'] as String? ?? '',
      date: map['date'] != null
          ? (DateTime.tryParse(map['date'] as String) ?? DateTime.now())
          : DateTime.now(),
      dueDate: map['dueDate'] != null
          ? DateTime.tryParse(map['dueDate'] as String)
          : null,
      status: st,
      isPayment: map['isPayment'] as bool? ?? false,
      paymentMethod: pm,
      note: map['note'] as String?,
      receiptUrl: map['receiptUrl'] as String?,
    );
  }
}

/// Bilateral Tab representation between Current User and Counterpart
@immutable
class BilateralTab {
  final String id;
  final TabbyUser counterpart;
  final int
      netBalanceCentavos; // > 0: Counterpart owes user; < 0: User owes counterpart; 0: settled
  final int itemCount;
  final List<LedgerEntry> entries;
  final DateTime lastUpdated;
  final bool isGroupTab;
  final String? groupName;

  /// True when this tab tracks an unregistered person without creating a Friend relationship.
  final bool isTabOnlyParticipant;

  const BilateralTab({
    required this.id,
    required this.counterpart,
    required this.netBalanceCentavos,
    required this.itemCount,
    required this.entries,
    required this.lastUpdated,
    this.isGroupTab = false,
    this.groupName,
    this.isTabOnlyParticipant = false,
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
    bool? isTabOnlyParticipant,
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
      isTabOnlyParticipant: isTabOnlyParticipant ?? this.isTabOnlyParticipant,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'counterpart': counterpart.toMap(),
        'netBalanceCentavos': netBalanceCentavos,
        'itemCount': itemCount,
        'entries': entries.map((e) => e.toMap()).toList(),
        'lastUpdated': lastUpdated.toIso8601String(),
        'isGroupTab': isGroupTab,
        'groupName': groupName,
        'isTabOnlyParticipant': isTabOnlyParticipant,
      };

  factory BilateralTab.fromMap(Map<String, dynamic> map) => BilateralTab(
        id: map['id'] as String? ?? '',
        counterpart: map['counterpart'] is Map<String, dynamic>
            ? TabbyUser.fromMap(map['counterpart'] as Map<String, dynamic>)
            : TabbyUser(
                id: map['id'] as String? ?? '',
                displayName: 'Friend',
                email: '',
                phone: ''),
        netBalanceCentavos: (map['netBalanceCentavos'] as num?)?.toInt() ?? 0,
        itemCount: (map['itemCount'] as num?)?.toInt() ??
            (map['entries'] as List<dynamic>?)?.length ??
            0,
        entries: (map['entries'] as List<dynamic>?)
                ?.map((e) => LedgerEntry.fromMap(e as Map<String, dynamic>))
                .toList() ??
            const [],
        lastUpdated: map['lastUpdated'] != null
            ? (DateTime.tryParse(map['lastUpdated'] as String) ??
                DateTime.now())
            : DateTime.now(),
        isGroupTab: map['isGroupTab'] as bool? ?? false,
        groupName: map['groupName'] as String?,
        isTabOnlyParticipant: map['isTabOnlyParticipant'] as bool? ?? false,
      );
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

  Map<String, dynamic> toMap() => {
        'id': id,
        'actorName': actorName,
        'description': description,
        'amountCentavos': amountCentavos,
        'timestamp': timestamp.toIso8601String(),
        'icon': icon,
      };

  factory TabbyActivity.fromMap(Map<String, dynamic> map) => TabbyActivity(
        id: map['id'] as String? ?? '',
        actorName: map['actorName'] as String? ?? '',
        description: map['description'] as String? ?? '',
        amountCentavos: (map['amountCentavos'] as num?)?.toInt() ?? 0,
        timestamp: map['timestamp'] != null
            ? (DateTime.tryParse(map['timestamp'] as String) ?? DateTime.now())
            : DateTime.now(),
        icon: map['icon'] as String? ?? '',
      );
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
  final bool
      isIWhoOwe; // true if current user owes; false if friend owes current user

  const UpcomingReminder({
    required this.id,
    required this.tabId,
    required this.friendName,
    required this.description,
    required this.amountCentavos,
    required this.dueDate,
    required this.isIWhoOwe,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'tabId': tabId,
        'friendName': friendName,
        'description': description,
        'amountCentavos': amountCentavos,
        'dueDate': dueDate.toIso8601String(),
        'isIWhoOwe': isIWhoOwe,
      };

  factory UpcomingReminder.fromMap(Map<String, dynamic> map) =>
      UpcomingReminder(
        id: map['id'] as String? ?? '',
        tabId: map['tabId'] as String? ?? '',
        friendName: map['friendName'] as String? ?? '',
        description: map['description'] as String? ?? '',
        amountCentavos: (map['amountCentavos'] as num?)?.toInt() ?? 0,
        dueDate: map['dueDate'] != null
            ? (DateTime.tryParse(map['dueDate'] as String) ?? DateTime.now())
            : DateTime.now(),
        isIWhoOwe: map['isIWhoOwe'] as bool? ?? false,
      );
}

// ─── AppNotification ──────────────────────────────────────────────────────────

/// Represents a row from public.notifications in Supabase.
/// Used for the Notification Center — real DB-backed, not just local state.
@immutable
class AppNotification {
  final String id;
  final String recipientUserId;
  final String type; // maps to notification_type check constraint
  final String? relatedTabId;
  final String? relatedTransactionId;
  final String? relatedPaymentId;
  final String? relatedGroupId;
  final String title;
  final String body;
  final bool isRead;
  final DateTime createdAt;
  final DateTime? readAt;

  const AppNotification({
    required this.id,
    required this.recipientUserId,
    required this.type,
    this.relatedTabId,
    this.relatedTransactionId,
    this.relatedPaymentId,
    this.relatedGroupId,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    this.readAt,
  });

  /// Factory constructor from Supabase PostgREST row JSON.
  static AppNotification? fromSupabaseRow(Map<String, dynamic> row) {
    final id = row['id'];
    final recipientUserId = row['recipient_user_id'];
    final title = row['title'];
    final body = row['body'];
    final createdAtRaw = row['created_at'];
    if (id is! String ||
        recipientUserId is! String ||
        title is! String ||
        body is! String ||
        createdAtRaw is! String) {
      return null;
    }
    return AppNotification(
      id: id,
      recipientUserId: recipientUserId,
      type: row['notification_type'] as String? ?? 'manual_nudge',
      relatedTabId: row['related_tab_id'] as String?,
      relatedTransactionId: row['related_transaction_id'] as String?,
      relatedPaymentId: row['related_payment_id'] as String?,
      relatedGroupId: row['related_group_id'] as String?,
      title: title,
      body: body,
      isRead: row['is_read'] as bool? ?? false,
      createdAt: DateTime.tryParse(createdAtRaw) ?? DateTime.now(),
      readAt: row['read_at'] != null
          ? DateTime.tryParse(row['read_at'] as String)
          : null,
    );
  }

  AppNotification copyWith({bool? isRead, DateTime? readAt}) => AppNotification(
        id: id,
        recipientUserId: recipientUserId,
        type: type,
        relatedTabId: relatedTabId,
        relatedTransactionId: relatedTransactionId,
        relatedPaymentId: relatedPaymentId,
        relatedGroupId: relatedGroupId,
        title: title,
        body: body,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt,
        readAt: readAt ?? this.readAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'recipientUserId': recipientUserId,
        'type': type,
        'relatedTabId': relatedTabId,
        'relatedTransactionId': relatedTransactionId,
        'relatedPaymentId': relatedPaymentId,
        'relatedGroupId': relatedGroupId,
        'title': title,
        'body': body,
        'isRead': isRead,
        'createdAt': createdAt.toIso8601String(),
        'readAt': readAt?.toIso8601String(),
      };

  factory AppNotification.fromMap(Map<String, dynamic> map) => AppNotification(
        id: map['id'] as String? ?? '',
        recipientUserId: map['recipientUserId'] as String? ?? '',
        type: map['type'] as String? ?? 'general',
        relatedTabId: map['relatedTabId'] as String?,
        relatedTransactionId: map['relatedTransactionId'] as String?,
        relatedPaymentId: map['relatedPaymentId'] as String?,
        relatedGroupId: map['relatedGroupId'] as String?,
        title: map['title'] as String? ?? '',
        body: map['body'] as String? ?? '',
        isRead: map['isRead'] as bool? ?? false,
        createdAt: map['createdAt'] != null
            ? (DateTime.tryParse(map['createdAt'] as String) ?? DateTime.now())
            : DateTime.now(),
        readAt: map['readAt'] != null
            ? DateTime.tryParse(map['readAt'] as String)
            : null,
      );
}
