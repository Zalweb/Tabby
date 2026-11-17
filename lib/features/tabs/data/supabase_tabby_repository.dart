import 'ledger_page_loader.dart';
import '../../../core/utils/philippine_phone.dart';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/config/session_scope.dart';
import '../../../core/services/tabby_notification_service.dart';
import '../../../core/services/auth_email_assistance.dart';
import '../../auth/application/profile_setup_draft.dart';
import '../../../core/services/qr_image_validator.dart';
import '../domain/models.dart';
import '../../payment_methods/domain/payment_method.dart' as payment_models;
import 'mock_tabby_repository.dart';
import 'tabby_local_cache.dart';
import 'durable_money_executor.dart';

class GoogleSignInClientConfiguration {
  final String? clientId;
  final String serverClientId;

  const GoogleSignInClientConfiguration({
    required this.clientId,
    required this.serverClientId,
  });
}

enum GoogleSignInFlow { authenticated, browserOpened, cancelled }

class GoogleSignInResult {
  const GoogleSignInResult.authenticated(Session authenticatedSession)
    : flow = GoogleSignInFlow.authenticated,
      session = authenticatedSession;
  const GoogleSignInResult.browserOpened()
    : flow = GoogleSignInFlow.browserOpened,
      session = null;
  const GoogleSignInResult.cancelled()
    : flow = GoogleSignInFlow.cancelled,
      session = null;

  final GoogleSignInFlow flow;
  final Session? session;
}

GoogleSignInClientConfiguration googleSignInClientConfiguration({
  required TargetPlatform platform,
  required String iosClientId,
  required String webClientId,
}) {
  return GoogleSignInClientConfiguration(
    clientId: platform == TargetPlatform.iOS ? iosClientId : null,
    serverClientId: webClientId,
  );
}

/// Live Supabase Repository for Tabby.
/// Communicates with Supabase PostgreSQL 15+ backend via PostgREST and GoTrue.
/// Falls back to MockTabbyRepository only when Supabase is not initialized (unit tests / offline).
class SupabaseTabbyRepository {
  SupabaseTabbyRepository._();
  static final SupabaseTabbyRepository instance = SupabaseTabbyRepository._();

  bool get isConnected => SupabaseConfig.isInitialized;

  /// Returns true when an OAuth-created account still needs profile details.
  ///
  /// Google provides the account identity and usually a display name, but it
  /// does not provide the user's Philippine mobile number to Tabby. The
  /// mobile number is required for friend matching and account recovery.
  static bool profileNeedsCompletion(Map<String, dynamic>? profile) {
    if (profile == null) return true;

    final displayName = (profile['display_name'] as String? ?? '').trim();
    final phone = (profile['phone'] as String? ?? '').trim();
    return displayName.isEmpty || phone.isEmpty;
  }

  /// Checks whether [userId] must complete the OAuth profile setup step.
  Future<bool?> requiresProfileCompletion(String userId) async {
    if (!isConnected || !_isValidUuid(userId)) return null;

    try {
      if (await ProfileSetupDraft.requiresCompletion(userId)) return true;
      final profile = await SupabaseConfig.client
          .from(SupabaseConfig.tableUsers)
          .select('display_name, phone')
          .eq('id', userId)
          .maybeSingle();

      if (!profileNeedsCompletion(profile)) return false;

      // Email signups store the requested phone in auth metadata until the
      // profile trigger or the first authenticated sync persists it.
      final metadata = SupabaseConfig.currentUser?.userMetadata ?? {};
      final profileName = profile?['display_name'] as String?;
      final profilePhone = profile?['phone'] as String?;
      final mergedProfile = <String, dynamic>{
        ...?profile,
        'display_name': profileName?.trim().isNotEmpty == true
            ? profileName
            : metadata['display_name'] ?? metadata['name'],
        'phone': profilePhone?.trim().isNotEmpty == true
            ? profilePhone
            : metadata['phone'],
      };
      return profileNeedsCompletion(mergedProfile);
    } catch (e) {
      debugPrint(
        '[SupabaseTabbyRepository] Profile completion check error: $e',
      );
      return null;
    }
  }

  /// Maps the sanitized flat row returned by friend-request RPCs.
  ///
  /// This is intentionally public so the PostgREST boundary can be tested
  /// without opening a live Supabase session.
  static FriendRequest parseFriendRequestRow(
    Map<String, dynamic> row, {
    String? currentUserId,
  }) {
    return FriendRequest.fromMap(row, currentUserId: currentUserId);
  }

  static Map<String, dynamic>? _responseMap(dynamic response) {
    if (response is Map) {
      return Map<String, dynamic>.from(response);
    }
    if (response is List && response.isNotEmpty && response.first is Map) {
      return Map<String, dynamic>.from(response.first as Map);
    }
    return null;
  }

