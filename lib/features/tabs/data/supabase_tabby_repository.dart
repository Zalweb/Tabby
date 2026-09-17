import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../domain/models.dart';
import 'mock_tabby_repository.dart';
import 'tabby_local_cache.dart';

class GoogleSignInClientConfiguration {
  final String? clientId;
  final String serverClientId;

  const GoogleSignInClientConfiguration({
    required this.clientId,
    required this.serverClientId,
  });
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
      final profile = await SupabaseConfig.client
          .from(SupabaseConfig.tableUsers)
          .select('display_name, phone')
          .eq('id', userId)
          .maybeSingle();
      return profileNeedsCompletion(profile);
    } catch (e) {
      debugPrint(
          '[SupabaseTabbyRepository] Profile completion check error: $e');
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
    if (!isConnected) return null;
    final normalized = normalizeFriendCode(friendCode);
    if (normalized == null) return null;

    try {
      final response = await SupabaseConfig.client.rpc(
        SupabaseConfig.rpcFindUserByFriendCode,
        params: {'p_friend_code': normalized},
      );
      final row = _responseMap(response);
      return row == null ? null : TabbyUser.fromMap(row);
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] findUserByFriendCode error: $e');
      return null;
    }
  }

  /// Sends a pending friend request using a shareable Tabby ID.
  Future<FriendRequest?> sendFriendRequest({required String friendCode}) async {
    if (!isConnected) return null;
    final normalized = normalizeFriendCode(friendCode);
    if (normalized == null) return null;

    try {
      final response = await SupabaseConfig.client.rpc(
        SupabaseConfig.rpcSendFriendRequest,
        params: {'p_friend_code': normalized},
      );
      final row = _responseMap(response);
      if (row == null) return null;
      return parseFriendRequestRow(
        row,
        currentUserId: SupabaseConfig.currentUserId,
      );
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] sendFriendRequest error: $e');
      return null;
    }
  }

  /// Loads requests involving the authenticated user.
  Future<List<FriendRequest>> fetchFriendRequests(String currentUserId) async {
    if (!isConnected || !_isValidUuid(currentUserId)) return [];

    try {
      final response = await SupabaseConfig.client.rpc(
        SupabaseConfig.rpcListFriendRequests,
      );
      if (response is! List) return [];
      return response
          .whereType<Map>()
          .map((row) => parseFriendRequestRow(
                Map<String, dynamic>.from(row),
                currentUserId: currentUserId,
              ))
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
    if (!isConnected || !_isValidUuid(friendshipId)) return null;

    try {
      final response = await SupabaseConfig.client.rpc(
        SupabaseConfig.rpcRespondFriendRequest,
        params: {
          'p_friendship_id': friendshipId,
          'p_accept': accept,
        },
      );
      final row = _responseMap(response);
      return row?['tab_id'] as String?;
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] respondToFriendRequest error: $e');
      return null;
    }
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

    final isGroup = (tabRow['tab_type'] as String?) == 'group' ||
        tabRow['group_id'] != null ||
        tabRow['groups'] != null;

    final groupData = tabRow['groups'] as Map<String, dynamic>?;
    final groupName = groupData?['name'] as String? ??
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
        final dName = (mUser?['display_name'] ??
                rawMeta?['display_name'] ??
                mUser?['name'] ??
                mContact?['display_name'] ??
                mMap['name']) as String? ??
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
            'display_name': memberNameById[fallbackCounterpartId] ?? 'Friend'
          },
        };
      }
    }

    if (counterpartMember == null && !isGroup) return null;

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
      final counterpartUserId = (counterpartMember!['user_id'] ??
              counterpartMember['contact_id']) as String? ??
          '';
      final counterpartUserRow = (counterpartMember['users'] ??
          counterpartMember['contacts']) as Map<String, dynamic>?;

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
      final pList = (tx['transaction_participants'] as List<dynamic>?) ??
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

      entries.add(LedgerEntry(
        id: tx['id'] as String? ?? 'tx-$tabId',
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
        receiptUrl: (tx['receipt_url'] ?? tx['payment_proof_url']) as String?,
      ));
    }

    // Build ledger entries from payments
    final payList = (tabRow['payments'] as List<dynamic>?) ?? [];
    for (final payRaw in payList) {
      final pay = payRaw as Map<String, dynamic>;
      final submittedBy = pay['submitted_by'] as String? ?? '';
      final isMePaying = submittedBy == currentUserId;
      final payerName = isMePaying
          ? 'You'
          : (memberNameById[submittedBy] ??
              (isGroup ? 'Group Member' : counterpart.displayName));
      final dateStr = (pay['submitted_at'] ?? pay['created_at']) as String?;
      final payAmt = (pay['amount_centavos'] as num?)?.toInt() ?? 0;

      final proofList = (pay['payment_proofs'] as List<dynamic>?) ?? [];
      final proofUrl = proofList.isNotEmpty
          ? (proofList.first as Map<String, dynamic>)['file_url'] as String?
          : null;
      final receiptUrl = proofUrl ??
          (pay['payment_proof_url'] ?? pay['receipt_url']) as String?;

      entries.add(LedgerEntry(
        id: pay['id'] as String? ?? 'pay-$tabId',
        tabId: tabId,
        title: isMePaying ? 'You paid' : '$payerName paid',
        category: ExpenseCategory.borrowedCash,
        totalAmountCentavos: payAmt,
        myShareCentavos: 0,
        counterpartShareCentavos: 0,
        paidByUserId: submittedBy,
        paidByName: payerName,
        date: dateStr != null
            ? DateTime.tryParse(dateStr) ?? DateTime.now()
            : DateTime.now(),
        status: TransactionStatus.settled,
        isPayment: true,
        paymentMethod: unmapPaymentMethod(pay['payment_method']),
        note: pay['note'] as String?,
        receiptUrl: receiptUrl,
      ));
    }

    // Sort entries newest-first
    entries.sort((a, b) => b.date.compareTo(a.date));

    final lastUpdatedStr =
        tabRow['updated_at'] as String? ?? tabRow['created_at'] as String?;

    final effectiveNetBalance = netBalance ??
        MockTabbyRepository.calculateNetBalance(entries, currentUserId);

    return BilateralTab(
      id: tabId,
      counterpart: counterpart,
      netBalanceCentavos: effectiveNetBalance,
      itemCount: entries.length,
      entries: entries,
      lastUpdated: lastUpdatedStr != null
          ? DateTime.tryParse(lastUpdatedStr) ?? DateTime.now()
          : DateTime.now(),
      isGroupTab: isGroup,
      groupName: isGroup ? groupName : null,
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
              '[SupabaseTabbyRepository] ensureUserExists upsert warning: $e');
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
          '[SupabaseTabbyRepository] ensureUserExists synthetic warning: $e');
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
          email: (data['email'] as String?) ?? authUser?.email ?? '',
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

  /// Updates profile in Supabase public.users
  Future<bool> updateUserProfile({
    required String userId,
    String? displayName,
    String? phone,
    String? avatarUrl,
    String? gcashNumber,
    String? mayaNumber,
    String? qrCodeUrl,
  }) async {
    if (!isConnected || !_isValidUuid(userId)) return false;

    try {
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (displayName != null) updates['display_name'] = displayName;
      if (phone != null) updates['phone'] = phone;
      if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
      if (gcashNumber != null) updates['gcash_number'] = gcashNumber;
      if (mayaNumber != null) updates['maya_number'] = mayaNumber;
      if (qrCodeUrl != null) updates['qr_code_url'] = qrCodeUrl;

      await SupabaseConfig.client.from(SupabaseConfig.tableUsers).upsert({
        'id': userId,
        ...updates,
      }, onConflict: 'id');

      debugPrint(
          '[SupabaseTabbyRepository] updateUserProfile saved to Supabase');
      return true;
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] updateUserProfile error: $e');
      return false;
    }
  }

  /// Sign in with Google OAuth
  ///
  /// - **Web**: Uses Supabase's browser redirect OAuth flow.
  /// - **iOS / Android**: Uses the native Google Sign-In SDK to obtain an ID
  ///   token, then exchanges it with Supabase via `signInWithIdToken`.
  ///   This opens the native account picker sheet — no browser pop-up.
  Future<bool> signInWithGoogle() async {
    if (!isConnected) return false;

    // ── Web: existing browser-redirect OAuth ─────────────────────────────────
    if (kIsWeb) {
      try {
        final success = await SupabaseConfig.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: '${Uri.base.origin}/',
        );
        return success;
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
        iosClientId:
            iosClientId.isNotEmpty ? iosClientId : defaultIosGoogleClientId,
        webClientId:
            webClientId.isNotEmpty ? webClientId : defaultWebGoogleClientId,
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
            '[SupabaseTabbyRepository] Google sign-in cancelled by user.');
        return false;
      }

      // Obtain auth tokens from Google
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null) {
        debugPrint(
            '[SupabaseTabbyRepository] Native Google sign-in: idToken is null. Falling back to browser OAuth...');
        return await SupabaseConfig.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: 'io.supabase.tabby://login-callback',
        );
      }

      // Exchange Google token with Supabase → creates/updates session
      await SupabaseConfig.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      debugPrint('[SupabaseTabbyRepository] Native Google sign-in successful.');
      return true;
    } catch (e) {
      debugPrint(
          '[SupabaseTabbyRepository] Native Google sign-in error: $e. Falling back to browser OAuth...');
      try {
        final fallbackSuccess = await SupabaseConfig.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: 'io.supabase.tabby://login-callback',
        );
        return fallbackSuccess;
      } catch (fallbackError) {
        debugPrint(
            '[SupabaseTabbyRepository] Google browser OAuth fallback error: $fallbackError');
        rethrow;
      }
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      await TabbyLocalCache.clearCache();
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] clearCache error: $e');
    }

    if (!isConnected) return;
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

    try {
      final tabsData = await SupabaseConfig.client
          .from(SupabaseConfig.tableTabs)
          .select(
            'id, tab_type, group_id, status, created_at, updated_at, user_a, user_b,'
            'groups ( id, name, avatar_url ),'
            'tab_members ('
            '  user_id, contact_id,'
            '  users ( id, display_name, email, phone, friend_code ),'
            '  contacts ( id, display_name, email, phone )'
            '),'
            'transactions ('
            '  id, created_by, transaction_type, category, description,'
            '  total_amount_centavos, currency, due_date, status, created_at, receipt_url,'
            '  transaction_participants ('
            '    user_id, contact_id, participant_role, share_amount_centavos, acknowledged'
            '  )'
            '),'
            'payments ('
            '  id, submitted_by, amount_centavos, payment_method, note, status, submitted_at,'
            '  payment_proofs ( file_url )'
            ')',
          )
          .neq('status', 'archived');

      if (tabsData.isEmpty) {
        return [];
      }

      final List<BilateralTab> loadedTabs = [];

      for (final tabRow in tabsData) {
        final tabId = tabRow['id'] as String? ?? '';
        if (tabId.isEmpty) continue;

        // Fetch live RPC balance for this tab
        int? netBalance;
        try {
          netBalance = await SupabaseConfig.getNetBalance(
            tabId: tabId,
            userId: currentUserId,
          );
        } catch (e) {
          debugPrint(
              '[SupabaseTabbyRepository] getNetBalance error for $tabId: $e');
        }

        final tab = parseTabRow(tabRow, currentUserId, netBalance: netBalance);
        if (tab != null) {
          loadedTabs.add(tab);
        }
      }

      return loadedTabs;
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] fetchTabs error: $e');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Write Operations
  // ---------------------------------------------------------------------------

  /// Atomically retrieves or creates a tab for an unregistered contact.
  Future<Map<String, String>?> getOrCreateContactTab({
    required String ownerId,
    required String contactName,
  }) async {
    if (!isConnected || !_isValidUuid(ownerId)) return null;

    try {
      final res = await SupabaseConfig.client.rpc(
        'get_or_create_contact_tab',
        params: {
          'p_owner_id': ownerId,
          'p_contact_name': contactName,
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

  /// Creates a group and an associated group tab in Supabase.
  Future<String?> createGroupTab({
    required String groupName,
    required String currentUserId,
    List<String>? memberUserIds,
  }) async {
    if (!isConnected || !_isValidUuid(currentUserId)) return null;

    try {
      // 1. Create group in public.groups
      final groupRes = await SupabaseConfig.client
          .from(SupabaseConfig.tableGroups)
          .insert({
            'name': groupName,
            'created_by': currentUserId,
          })
          .select('id')
          .maybeSingle();

      if (groupRes == null || groupRes['id'] == null) return null;
      final groupId = groupRes['id'] as String;

      // 2. Add creator as admin member
      await SupabaseConfig.client
          .from(SupabaseConfig.tableGroupMembers)
          .insert({
        'group_id': groupId,
        'user_id': currentUserId,
        'role': 'admin',
        'status': 'active',
      });

      // 3. Add other members if valid UUIDs
      if (memberUserIds != null) {
        for (final mId in memberUserIds) {
          if (_isValidUuid(mId) && mId != currentUserId) {
            try {
              await SupabaseConfig.client
                  .from(SupabaseConfig.tableGroupMembers)
                  .insert({
                'group_id': groupId,
                'user_id': mId,
                'role': 'member',
                'status': 'active',
              });
            } catch (e) {
              debugPrint('[SupabaseTabbyRepository] add member warning: $e');
            }
          }
        }
      }

      // 4. Create group tab in public.tabs
      final tabRes = await SupabaseConfig.client
          .from(SupabaseConfig.tableTabs)
          .insert({
            'tab_type': 'group',
            'group_id': groupId,
            'status': 'active',
          })
          .select('id')
          .maybeSingle();

      if (tabRes != null && tabRes['id'] != null) {
        final tabId = tabRes['id'] as String;
        final tabMembers = <Map<String, dynamic>>[
          {
            'tab_id': tabId,
            'user_id': currentUserId,
            'role': 'admin',
          }
        ];
        if (memberUserIds != null) {
          for (final mId in memberUserIds) {
            if (_isValidUuid(mId) && mId != currentUserId) {
              tabMembers.add({
                'tab_id': tabId,
                'user_id': mId,
                'role': 'participant',
              });
            }
          }
        }
        await SupabaseConfig.client
            .from(SupabaseConfig.tableTabMembers)
            .insert(tabMembers);
        return tabId;
      }
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] createGroupTab error: $e');
    }
    return null;
  }

  /// Logs an expense to Supabase (ADR-001: integer centavos BIGINT).
  Future<void> logExpense({
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
  }) async {
    if (!isConnected) return;

    // Only insert if tabId is a valid UUID
    if (!_isValidUuid(tabId)) {
      debugPrint(
          '[SupabaseTabbyRepository] logExpense skipped: tabId ($tabId) is not a valid UUID');
      return;
    }

    try {
      final inserted = await SupabaseConfig.client
          .from(SupabaseConfig.tableTransactions)
          .insert({
            'tab_id': tabId,
            'created_by': currentUserId,
            'transaction_type': 'shared_expense',
            'category': _mapCategory(category),
            'description': title.isEmpty ? category.displayName : title,
            'total_amount_centavos': totalAmountCentavos,
            'currency': 'PHP',
            'status': 'acknowledged',
            if (dueDate != null)
              'due_date': dueDate.toIso8601String().split('T')[0],
            if (receiptUrl != null && receiptUrl.isNotEmpty)
              'receipt_url': receiptUrl,
          })
          .select('id')
          .maybeSingle();

      if (inserted != null && inserted['id'] != null) {
        final txId = inserted['id'] as String;

        final participants = <Map<String, dynamic>>[];

        // Payer participant
        if (_isValidUuid(paidByUserId)) {
          final payerShare = paidByUserId == currentUserId
              ? myShareCentavos
              : counterpartShareCentavos;
          participants.add({
            'transaction_id': txId,
            'user_id': paidByUserId,
            'participant_role': 'payer',
            'share_amount_centavos': payerShare,
            'acknowledged': true,
          });
        }

        // Debtor participant(s) & contact lookup
        List<Map<String, dynamic>> tabMembers = [];
        try {
          final membersRes = await SupabaseConfig.client
              .from(SupabaseConfig.tableTabMembers)
              .select('user_id, contact_id')
              .eq('tab_id', tabId);
          tabMembers = List<Map<String, dynamic>>.from(membersRes);
        } catch (e) {
          debugPrint('[SupabaseTabbyRepository] tabMembers lookup warning: $e');
        }

        final otherUserMembers = tabMembers
            .map((m) => m['user_id'] as String?)
            .where((uid) =>
                uid != null && _isValidUuid(uid) && uid != paidByUserId)
            .cast<String>()
            .toList();

        final contactMembers = tabMembers
            .map((m) => m['contact_id'] as String?)
            .where((cid) => cid != null && _isValidUuid(cid))
            .cast<String>()
            .toList();

        if (otherUserMembers.isNotEmpty) {
          // Multi-party / registered group tab: distribute debtor share
          final remainingAmount = totalAmountCentavos -
              (paidByUserId == currentUserId ? myShareCentavos : 0);
          final perMemberShare = remainingAmount > 0
              ? (remainingAmount ~/ otherUserMembers.length)
              : counterpartShareCentavos;
          for (final memberId in otherUserMembers) {
            participants.add({
              'transaction_id': txId,
              'user_id': memberId,
              'participant_role': 'debtor',
              'share_amount_centavos': perMemberShare,
              'acknowledged': false,
            });
          }
        } else if (contactMembers.isNotEmpty) {
          // Contact tab: counterpart is a virtual contact
          final contactId = contactMembers.first;
          final isPayerMe = paidByUserId == currentUserId;
          if (isPayerMe) {
            participants.add({
              'transaction_id': txId,
              'contact_id': contactId,
              'participant_role': 'debtor',
              'share_amount_centavos': counterpartShareCentavos,
              'acknowledged': false,
            });
          } else {
            // Contact paid, current user owes
            participants.add({
              'transaction_id': txId,
              'contact_id': contactId,
              'participant_role': 'payer',
              'share_amount_centavos': counterpartShareCentavos,
              'acknowledged': true,
            });
            participants.add({
              'transaction_id': txId,
              'user_id': currentUserId,
              'participant_role': 'debtor',
              'share_amount_centavos': myShareCentavos,
              'acknowledged': false,
            });
          }
        } else {
          // Fallback bilateral registered debtor
          final debtorId =
              paidByUserId == currentUserId ? counterpartId : currentUserId;
          final debtorShare = paidByUserId == currentUserId
              ? counterpartShareCentavos
              : myShareCentavos;
          if (_isValidUuid(debtorId) && debtorId != paidByUserId) {
            participants.add({
              'transaction_id': txId,
              'user_id': debtorId,
              'participant_role': 'debtor',
              'share_amount_centavos': debtorShare,
              'acknowledged': false,
            });
          }
        }

        if (participants.isNotEmpty) {
          await SupabaseConfig.client
              .from(SupabaseConfig.tableTransactionParticipants)
              .insert(participants);
        }
      }
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] logExpense error: $e');
    }
  }

  /// Records a payment settlement in Supabase.
  Future<void> recordPayment({
    required String tabId,
    required int amountCentavos,
    required PaymentMethod method,
    required String paidByUserId,
    required String receivedByUserId,
    String? note,
    String? confirmedByUserId,
  }) async {
    if (!isConnected) return;

    // Only insert if tabId and paidByUserId are valid UUIDs
    if (!_isValidUuid(tabId) || !_isValidUuid(paidByUserId)) {
      debugPrint(
          '[SupabaseTabbyRepository] recordPayment skipped: tabId ($tabId) or paidByUserId ($paidByUserId) is not a valid UUID');
      return;
    }

    try {
      final currentUserId = SupabaseConfig.currentUserId;
      final isCreditorRecording =
          currentUserId != null && currentUserId == receivedByUserId;
      final confirmedBy =
          confirmedByUserId ?? (isCreditorRecording ? currentUserId : null);
      final validConfirmedBy =
          (confirmedBy != null && _isValidUuid(confirmedBy))
              ? confirmedBy
              : null;
      final paymentStatus = isCreditorRecording ? 'confirmed' : 'submitted';

      await SupabaseConfig.client.from(SupabaseConfig.tablePayments).insert({
        'tab_id': tabId,
        'submitted_by': paidByUserId,
        'amount_centavos': amountCentavos,
        'payment_method': _mapPaymentMethod(method),
        if (note != null && note.isNotEmpty) 'note': note,
        'status': paymentStatus,
        if (validConfirmedBy != null) 'confirmed_by': validConfirmedBy,
        if (validConfirmedBy != null)
          'confirmed_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] recordPayment error: $e');
    }
  }

  /// Archives a tab in Supabase.
  Future<void> archiveTab(String tabId) async {
    if (!isConnected || !_isValidUuid(tabId)) return;
    try {
      await SupabaseConfig.client
          .from(SupabaseConfig.tableTabs)
          .update({'status': 'archived'}).eq('id', tabId);
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] archiveTab error: $e');
    }
  }

  /// Attaches a receipt URL to an existing transaction in Supabase.
  Future<void> attachReceipt(String transactionId, String receiptUrl) async {
    if (!isConnected || !_isValidUuid(transactionId)) return;
    try {
      await SupabaseConfig.client
          .from(SupabaseConfig.tableTransactions)
          .update({'receipt_url': receiptUrl}).eq('id', transactionId);
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] attachReceipt error: $e');
    }
  }
}