  /// Looks up a registered account by its exact, shareable Tabby ID.
  Future<TabbyUser?> findUserByFriendCode(String friendCode) async {
    final session = SupabaseConfig.captureSession();
    if (!isConnected) return null;
    final normalized = normalizeFriendCode(friendCode);
    if (normalized == null) return null;

    try {
      final response = await SupabaseConfig.client.rpc(
        SupabaseConfig.rpcFindUserByFriendCode,
        params: {'p_friend_code': normalized},
      );
      if (!SupabaseConfig.isCurrentSession(session)) return null;
      final row = _responseMap(response);
      return row == null ? null : TabbyUser.fromMap(row);
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] findUserByFriendCode error: $e');
      return null;
    }
  }

  /// Sends a pending friend request using a shareable Tabby ID.
  Future<FriendRequest?> sendFriendRequest({required String friendCode}) async {
    final session = SupabaseConfig.captureSession();
    if (!isConnected) return null;
    final normalized = normalizeFriendCode(friendCode);
    if (normalized == null) return null;

    try {
      final response = await SupabaseConfig.client.rpc(
        SupabaseConfig.rpcSendFriendRequest,
        params: {'p_friend_code': normalized},
      );
      if (!SupabaseConfig.isCurrentSession(session)) return null;
      final row = _responseMap(response);
      if (row == null ||
          row['requester_id'] != session.accountId ||
          row['status'] != 'pending' ||
          row['id'] is! String ||
          !_isValidUuid(row['id'] as String) ||
          row['addressee_id'] is! String ||
          !_isValidUuid(row['addressee_id'] as String) ||
          row['addressee_id'] == session.accountId) {
        return null;
      }
      return parseFriendRequestRow(row, currentUserId: session.accountId);
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] sendFriendRequest error: $e');
      return null;
    }
  }

  /// Loads requests involving the authenticated user.
  Future<List<FriendRequest>> fetchFriendRequests(String currentUserId) async {
    final session = SupabaseConfig.captureSession();
    if (!isConnected || !_isValidUuid(currentUserId)) return [];
    if (session.accountId != currentUserId) return [];

    try {
      final response = await SupabaseConfig.client.rpc(
        SupabaseConfig.rpcListFriendRequests,
      );
      if (!SupabaseConfig.isCurrentSession(session)) return [];
      if (response is! List) return [];
      return response
          .whereType<Map>()
          .map(
            (row) => parseFriendRequestRow(
              Map<String, dynamic>.from(row),
              currentUserId: currentUserId,
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] fetchFriendRequests error: $e');
      return [];
    }
  }

  /// Accepts or declines a request. Accept returns the canonical tab ID.
  Future<String?> respondToFriendRequest({
    required String friendshipId,
    required bool accept,
  }) async {
    final session = SupabaseConfig.captureSession();
    if (!isConnected || !_isValidUuid(friendshipId)) return null;

    try {
      final response = await SupabaseConfig.client.rpc(
        SupabaseConfig.rpcRespondFriendRequest,
        params: {'p_friendship_id': friendshipId, 'p_accept': accept},
      );
      if (!SupabaseConfig.isCurrentSession(session)) return null;
      final row = _responseMap(response);
      if (row == null ||
          row['request_id'] != friendshipId ||
          row['status'] != (accept ? 'accepted' : 'declined')) {
        return null;
      }
      final tabId = row['tab_id'];
      if (tabId is! String ||
          (accept ? !_isValidUuid(tabId) : tabId.isNotEmpty)) {
        return null;
      }
      return tabId;
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] respondToFriendRequest error: $e');
      return null;
    }
  }

  /// Removes an accepted social friendship without touching any financial tab.
  Future<bool> removeFriend({required String friendUserId}) async {
    final session = SupabaseConfig.captureSession();
    if (!isConnected ||
        session.accountId == null ||
        !_isValidUuid(friendUserId)) {
      return false;
    }

    try {
      final response = await SupabaseConfig.client.rpc(
        'remove_friend_v2',
        params: {
          'p_expected_owner': session.accountId,
          'p_friend_user_id': friendUserId,
        },
      );
      if (!SupabaseConfig.isCurrentSession(session)) return false;
      if (response is bool) return response;
      if (response is Map) return response['removed'] as bool? ?? false;
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] removeFriend error: $e');
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Category mapping helpers (DB uses snake_case)
  // ---------------------------------------------------------------------------
  String _mapCategory(ExpenseCategory category) {
    switch (category) {
      case ExpenseCategory.food:
        return 'food';
      case ExpenseCategory.transportation:
        return 'transportation';
      case ExpenseCategory.borrowedCash:
        return 'borrowed_cash';
      case ExpenseCategory.bills:
        return 'bills';
      case ExpenseCategory.groceries:
        return 'groceries';
      case ExpenseCategory.other:
        return 'other';
    }
  }

  ExpenseCategory _unmapCategory(dynamic catStr) {
    switch ((catStr as String? ?? '').toLowerCase()) {
      case 'food':
        return ExpenseCategory.food;
      case 'transportation':
        return ExpenseCategory.transportation;
      case 'borrowed_cash':
        return ExpenseCategory.borrowedCash;
      case 'bills':
        return ExpenseCategory.bills;
      case 'groceries':
        return ExpenseCategory.groceries;
      default:
        return ExpenseCategory.other;
    }
  }

  // ---------------------------------------------------------------------------
  // Payment method mapping helpers
  // ---------------------------------------------------------------------------
  String _mapPaymentMethod(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.gcash:
        return 'gcash';
      case PaymentMethod.maya:
        return 'maya';
      case PaymentMethod.cash:
        return 'cash';
      case PaymentMethod.bankTransfer:
        return 'bank_transfer';
      case PaymentMethod.other:
        return 'other';
    }
  }

  PaymentMethod _unmapPaymentMethod(dynamic methodStr) {
    switch ((methodStr as String? ?? '').toLowerCase()) {
      case 'gcash':
        return PaymentMethod.gcash;
      case 'maya':
        return PaymentMethod.maya;
      case 'cash':
        return PaymentMethod.cash;
      case 'bank_transfer':
        return PaymentMethod.bankTransfer;
      default:
        return PaymentMethod.other;
    }
  }

  TransactionStatus _unmapTransactionStatus(dynamic statusStr) {
    switch ((statusStr as String? ?? '').toLowerCase()) {
      case 'settled':
        return TransactionStatus.settled;
      case 'payment_submitted':
        return TransactionStatus.paymentSubmitted;
      case 'cancelled':
        return TransactionStatus.cancelled;
      case 'disputed':
        return TransactionStatus.disputed;
      case 'acknowledged':
        return TransactionStatus.acknowledged;
      default:
        return TransactionStatus.pending;
    }
  }

  // ---------------------------------------------------------------------------
  // UUID validation helper
  // ---------------------------------------------------------------------------
  static final _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  bool _isValidUuid(String id) => _uuidRegex.hasMatch(id);

  // Static testing & mapping helpers
  static String mapCategory(ExpenseCategory category) =>
      instance._mapCategory(category);
  static ExpenseCategory unmapCategory(dynamic catStr) =>
      instance._unmapCategory(catStr);
  static String mapPaymentMethod(PaymentMethod method) =>
      instance._mapPaymentMethod(method);
  static PaymentMethod unmapPaymentMethod(dynamic methodStr) =>
      instance._unmapPaymentMethod(methodStr);
  static TransactionStatus unmapTransactionStatus(dynamic statusStr) =>
      instance._unmapTransactionStatus(statusStr);
  static bool isValidUuid(String id) => _uuidRegex.hasMatch(id);

  /// Parses a raw Supabase PostgREST tab query row into a [BilateralTab].
  /// Returns `null` if row is missing essential fields or counterpart member cannot be resolved.
  static BilateralTab? parseTabRow(
    Map<String, dynamic> tabRow,
    String currentUserId, {
    int? netBalance,
  }) {
    final tabId = tabRow['id'] as String? ?? '';
    if (tabId.isEmpty) return null;

    final isGroup =
        (tabRow['tab_type'] as String?) == 'group' ||
        tabRow['group_id'] != null ||
        tabRow['groups'] != null;

    final groupData = tabRow['groups'] as Map<String, dynamic>?;
    final groupName =
        groupData?['name'] as String? ??
        tabRow['group_name'] as String? ??
        'Group Tab';

    // Find counterpart member (anyone who is not the current user) and build member lookup map
    final membersList = (tabRow['tab_members'] as List<dynamic>?) ?? [];
    final Map<String, String> memberNameById = {};
    Map<String, dynamic>? counterpartMember;
    for (final m in membersList) {
      final mMap = m as Map<String, dynamic>;
      final mUserId = mMap['user_id'] as String?;
      final mContactId = mMap['contact_id'] as String?;
      final mId = (mUserId != null && mUserId.isNotEmpty)
          ? mUserId
          : (mContactId ?? '');
      final mUser = mMap['users'] as Map<String, dynamic>?;
      final mContact = mMap['contacts'] as Map<String, dynamic>?;
      if (mId.isNotEmpty) {
        final rawMeta = mUser?['raw_user_meta_data'] as Map<String, dynamic>?;
        final dName =
            (mUser?['display_name'] ??
                    rawMeta?['display_name'] ??
                    mUser?['name'] ??
                    mContact?['display_name'] ??
                    mMap['name'])
                as String? ??
            '';
        if (dName.isNotEmpty) {
          memberNameById[mId] = dName;
        }
      }
      if (mId != currentUserId && counterpartMember == null) {
        counterpartMember = mMap;
      }
    }

    if (counterpartMember == null && !isGroup) {
      final userA = tabRow['user_a'] as String?;
      final userB = tabRow['user_b'] as String?;
      final fallbackCounterpartId = (userA != null && userA != currentUserId)
          ? userA
          : (userB != null && userB != currentUserId ? userB : null);
      if (fallbackCounterpartId != null && fallbackCounterpartId.isNotEmpty) {
        counterpartMember = {
          'user_id': fallbackCounterpartId,
          'users': {
            'display_name': memberNameById[fallbackCounterpartId] ?? 'Friend',
          },
        };
      }
    }

    if (counterpartMember == null && !isGroup) return null;

    final isTabOnlyParticipant =
        !isGroup &&
        counterpartMember?['contact_id'] is String &&
        (counterpartMember?['contact_id'] as String).isNotEmpty &&
        counterpartMember?['user_id'] == null;

    final TabbyUser counterpart;
    if (isGroup) {
      final groupId = tabRow['group_id'] as String? ?? tabId;
      counterpart = TabbyUser(
        id: groupId,
        displayName: groupName,
        email: '',
        phone: '',
      );
    } else {
      final counterpartUserId =
          (counterpartMember!['user_id'] ?? counterpartMember['contact_id'])
              as String? ??
          '';
      final counterpartUserRow =
          (counterpartMember['users'] ?? counterpartMember['contacts'])
              as Map<String, dynamic>?;

      counterpart = TabbyUser(
        id: counterpartUserId,
        displayName: counterpartUserRow?['display_name'] as String? ?? 'Friend',
        email: counterpartUserRow?['email'] as String? ?? '',
        phone: counterpartUserRow?['phone'] as String? ?? '',
        friendCode: counterpartUserRow?['friend_code'] as String?,
      );
    }

    // Build ledger entries from transactions
    final List<LedgerEntry> entries = [];

    final txList = (tabRow['transactions'] as List<dynamic>?) ?? [];
    for (final txRaw in txList) {
      final tx = txRaw as Map<String, dynamic>;
      final pList =
          (tx['transaction_participants'] as List<dynamic>?) ??
          (tx['transaction_splits'] as List<dynamic>?) ??
          [];
      int myShare = 0;
      int counterpartShare = 0;
      String? actualPayerId;

      for (final pRaw in pList) {
        final p = pRaw as Map<String, dynamic>;
        final pUserId = (p['user_id'] ?? p['contact_id']) as String?;
        final shareAmt = (p['share_amount_centavos'] as num?)?.toInt() ?? 0;
        final role = p['participant_role'] as String?;
        if (role == 'payer' && pUserId != null && pUserId.isNotEmpty) {
          actualPayerId = pUserId;
        }
        if (pUserId == currentUserId) {
          myShare = shareAmt;
        } else {
          counterpartShare += shareAmt;
        }
      }

      final dateStr = tx['created_at'] as String?;
      final dueDateStr = tx['due_date'] as String?;
      final totalAmt = (tx['total_amount_centavos'] as num?)?.toInt() ?? 0;
      final createdBy = (tx['created_by'] ?? tx['paid_by']) as String? ?? '';
      final payerId = actualPayerId ?? (tx['paid_by'] as String?) ?? createdBy;

      // If no participants were recorded, fall back to payer-debtor calculation
      if (pList.isEmpty) {
        if (payerId == currentUserId) {
          myShare = 0;
          counterpartShare = totalAmt;
        } else {
          myShare = totalAmt;
          counterpartShare = 0;
        }
      }

      final isMePayer = payerId == currentUserId;
      final payerName = isMePayer
          ? 'You'
          : (memberNameById[payerId] ?? counterpart.displayName);

      final revisions = [
        ...?(tx['transaction_receipt_revisions'] as List<dynamic>?),
      ];
      revisions.sort(
        (a, b) => ((a as Map)['uploaded_at'] as String? ?? '').compareTo(
          (b as Map)['uploaded_at'] as String? ?? '',
        ),
      );
      final receipts = <String>{
        if (tx['receipt_url'] is String &&
            (tx['receipt_url'] as String).isNotEmpty)
          tx['receipt_url'] as String,
        for (final revision in revisions)
          (revision as Map)['storage_path'] as String,
      }.toList();
      entries.add(
        LedgerEntry(
          revision: tx['expense_revision'] == null
              ? null
              : ExpenseRevision.fromMap(
                  Map<String, dynamic>.from(tx['expense_revision'] as Map),
                ),
          receiptHistory: receipts,
          id: tx['id'] as String? ?? 'tx-$tabId',
          participants: pList.map((raw) {
            final p = Map<String, dynamic>.from(raw as Map);
            final id = (p['user_id'] ?? p['contact_id']) as String? ?? '';
            return ParticipantShare(
              userId: id,
              name: memberNameById[id] ?? 'Member',
              shareAmountCentavos:
                  (p['share_amount_centavos'] as num?)?.toInt() ?? 0,
              isPayer: p['participant_role'] == 'payer',
              acknowledged: p['acknowledged'] == true,
            );
          }).toList(),
          tabId: tabId,
          title: (tx['description'] ?? tx['title']) as String? ?? '',
          category: unmapCategory(tx['category']),
          totalAmountCentavos: totalAmt,
          myShareCentavos: myShare,
          counterpartShareCentavos: counterpartShare,
          paidByUserId: payerId,
          paidByName: payerName,
          date: dateStr != null
              ? DateTime.tryParse(dateStr) ?? DateTime.now()
              : DateTime.now(),
          dueDate: dueDateStr != null ? DateTime.tryParse(dueDateStr) : null,
          status: unmapTransactionStatus(tx['status']),
          receiptUrl: receipts.isNotEmpty
              ? receipts.last
              : tx['payment_proof_url'] as String?,
        ),
      );
    }

    // Build ledger entries from payments
    final payList = (tabRow['payments'] as List<dynamic>?) ?? [];
    for (final payRaw in payList) {
      final pay = payRaw as Map<String, dynamic>;
      final submittedBy =
          (pay['payer_contact_id'] ??
                  pay['payer_user_id'] ??
                  pay['submitted_by'])
              as String? ??
          '';
      final recipientId =
          (pay['recipient_contact_id'] ??
                  pay['recipient_user_id'] ??
                  pay['confirmed_by'])
              as String?;
      final isMePaying = submittedBy == currentUserId;
      final payerName = isMePaying
          ? 'You'
          : (memberNameById[submittedBy] ??
                (isGroup ? 'Group Member' : counterpart.displayName));
      final dateStr = (pay['submitted_at'] ?? pay['created_at']) as String?;
      final payAmt = (pay['amount_centavos'] as num?)?.toInt() ?? 0;

      final proofList = [...?(pay['payment_proofs'] as List<dynamic>?)];
      proofList.sort(
        (a, b) => ((b as Map)['uploaded_at'] as String? ?? '').compareTo(
          (a as Map)['uploaded_at'] as String? ?? '',
        ),
      );
      final proofUrl = proofList
          .where(
            (raw) => ((raw as Map)['file_url'] as String?)?.isNotEmpty == true,
          )
          .map((raw) => (raw as Map)['file_url'] as String)
          .firstOrNull;
      final receiptUrl =
          proofUrl ??
          (pay['payment_proof_url'] ?? pay['receipt_url']) as String?;
      // Only a confirmed payment clears the obligation; submitted and legacy
      // statuses stay pending until the recipient confirms them.
      final paymentStatus = switch (pay['status']) {
        'confirmed' => TransactionStatus.settled,
        'rejected' => TransactionStatus.cancelled,
        _ => TransactionStatus.paymentSubmitted,
      };

      entries.add(
        LedgerEntry(
          id: pay['id'] as String? ?? 'pay-$tabId',
          receiptHistory: proofList.reversed
              .where(
                (raw) =>
                    ((raw as Map)['file_url'] as String?)?.isNotEmpty == true,
              )
              .map((raw) => (raw as Map)['file_url'] as String)
              .toSet()
              .toList(),
          rejectionReason: pay['rejection_reason'] as String?,
          paymentReference: proofList.isEmpty
              ? null
              : (proofList.first as Map)['reference'] as String?,
          tabId: tabId,
          title: isMePaying ? 'You paid' : '$payerName paid',
          category: ExpenseCategory.borrowedCash,
          totalAmountCentavos: payAmt,
          myShareCentavos: 0,
          counterpartShareCentavos: 0,
          paidByUserId: submittedBy,
          payer: PartyRef(
            kind: pay['payer_contact_id'] != null
                ? PartyKind.contact
                : PartyKind.user,
            id: submittedBy,
          ),
          recipient: recipientId == null
              ? null
              : PartyRef(
                  kind: pay['recipient_contact_id'] != null
                      ? PartyKind.contact
                      : PartyKind.user,
                  id: recipientId,
                ),
          paidByName: payerName,
          date: dateStr != null
              ? DateTime.tryParse(dateStr) ?? DateTime.now()
              : DateTime.now(),
          status: paymentStatus,
          isPayment: true,
          paymentMethod: unmapPaymentMethod(pay['payment_method']),
          note: pay['note'] as String?,
          receiptUrl: receiptUrl,
        ),
      );
    }

    // Deduplicate entries newest-first
    final cleanEntries = MockTabbyRepository.deduplicateLedgerEntries(entries);

    final lastUpdatedStr =
        tabRow['updated_at'] as String? ?? tabRow['created_at'] as String?;

    final effectiveNetBalance =
        netBalance ??
        MockTabbyRepository.calculateNetBalance(cleanEntries, currentUserId);

    return BilateralTab(
      id: tabId,
      members: isGroup
          ? membersList.where((raw) => (raw as Map)['user_id'] != null).map((
              raw,
            ) {
              final m = Map<String, dynamic>.from(raw as Map);
              final id = m['user_id'] as String;
              return TabbyUser(
                id: id,
                displayName: memberNameById[id] ?? 'Member',
                email: '',
                phone: '',
              );
            }).toList()
          : const [],
      counterpart: counterpart,
      netBalanceCentavos: effectiveNetBalance,
      itemCount: cleanEntries.length,
      entries: cleanEntries,
      lastUpdated: lastUpdatedStr != null
          ? DateTime.tryParse(lastUpdatedStr) ?? DateTime.now()
          : DateTime.now(),
      isGroupTab: isGroup,
      groupName: isGroup ? groupName : null,
      isTabOnlyParticipant: isTabOnlyParticipant,
    );
  }

  /// Ensures a user row exists in public.users.
  /// For real UUID IDs, upserts the record if it is the current user.
  /// For synthetic IDs (non-UUID), looks up user by display_name.
  Future<String> ensureUserExists(String id, String displayName) async {
    if (!isConnected) return id;

    final currentUserId = SupabaseConfig.currentUserId;
    if (_isValidUuid(id)) {
      // Only upsert self to respect RLS policy auth.uid() = id
      if (currentUserId != null && id == currentUserId) {
        try {
          await SupabaseConfig.client.from(SupabaseConfig.tableUsers).upsert({
            'id': id,
            'display_name': displayName,
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'id');
        } catch (e) {
          debugPrint(
            '[SupabaseTabbyRepository] ensureUserExists upsert warning: $e',
          );
        }
      }
      return id;
    }

    // Synthetic ID: find by display_name if exists
    try {
      final existing = await SupabaseConfig.client
          .from(SupabaseConfig.tableUsers)
          .select('id')
          .ilike('display_name', displayName)
          .limit(1)
          .maybeSingle();
      if (existing != null && existing['id'] != null) {
        return existing['id'] as String;
      }
    } catch (e) {
      debugPrint(
        '[SupabaseTabbyRepository] ensureUserExists synthetic warning: $e',
      );
    }
    return id;
  }

  /// Fetches profile of [userId] from Supabase public.users
  Future<TabbyUser?> fetchUserProfile(String userId) async {
    if (!isConnected || !_isValidUuid(userId)) return null;

    try {
      final data = await SupabaseConfig.client
          .from(SupabaseConfig.tableUsers)
          .select('*')
          .eq('id', userId)
          .maybeSingle();

      final authUser = SupabaseConfig.currentUser;
      final meta = authUser?.userMetadata ?? {};

      if (data != null) {
        final displayName =
            (data['display_name'] as String?)?.isNotEmpty == true
            ? data['display_name'] as String
            : (meta['display_name'] as String?)?.isNotEmpty == true
            ? meta['display_name'] as String
            : (authUser?.email?.split('@').first ?? 'User');

        return TabbyUser(
          id: userId,
          displayName: displayName,
          email: authUser?.id == userId
              ? authUser?.email ?? ''
              : (data['email'] as String? ?? ''),
          phone: (data['phone'] as String?) ?? (meta['phone'] as String?) ?? '',
          avatarUrl:
              data['avatar_url'] as String? ?? meta['avatar_url'] as String?,
          gcashNumber: (data['gcash_number'] as String?) ?? '',
          mayaNumber: (data['maya_number'] as String?) ?? '',
          qrCodeUrl: data['qr_code_url'] as String?,
          friendCode: data['friend_code'] as String?,
        );
      }
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] fetchUserProfile error: $e');
    }
    return null;
  }

  /// Checks whether [phone] is available or already linked to another user.
  Future<bool> isPhoneAvailable({
    required String phone,
    String? currentUserId,
  }) async {
    final normalized = normalizePhilippineMobile(phone);
    if (normalized == null) return false;
    if (!isConnected) return true;

    try {
      final res = await SupabaseConfig.client.rpc(
        'is_phone_available',
        params: {
          'p_phone': normalized,
          if (currentUserId != null && _isValidUuid(currentUserId))
            'p_user_id': currentUserId,
        },
      );
      if (res is bool) return res;
      return true;
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] isPhoneAvailable error: $e');
      return true;
    }
  }

  /// Saves core details through an owner-scoped RPC and requires its returned row.
  /// Email belongs to Auth; receiving destinations belong to saved methods.
  Future<ProfileUpdateResult> updateUserProfile({
    required String userId,
    String? displayName,
    String? phone,
    String? avatarUrl,
  }) async {
    final session = SupabaseConfig.captureSession();
    if (!isConnected || session.accountId != userId || !_isValidUuid(userId)) {
      return ProfileUpdateResult.failure;
    }
    try {
      final updates = <String, dynamic>{};
      if (displayName != null) updates['display_name'] = displayName.trim();
      if (phone != null) {
        final normalized = normalizePhilippineMobile(phone);
        if (normalized == null) {
          return const ProfileUpdateResult(
            isSuccess: false,
            errorMessage: 'Enter a valid Philippine mobile number.',
          );
        }
        updates['phone'] = normalized;
      }
      if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
      final response = await SupabaseConfig.client.rpc(
        'update_profile_v2',
        params: {'p_expected_owner': userId, 'p_changes': updates},
      );
      if (!SupabaseConfig.isCurrentSession(session)) {
        return ProfileUpdateResult.failure;
      }
      final row = _responseMap(response);
      if (row == null || row['id'] != userId) {
        return ProfileUpdateResult.failure;
      }
      return ProfileUpdateResult(
        isSuccess: true,
        user: TabbyUser.fromMap(row)
            .copyWith(email: SupabaseConfig.currentUser?.email ?? ''),
      );
    } catch (error) {
      if (error is PostgrestException && error.code == '23505') {
        return const ProfileUpdateResult(
          isSuccess: false,
          isDuplicatePhone: true,
          errorMessage:
              'This mobile number is already linked to another Tabby account.',
        );
      }
      return const ProfileUpdateResult(
        isSuccess: false,
        errorMessage: 'Profile could not be saved. Your edits are still here. Please retry.',
      );
    }
  }

  /// Downloads an active method through current row/object authorization.
  Future<Uint8List> downloadReceivingQr(String methodId) async {
    final session = SupabaseConfig.captureSession();
    if (!isConnected || session.accountId == null || !_isValidUuid(methodId)) {
      throw StateError('Sign in to download a receiving QR.');
    }
    final row = await SupabaseConfig.client
        .from(SupabaseConfig.tablePaymentMethods)
        .select('qr_storage_path')
        .eq('id', methodId)
        .eq('is_active', true)
        .maybeSingle();
    if (!SupabaseConfig.isCurrentSession(session)) {
      throw StateError('Account changed.');
    }
    final path = row?['qr_storage_path'] as String?;
    if (path == null || path.isEmpty || path.startsWith('http')) {
      throw StateError('Ask the recipient to upload a private receiving QR.');
    }
    final bytes = await SupabaseConfig.paymentMethodsBucket.download(
      path,
      cacheNonce: const Uuid().v4(),
    );
    if (!SupabaseConfig.isCurrentSession(session)) {
      throw StateError('Account changed.');
    }
    return bytes;
  }

  /// Loads methods visible to the current authenticated caller.
  Future<List<payment_models.PaymentMethod>> fetchPaymentMethods(
    String ownerUserId,
  ) async {
    if (!isConnected || !_isValidUuid(ownerUserId)) return const [];

    try {
      final rows = await SupabaseConfig.client
          .from(SupabaseConfig.tablePaymentMethods)
          .select('*')
          .eq('owner_user_id', ownerUserId);
      return await _signedPaymentMethods(
        (rows as List)
            .whereType<Map>()
            .map(
              (row) => payment_models.PaymentMethod.fromMap(
                Map<String, dynamic>.from(row),
              ),
            )
            .toList(),
      );
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] fetchPaymentMethods error: $e');
      rethrow;
    }
  }

  /// Upload first, then atomically switch metadata and preference on the server.
  Future<payment_models.PaymentMethod?> createPaymentMethod({
    required String ownerUserId,
    required payment_models.PaymentMethodDraft draft,
    required bool makeDefault,
  }) => _savePaymentMethod(
    ownerUserId: ownerUserId,
    draft: draft,
    methodId: draft.methodId ?? const Uuid().v4(),
    makeDefault: makeDefault,
  );

  Future<payment_models.PaymentMethod?> updatePaymentMethod({
    required payment_models.PaymentMethod current,
    required payment_models.PaymentMethodDraft draft,
  }) => _savePaymentMethod(
    ownerUserId: current.ownerUserId,
    draft: draft,
    methodId: current.id,
    makeDefault: current.isDefault,
    previous: current,
  );

  Future<payment_models.PaymentMethod?> _savePaymentMethod({
    required String ownerUserId,
    required payment_models.PaymentMethodDraft draft,
    required String methodId,
    required bool makeDefault,
    payment_models.PaymentMethod? previous,
  }) async {
    final session = SupabaseConfig.captureSession();
    if (!isConnected ||
        !_isValidUuid(ownerUserId) ||
        !draft.isValid ||
        ownerUserId != session.accountId) {
      return null;
    }
    final operationId = draft.operationId ?? const Uuid().v4();
    String? newPath;
    try {
      if (draft.hasQr) {
        final prepared = await QrImageValidator.prepare(draft.qrBytes!);
        if (!SupabaseConfig.isCurrentSession(session)) return null;
        newPath = '$ownerUserId/$methodId/$operationId.png';
        try {
          await SupabaseConfig.paymentMethodsBucket.uploadBinary(
            newPath,
            prepared.bytes,
            fileOptions: const FileOptions(
              contentType: 'image/png',
              upsert: false,
            ),
          );
        } on StorageException catch (error) {
          // A retry uses the same immutable path. Never overwrite the prior QR.
          if (error.statusCode != '409' && error.error != 'Duplicate') rethrow;
        }
      }
      if (!SupabaseConfig.isCurrentSession(session)) return null;
      final result = await SupabaseConfig.client.rpc(
        'change_payment_method_v1',
        params: {
          'p_operation_id': operationId,
          'p_kind': 'save',
          'p_command': {
            'method_id': methodId,
            'expected_revision': previous?.revision,
            'provider': draft.provider.trim(),
            'display_name': draft.displayName.trim(),
            'account_label': draft.accountLabel.trim(),
            'qr_storage_path': newPath ?? previous?.qrStoragePath,
            'make_default': makeDefault,
          },
        },
      );
      if (!SupabaseConfig.isCurrentSession(session) || result is! Map) {
        return null;
      }
      final signed = await _signedPaymentMethods([
        payment_models.PaymentMethod.fromMap(Map<String, dynamic>.from(result)),
      ]);
      return SupabaseConfig.isCurrentSession(session) ? signed.single : null;
    } catch (error) {
      debugPrint('[SupabaseTabbyRepository] method save failed: $error');
      // Referenced revisions are protected by server policy, including when
      // the write committed but its response was lost.
      if (newPath != null && SupabaseConfig.isCurrentSession(session)) {
        try {
          await SupabaseConfig.paymentMethodsBucket.remove([newPath]);
        } catch (_) {}
      }
      return null;
    }
  }

  Future<bool> setPreferredPaymentMethod(String methodId) =>
      _changeMethod('prefer', methodId);
  Future<bool> deletePaymentMethod(String methodId) =>
      _changeMethod('remove', methodId);

  Future<bool> _changeMethod(String kind, String methodId) async {
    final session = SupabaseConfig.captureSession();
    if (!isConnected || session.accountId == null || !_isValidUuid(methodId)) {
      return false;
    }
    try {
      await SupabaseConfig.client.rpc(
        'change_payment_method_v1',
        params: {
          'p_operation_id': const Uuid().v4(),
          'p_kind': kind,
          'p_command': {'method_id': methodId},
        },
      );
      return SupabaseConfig.isCurrentSession(session);
    } catch (error) {
      debugPrint('[SupabaseTabbyRepository] method $kind failed: $error');
      return false;
    }
  }

  /// Returns only methods the authenticated caller is authorized to use in a tab.
  Future<List<payment_models.PaymentMethod>> fetchPaymentMethodsForTab({
    required String tabId,
    required String payeeUserId,
  }) async {
    if (!isConnected ||
        !_isValidUuid(tabId) ||
        !_isValidUuid(payeeUserId) ||
        SupabaseConfig.currentUserId == payeeUserId) {
      return const [];
    }

    try {
      final rows = await SupabaseConfig.client.rpc(
        SupabaseConfig.rpcListPaymentMethodsForTab,
        params: {'p_tab_id': tabId, 'p_payee_user_id': payeeUserId},
      );
      if (rows is! List) return const [];
      return await _signedPaymentMethods(
        rows
            .whereType<Map>()
            .map(
              (row) => payment_models.PaymentMethod.fromMap(
                Map<String, dynamic>.from(row),
              ),
            )
            .toList(),
      );
    } catch (e) {
      debugPrint(
        '[SupabaseTabbyRepository] fetchPaymentMethodsForTab error: $e',
      );
      rethrow;
    }
  }

  Future<List<payment_models.PaymentMethod>> _signedPaymentMethods(
    List<payment_models.PaymentMethod> methods,
  ) async {
    final signed = <payment_models.PaymentMethod>[];
    for (final method in payment_models.PaymentMethod.defaultFirst(methods)) {
      final path = method.qrStoragePath;
      String? qrUrl = method.qrUrl;
      if (path != null && path.isNotEmpty) {
        if (path.startsWith('http')) {
          qrUrl = path;
        } else {
          try {
            qrUrl = await SupabaseConfig.paymentMethodsBucket.createSignedUrl(
              path,
              600,
            );
          } catch (_) {}
        }
      }
      signed.add(method.copyWith(qrUrl: qrUrl));
    }
    return signed;
  }

  /// Signs in with a Tabby email/password account.
  Future<AuthResponse?> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    if (!isConnected) return null;
    return SupabaseConfig.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Creates a Tabby email/password account and stores profile metadata on the
  /// Supabase auth user. The database trigger mirrors this metadata into
  /// public.users, including the contact number.
  Future<AuthResponse?> signUpWithEmailPassword({
    required String email,
    required String password,
    required String displayName,
    required String phone,
  }) async {
    if (!isConnected) return null;
    return SupabaseConfig.auth.signUp(
      email: email.trim(),
      emailRedirectTo: authEmailRedirect,
      password: password,
      data: {
        'display_name': displayName.trim(),
        'phone':
            normalizePhilippineMobile(phone) ??
            (throw const FormatException('Invalid Philippine mobile number.')),
      },
    );
  }

  /// Sign in with Google OAuth. Browser launch is a pending handoff, not an
  /// authenticated session. Only native token exchange returns its exact Session.
  ///
  /// - **Web**: Uses Supabase's browser redirect OAuth flow.
  /// - **iOS / Android**: Uses the native Google Sign-In SDK to obtain an ID
  ///   token, then exchanges it with Supabase via `signInWithIdToken`.
  ///   This opens the native account picker sheet — no browser pop-up.
  Future<GoogleSignInResult> signInWithGoogle() async {
    if (!isConnected) return const GoogleSignInResult.cancelled();

    // ── Web: existing browser-redirect OAuth ─────────────────────────────────
    if (kIsWeb) {
      try {
        return await _openGoogleBrowser('${Uri.base.origin}/');
      } catch (e) {
        debugPrint('[SupabaseTabbyRepository] Google web sign-in error: $e');
        rethrow;
      }
    }

    // ── Native iOS / Android: native Google Sign-In SDK with web OAuth fallback ──
    const defaultIosGoogleClientId =
        '137141086000-qnr5kedgh9miig5mmaaq90efn90gckmm.apps.googleusercontent.com';
    const defaultWebGoogleClientId =
        '137141086000-p2o6c1hminjif8i5f739n3a6ils7ucmm.apps.googleusercontent.com';

    try {
      // Read compile-time client IDs or use platform-specific defaults.
      const iosClientId = String.fromEnvironment(
        'GOOGLE_IOS_CLIENT_ID',
        defaultValue: defaultIosGoogleClientId,
      );
      const webClientId = String.fromEnvironment(
        'GOOGLE_WEB_CLIENT_ID',
        defaultValue: defaultWebGoogleClientId,
      );

      // Android resolves its native client from the registered package/SHA-1.
      // The Web client is required as serverClientId for Supabase's ID-token
      // exchange.
      final clientConfiguration = googleSignInClientConfiguration(
        platform: defaultTargetPlatform,
        iosClientId: iosClientId.isNotEmpty
            ? iosClientId
            : defaultIosGoogleClientId,
        webClientId: webClientId.isNotEmpty
            ? webClientId
            : defaultWebGoogleClientId,
      );

      final googleSignIn = GoogleSignIn(
        clientId: clientConfiguration.clientId,
        serverClientId: clientConfiguration.serverClientId,
        scopes: ['email', 'profile'],
      );

      // Trigger native account picker
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        // User cancelled the picker
        debugPrint(
          '[SupabaseTabbyRepository] Google sign-in cancelled by user.',
        );
        return const GoogleSignInResult.cancelled();
      }

      // Obtain auth tokens from Google
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null) {
        debugPrint(
          '[SupabaseTabbyRepository] Native Google sign-in: idToken is null. Falling back to browser OAuth...',
        );
      } else {
        // Exchange Google token with Supabase → creates/updates session.
        final response = await SupabaseConfig.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
          accessToken: accessToken,
        );
        final session = response.session;
        if (session == null) {
          throw const AuthException('No Google session returned.');
        }
        debugPrint(
          '[SupabaseTabbyRepository] Native Google sign-in successful.',
        );
        return GoogleSignInResult.authenticated(session);
      }
    } catch (e) {
      debugPrint(
        '[SupabaseTabbyRepository] Native Google sign-in error: $e. Falling back to browser OAuth...',
      );
    }
    // A browser failure must reach the form, never retry through the native
    // catch and open a second browser attempt.
    return _openGoogleBrowser(_googleCallback);
  }

  static const _googleCallback = bool.fromEnvironment('TABBY_USB_TEST')
      ? 'io.supabase.tabby.usbtest://login-callback'
      : 'io.supabase.tabby://login-callback';

  Future<GoogleSignInResult> _openGoogleBrowser(String redirect) async {
    final opened = await SupabaseConfig.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: redirect,
    );
    if (!opened) {
      throw const AuthException('Could not open Google sign-in browser.');
    }
    return const GoogleSignInResult.browserOpened();
  }

  /// Sign out
  Future<void> signOut({SessionStamp? expectedSession}) async {
    final session = expectedSession ?? SupabaseConfig.captureSession();
    if (!SupabaseConfig.isCurrentSession(session)) return;
    try {
      await TabbyNotificationService.instance.logout(session);
    } catch (_) {
      // The account binding is invalidated synchronously even if the OS cancel
      // fails. A notification plugin failure must not prevent signing out.
      debugPrint('[SupabaseTabbyRepository] Device alert cancellation failed.');
    }
    if (!SupabaseConfig.isCurrentSession(session)) return;
    try {
      await TabbyLocalCache.clearCache(userId: session.accountId);
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] clearCache error: $e');
    }

    if (!isConnected || !SupabaseConfig.isCurrentSession(session)) return;
    try {
      await SupabaseConfig.auth.signOut();
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] Sign out error: $e');
    }
  }

  /// Searches for registered users by display name or email using sanitized RPC
  Future<List<TabbyUser>> searchUsers(String query) async {
    if (!isConnected || query.trim().isEmpty) return [];

    try {
      final res = await SupabaseConfig.client.rpc(
        'search_users',
        params: {'p_query': query.trim()},
      );

      if (res is List) {
        return res.map((r) {
          final row = r as Map<String, dynamic>;
          return TabbyUser(
            id: row['id'] as String? ?? '',
            displayName: row['display_name'] as String? ?? '',
            avatarUrl: row['avatar_url'] as String?,
            email: '',
            phone: '',
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] searchUsers error: $e');
    }
    return [];
  }

  // ---------------------------------------------------------------------------
  // Tab Fetching & Deserialization
  // ---------------------------------------------------------------------------

  /// Read-only identity lookup. Never call get-or-create while selecting people.
  Future<String?> findSharedTabId(String actorId, String otherUserId) async {
    if (!isConnected ||
        !_isValidUuid(actorId) ||
        !_isValidUuid(otherUserId) ||
        actorId == otherUserId) {
      throw StateError('Select a registered friend.');
    }
    final session = SupabaseConfig.captureSession();
    if (session.accountId != actorId) throw StateError('Account changed.');
    final id = await readSharedTabId(
      SupabaseConfig.client,
      actorId,
      otherUserId,
    );
    if (!SupabaseConfig.isCurrentSession(session)) {
      throw StateError('Account changed.');
    }
    return id;
  }

  @visibleForTesting
  static Future<String?> readSharedTabId(
    SupabaseClient client,
    String actorId,
    String otherUserId,
  ) async {
    if (!isValidUuid(actorId) ||
        !isValidUuid(otherUserId) ||
        actorId == otherUserId) {
      throw StateError('Select a registered friend.');
    }
    final rows = await client
        .from(SupabaseConfig.tableTabs)
        .select('id,status')
        .eq('tab_type', 'individual')
        .or(
          'and(user_a.eq.$actorId,user_b.eq.$otherUserId),and(user_a.eq.$otherUserId,user_b.eq.$actorId)',
        )
        .order('status', ascending: true)
        .limit(2);
    if (rows.isEmpty) return null;
    final active = rows.where((row) => row['status'] == 'active').toList();
    if (active.length != 1) {
      throw StateError(
        'This shared tab is unavailable. Open Tabs to review it.',
      );
    }
    return active.single['id'] as String;
  }

  /// Reads one bounded header page using the ledger's ID cursor contract.
  static Future<LedgerRows> fetchTabHeaderPage(
    SupabaseClient client,
    String? after,
    int limit,
  ) async {
    var query = client
        .from(SupabaseConfig.tableTabs)
        .select(
          'id,tab_type,group_id,status,created_at,updated_at,user_a,user_b,'
          'groups(id,name,avatar_url),'
          'tab_members(user_id,contact_id,users(id,display_name,email,phone,friend_code),'
          'contacts(id,display_name,email,phone))',
        )
        .neq('status', 'archived');
    if (after != null) query = query.gt('id', after);
    // Cursor continuation uses id > after, so both pages and rows must ascend.
    final result = await query.order('id', ascending: true).limit(limit);
    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  /// Fetches all bilateral tabs for [currentUserId] from Supabase.
  ///
  /// Returns an empty list when connected but no data exists yet.
  /// Falls back to mock data only when Supabase is not initialized (unit tests / offline).
  Future<List<BilateralTab>> fetchTabs(String currentUserId) async {
    if (!isConnected) {
      return MockTabbyRepository.getInitialTabs();
    }

    // Unauthenticated or synthetic ID: return empty list for real empty state
    if (!_isValidUuid(currentUserId)) {
      return [];
    }

    final session = SupabaseConfig.captureSession();
    if (session.accountId != currentUserId) throw StateError('Account changed');
    void current() {
      if (!SupabaseConfig.isCurrentSession(session)) {
        throw StateError('Account changed');
      }
    }

    final loader = LedgerPageLoader(
      headers: (after, limit) async {
        current();
        final result = await fetchTabHeaderPage(
          SupabaseConfig.client,
          after,
          limit,
        );
        current();
        return result;
      },
      history: (tabs, kind, after, limit) async {
        current();
        final result = await SupabaseConfig.client.rpc(
          'get_tab_ledger_page_v1',
          params: {
            'p_tab_ids': tabs,
            'p_kind': kind,
            'p_after': after,
            'p_limit': limit,
          },
        );
        current();
        return Map<String, dynamic>.from(result as Map);
      },
      balances: (tabs) async {
        current();
        final result = await SupabaseConfig.client.rpc(
          'get_tab_balances_v1',
          params: {'p_tab_ids': tabs},
        );
        current();
        return Map<String, dynamic>.from(result as Map);
      },
    );
    final rows = await loader.load(currentUserId);
    current();
    return rows
        .map(
          (row) => parseTabRow(
            row,
            currentUserId,
            netBalance: row['net_balance_centavos'] as int,
          ),
        )
        .whereType<BilateralTab>()
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Write Operations
  // ---------------------------------------------------------------------------

  static String contactIdentity(String ownerId, String localId) =>
      isValidUuid(localId)
      ? localId.toLowerCase()
      : const Uuid().v5(
          '6ba7b811-9dad-11d1-80b4-00c04fd430c8',
          'tabby/contact/$ownerId/$localId',
        );

  /// Atomically resolves an explicit contact identity; names never identify parties.
  Future<Map<String, String>?> getOrCreateContactTab({
    required String ownerId,
    required String contactName,
    required String contactId,
  }) async {
    if (!isConnected || !_isValidUuid(ownerId)) return null;

    try {
      final res = await SupabaseConfig.client.rpc(
        'resolve_contact_tab_v1',
        params: {
          'p_contact_id': contactIdentity(ownerId, contactId),
          'p_display_name': contactName,
        },
      );
      if (res is Map) {
        return {
          'tab_id': res['tab_id'] as String? ?? '',
          'contact_id': res['contact_id'] as String? ?? '',
        };
      }
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] getOrCreateContactTab error: $e');
    }
    return null;
  }

  /// All group, roster and tab writes run in one authenticated server command.
  Future<String?> createGroupTab({
    required String groupName,
    required String currentUserId,
    required String operationId,
    List<String>? memberUserIds,
  }) async {
    if (!isConnected || !_isValidUuid(currentUserId)) return null;
    final session = SupabaseConfig.captureSession();
    final members = [...?memberUserIds]..sort();
    final result = await SupabaseConfig.client.rpc(
      'create_group_v1',
      params: {
        'p_operation_id': operationId,
        'p_command': {'name': groupName.trim(), 'member_user_ids': members},
      },
    );
    if (!SupabaseConfig.isCurrentSession(session)) return null;
    if (result is! Map ||
        result['tab_id'] is! String ||
        !_isValidUuid(result['tab_id'] as String)) {
      throw StateError('Invalid group creation response.');
    }
    return result['tab_id'] as String;
  }

  Future<String> executeMoneyCommand({
    required String operationId,
    required String rpc,
    required Map<String, dynamic> command,
  }) async {
    final session = SupabaseConfig.captureSession();
    final userId = SupabaseConfig.currentUserId;
    if (userId == null) {
      throw StateError('Money commands require authentication.');
    }
    return DurableMoneyExecutor(
      invoke: (name, params) async {
        if (!SupabaseConfig.isCurrentSession(session) ||
            SupabaseConfig.currentUserId != userId) {
          throw StateError('Session changed.');
        }
        final result = await SupabaseConfig.client.rpc(name, params: params);
        if (!SupabaseConfig.isCurrentSession(session)) {
          throw StateError('Session changed.');
        }
        if (result is! String || !_isValidUuid(result)) {
          throw StateError('Invalid money command result.');
        }
        return result;
      },
    ).execute(
      userId: userId,
      operationId: operationId,
      rpc: rpc,
      command: command,
    );
  }

  /// Versioned commands require an already durable operation ID.
  Future<String?> createExpenseAtomic({
    required String tabId,
    required String title,
    required int totalAmountCentavos,
    required ExpenseCategory category,
    required String paidByUserId,
    required List<Map<String, dynamic>> participants,
    String? operationId,
    DateTime? dueDate,
    String? receiptUrl,
  }) async {
    if (!isConnected || !_isValidUuid(tabId) || !_isValidUuid(paidByUserId)) {
      return null;
    }
    if (operationId == null) {
      throw StateError('A durable operation ID is required.');
    }
    return executeMoneyCommand(
      operationId: operationId,
      rpc: SupabaseConfig.rpcCreateExpenseV1,
      command: {
        'p_tab_id': tabId,
        'p_description': title.isEmpty ? category.displayName : title,
        'p_category': _mapCategory(category),
        'p_total_amount_centavos': totalAmountCentavos,
        'p_paid_by_user_id': paidByUserId,
        'p_participants': participants,
        'p_due_date': dueDate?.toIso8601String().split('T')[0],
        'p_receipt_url': receiptUrl,
      },
    );
  }

  /// Logs an expense to Supabase (ADR-001: integer centavos BIGINT).
  Future<String?> logExpense({
    List<ParticipantShare>? explicitShares,
    required String tabId,
    required String title,
    required int totalAmountCentavos,
    required ExpenseCategory category,
    required String paidByUserId,
    required int myShareCentavos,
    required int counterpartShareCentavos,
    required String currentUserId,
    required String counterpartId,
    DateTime? dueDate,
    String? receiptUrl,
    String? operationId,
  }) async {
    final session = SupabaseConfig.captureSession();
    if (!isConnected ||
        !_isValidUuid(tabId) ||
        !_isValidUuid(paidByUserId) ||
        !_isValidUuid(currentUserId)) {
      return null;
    }
    if (totalAmountCentavos <= 0 ||
        myShareCentavos < 0 ||
        counterpartShareCentavos < 0 ||
        myShareCentavos + counterpartShareCentavos != totalAmountCentavos) {
      throw ArgumentError(
        'Expense total and participant shares must be positive and sum exactly.',
      );
    }

    try {
      if (explicitShares != null) {
        if (explicitShares.length < 2 ||
            explicitShares.map((p) => p.userId).toSet().length !=
                explicitShares.length ||
            explicitShares.any(
              (p) => p.shareAmountCentavos < 0 || !_isValidUuid(p.userId),
            ) ||
            explicitShares.fold<int>(0, (n, p) => n + p.shareAmountCentavos) !=
                totalAmountCentavos ||
            explicitShares.where((p) => p.isPayer).length != 1 ||
            explicitShares.singleWhere((p) => p.isPayer).userId !=
                paidByUserId) {
          throw const FormatException('Invalid explicit group allocations.');
        }
        return await createExpenseAtomic(
          tabId: tabId,
          operationId: operationId,
          title: title,
          totalAmountCentavos: totalAmountCentavos,
          category: category,
          paidByUserId: paidByUserId,
          participants: explicitShares
              .map(
                (p) => {
                  'user_id': p.userId,
                  'participant_role': p.isPayer ? 'payer' : 'debtor',
                  'share_amount_centavos': p.shareAmountCentavos,
                  'acknowledged': p.userId == currentUserId,
                },
              )
              .toList(),
          dueDate: dueDate,
          receiptUrl: receiptUrl,
        );
      }
      final participants = <Map<String, dynamic>>[];

      final membersRes = await SupabaseConfig.client
          .from(SupabaseConfig.tableTabMembers)
          .select('user_id, contact_id')
          .eq('tab_id', tabId);
      final tabMembers = List<Map<String, dynamic>>.from(membersRes);
      if (!SupabaseConfig.isCurrentSession(session)) {
        throw StateError('Session changed.');
      }
      final otherUserMembers = tabMembers
          .map((m) => m['user_id'] as String?)
          .where(
            (uid) => uid != null && _isValidUuid(uid) && uid != paidByUserId,
          )
          .cast<String>()
          .toList();
      final contactMembers = tabMembers
          .map((m) => m['contact_id'] as String?)
          .where((cid) => cid != null && _isValidUuid(cid))
          .cast<String>()
          .toList();
      final isContactPayer =
          contactMembers.isNotEmpty && paidByUserId != currentUserId;
      final payerShare = paidByUserId == currentUserId
          ? myShareCentavos
          : counterpartShareCentavos;

      {
        participants.add({
          if (isContactPayer)
            'contact_id': paidByUserId
          else
            'user_id': paidByUserId,
          'participant_role': 'payer',
          'share_amount_centavos': payerShare,
          'acknowledged': true,
        });
      }

      if (otherUserMembers.isNotEmpty) {
        final remainingAmount = totalAmountCentavos - payerShare;
        // A payer can own the whole bill. Zero remaining means every other
        // participant has a zero share, not the payer's allocation again.
        final perMemberShare = remainingAmount ~/ otherUserMembers.length;
        var remainder =
            remainingAmount - perMemberShare * otherUserMembers.length;
        for (final memberId in otherUserMembers) {
          final share = perMemberShare + (remainder-- > 0 ? 1 : 0);
          participants.add({
            'user_id': memberId,
            'participant_role': 'debtor',
            'share_amount_centavos': share,
            'acknowledged': false,
          });
        }
      } else if (contactMembers.isNotEmpty) {
        final contactId = contactMembers.first;
        if (paidByUserId == currentUserId) {
          participants.add({
            'contact_id': contactId,
            'participant_role': 'debtor',
            'share_amount_centavos': counterpartShareCentavos,
            'acknowledged': false,
          });
        } else {
          participants.add({
            'contact_id': contactId,
            'participant_role': 'payer',
            'share_amount_centavos': counterpartShareCentavos,
            'acknowledged': true,
          });
          participants.add({
            'user_id': currentUserId,
            'participant_role': 'debtor',
            'share_amount_centavos': myShareCentavos,
            'acknowledged': false,
          });
        }
      } else {
        final debtorId = paidByUserId == currentUserId
            ? counterpartId
            : currentUserId;
        final debtorShare = paidByUserId == currentUserId
            ? counterpartShareCentavos
            : myShareCentavos;
        if (_isValidUuid(debtorId) && debtorId != paidByUserId) {
          participants.add({
            'user_id': debtorId,
            'participant_role': 'debtor',
            'share_amount_centavos': debtorShare,
            'acknowledged': false,
          });
        }
      }

      final transactionId = await createExpenseAtomic(
        tabId: tabId,
        operationId: operationId,
        title: title,
        totalAmountCentavos: totalAmountCentavos,
        category: category,
        paidByUserId: paidByUserId,
        participants: participants,
        dueDate: dueDate,
        receiptUrl: receiptUrl,
      );
      return transactionId;
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] logExpense error: $e');
      rethrow;
    }
  }

  /// Records a payment settlement in Supabase.
  Future<bool> recordPayment({
    required String tabId,
    required int amountCentavos,
    required PaymentMethod method,
    required String paidByUserId,
    required String receivedByUserId,
    String? note,
    String? confirmedByUserId,
    String? operationId,
  }) async =>
      (await submitPayment(
        tabId: tabId,
        amountCentavos: amountCentavos,
        method: method,
        submittedByUserId: paidByUserId,
        recipientUserId: receivedByUserId,
        note: note,
        operationId: operationId,
      )) !=
      null;

  /// Submits or confirms a payment through the atomic payment contract.
  Future<String?> submitPayment({
    String? proofPath,
    String? paymentReference,
    required String tabId,
    required String submittedByUserId,
    required String recipientUserId,
    required int amountCentavos,
    required PaymentMethod method,
    String? note,
    String? operationId,
  }) async {
    if (!isConnected ||
        !_isValidUuid(tabId) ||
        !_isValidUuid(submittedByUserId) ||
        !_isValidUuid(recipientUserId) ||
        submittedByUserId == recipientUserId ||
        amountCentavos <= 0) {
      return null;
    }
    if (operationId == null) {
      throw StateError('A durable operation ID is required.');
    }
    return executeMoneyCommand(
      operationId: operationId,
      rpc: proofPath != null || paymentReference != null
          ? 'submit_payment_v2'
          : SupabaseConfig.rpcSubmitPaymentV1,
      command: {
        if (proofPath != null) 'proof_path': proofPath,
        if (paymentReference != null) 'reference': paymentReference,
        'p_tab_id': tabId,
        'p_submitted_by_user_id': submittedByUserId,
        'p_recipient_user_id': recipientUserId,
        'p_amount_centavos': amountCentavos,
        'p_payment_method': _mapPaymentMethod(method),
        'p_note': note,
      },
    );
  }

  Future<String> recordContactCash({
    required String operationId,
    required String tabId,
    required PartyRef payer,
    required PartyRef recipient,
    required int amountCentavos,
    String? note,
  }) => executeMoneyCommand(
    operationId: operationId,
    rpc: 'record_received_payment_v1',
    command: {
      'p_tab_id': tabId,
      'payer': payer.toMap(),
      'recipient': recipient.toMap(),
      'amount_centavos': amountCentavos,
      'method': 'cash',
      'note': note,
    },
  );

  /// Confirms a previously submitted payment as its explicit recipient.
  Future<String?> decidePayment(
    String paymentId,
    bool confirm,
    String? reason,
  ) async {
    if (!isConnected || !_isValidUuid(paymentId)) return null;
    final session = SupabaseConfig.captureSession();
    final response = await SupabaseConfig.client.rpc(
      confirm ? 'confirm_payment' : 'reject_payment_v1',
      params: {'p_payment_id': paymentId, if (!confirm) 'p_reason': reason},
    );
    if (!SupabaseConfig.isCurrentSession(session)) return null;
    return response is String ? response : null;
  }

  Future<String?> confirmPayment(String paymentId) async {
    if (!isConnected || !_isValidUuid(paymentId)) return null;
    try {
      final response = await SupabaseConfig.client.rpc(
        SupabaseConfig.rpcConfirmPayment,
        params: {'p_payment_id': paymentId},
      );
      return response is String ? response : response?.toString();
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] confirm_payment error: $e');
      return null;
    }
  }

  /// Shared archival is unsupported; use caller-only Connections preferences.
  Future<void> archiveTab(String tabId) async {
    throw UnsupportedError('Use private Connections archive and restore.');
  }

  /// Attaches a receipt URL to an existing transaction in Supabase.
  Future<void> attachReceipt(String transactionId, String receiptUrl) async {
    if (!isConnected || !_isValidUuid(transactionId)) return;
    throw UnsupportedError(
      'Use the durable append_transaction_receipt_v1 command.',
    );
  }

  // ─── Notifications (public.notifications table) ─────────────────────────

  /// Fetches all notifications for the current user, most recent first.
  /// Returns empty list on error or when not connected.
  Future<List<AppNotification>> fetchNotifications(String userId) async {
    if (!isConnected || !_isValidUuid(userId)) return [];
    try {
      final rows = await SupabaseConfig.client
          .from('notifications')
          .select(
            'id, recipient_user_id, notification_type, related_tab_id, '
            'related_transaction_id, related_payment_id, related_group_id, '
            'title, body, is_read, created_at, read_at',
          )
          .eq('recipient_user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);

      return (rows as List)
          .whereType<Map<String, dynamic>>()
          .map(AppNotification.fromSupabaseRow)
          .whereType<AppNotification>()
          .toList();
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] fetchNotifications error: $e');
      return [];
    }
  }

  /// Marks a single notification as read in the database.
  Future<void> markNotificationRead(String notificationId) async {
    if (!isConnected || !_isValidUuid(notificationId)) return;
    try {
      await SupabaseConfig.client
          .from('notifications')
          .update({
            'is_read': true,
            'read_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', notificationId);
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] markNotificationRead error: $e');
    }
  }

  /// Marks ALL notifications for a user as read.
  Future<void> markAllNotificationsRead(String userId) async {
    if (!isConnected || !_isValidUuid(userId)) return;
    try {
      await SupabaseConfig.client
          .from('notifications')
          .update({
            'is_read': true,
            'read_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('recipient_user_id', userId)
          .eq('is_read', false);
    } catch (e) {
      debugPrint(
        '[SupabaseTabbyRepository] markAllNotificationsRead error: $e',
      );
    }
  }

  Future<String?> submitReminderCommand(
    String operationId,
    Map<String, dynamic> command,
  ) async {
    if (!isConnected) return null;
    final session = SupabaseConfig.captureSession();
    final result = await SupabaseConfig.client.rpc(
      'send_tab_reminder_v1',
      params: {'p_operation_id': operationId, 'p_command': command},
    );
    return SupabaseConfig.isCurrentSession(session) &&
            result is String &&
            _isValidUuid(result)
        ? result
        : null;
  }

  Future<bool> sendTabReminder({
    required String tabId,
    required String recipientUserId,
    required String senderName,
    required String formattedAmount,
    String? description,
    String? customTitle,
    String? customBody,
  }) async {
    try {
      final result = await submitReminderCommand(const Uuid().v4(), {
        'tab_id': tabId,
        'recipient_user_id': recipientUserId,
        'title': customTitle ?? '$senderName sent you a friendly reminder',
        'body': customBody ?? 'You have an outstanding balance on our shared tab. Open Tabby to review it.',
      });
      return result != null;
    } catch (_) {
      return false;
    }
  }

  /// Inserts a manual nudge notification row for the recipient user.
  /// Called when the current user taps "Remind" on a tab —
  /// the recipient sees this in their Notification Center next time they open the app.
  Future<void> insertNudgeNotification({
    required String recipientUserId,
    required String senderName,
    required String relatedTabId,
    required String description,
    required String formattedAmount,
  }) async {
    await sendTabReminder(
      tabId: relatedTabId,
      recipientUserId: recipientUserId,
      senderName: senderName,
      formattedAmount: formattedAmount,
      description: description,
    );
  }

  /// Inserts a payment-confirmed notification for the payee.
  Future<void> insertPaymentConfirmedNotification({
    required String recipientUserId,
    required String senderName,
    required String relatedTabId,
    required String formattedAmount,
  }) async {
    if (!isConnected ||
        !_isValidUuid(recipientUserId) ||
        !_isValidUuid(relatedTabId)) {
      return;
    }
    try {
      await SupabaseConfig.client.from('notifications').insert({
        'recipient_user_id': recipientUserId,
        'notification_type': 'payment_confirmed',
        'related_tab_id': relatedTabId,
        'title': 'Payment confirmed',
        'body':
            '$senderName confirmed your $formattedAmount payment. Tab updated.',
        'is_read': false,
      });
    } catch (e) {
      debugPrint(
        '[SupabaseTabbyRepository] insertPaymentConfirmedNotification error: $e',
      );
    }
  }

  /// Alias for markNotificationRead
  Future<void> markNotificationAsRead(String id) => markNotificationRead(id);

  /// Alias for markAllNotificationsRead
  Future<void> markAllNotificationsAsRead(String userId) =>
      markAllNotificationsRead(userId);
}
