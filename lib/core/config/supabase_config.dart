import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Type-safe Supabase configuration and initialization service for Tabby.
///
/// Follows ADR-001 (Integer centavos BIGINT) and ADR-011 (Supabase BaaS).
/// Supports compile-time environment flags `--dart-define` as well as runtime initialization.
class SupabaseConfig {
  SupabaseConfig._();

  // --------------------------------------------------------------------------
  // Compile-time environment variable bindings
  // --------------------------------------------------------------------------
  static const String defaultUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ziaqrkagsvozhotremsx.supabase.co',
  );

  static const String defaultAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_3oqHm0yg7oetZTuIJ27NNA_4yy8VK8O',
  );

  static const String storageBucketName = 'payment-proofs';
  static const String paymentMethodsBucketName = 'payment-methods';

  // --------------------------------------------------------------------------
  // Table Constants (All 17 Relational Entities from AGENTS.md Section 7)
  // --------------------------------------------------------------------------
  static const String tableUsers = 'users';
  static const String tableContacts = 'contacts';
  static const String tableFriendships = 'friendships';
  static const String tableGroups = 'groups';
  static const String tableGroupMembers = 'group_members';
  static const String tableGroupPermissions = 'group_permissions';
  static const String tableTabs = 'tabs';
  static const String tableTabMembers = 'tab_members';
  static const String tableRecurringRules = 'recurring_rules';
  static const String tableTransactions = 'transactions';
  static const String tableTransactionParticipants = 'transaction_participants';
  static const String tablePayments = 'payments';
  static const String tablePaymentProofs = 'payment_proofs';
  static const String tablePaymentMethods = 'payment_methods';
  static const String tableReminders = 'reminders';
  static const String tableNotifications = 'notifications';
  static const String tableReports = 'reports';
  static const String tableActivityLogs = 'activity_logs';

  // --------------------------------------------------------------------------
  // Stored Function / RPC Names (AGENTS.md Section 8)
  // --------------------------------------------------------------------------
  static const String rpcGetNetBalance = 'get_net_balance';
  static const String rpcGetTabSummary = 'get_tab_summary';
  static const String rpcGetUserDashboardSummary = 'get_user_dashboard_summary';
  static const String rpcGetOrCreateBilateralTab =
      'get_or_create_bilateral_tab';
  static const String rpcClaimContact = 'claim_contact';
  static const String rpcValidateTransactionSplit =
      'validate_transaction_split';
  static const String rpcFindUserByFriendCode = 'find_user_by_friend_code';
  static const String rpcSendFriendRequest = 'send_friend_request';
  static const String rpcListFriendRequests = 'list_friend_requests';
  static const String rpcRespondFriendRequest = 'respond_friend_request';
  static const String rpcListPaymentMethodsForTab =
      'list_payment_methods_for_tab';

  // --------------------------------------------------------------------------
  // State & Initialization
  // --------------------------------------------------------------------------
  static bool _initialized = false;
  static bool get isInitialized => _initialized;

  /// Initializes the Supabase client instance.
  /// Call this in `main()` before `runApp()`.
  ///
  /// ```dart
  /// void main() async {
  ///   WidgetsFlutterBinding.ensureInitialized();
  ///   await SupabaseConfig.initialize(
  ///     url: 'https://myproject.supabase.co',
  ///     anonKey: 'my-anon-key',
  ///   );
  ///   runApp(const TabbyApp());
  /// }
  /// ```
  static Future<void> initialize({
    String? url,
    String? anonKey,
    bool debug = kDebugMode,
  }) async {
    final effectiveUrl = url ?? defaultUrl;
    final effectiveAnonKey = anonKey ?? defaultAnonKey;

    if (effectiveUrl.isEmpty || effectiveAnonKey.isEmpty) {
      debugPrint(
        '[SupabaseConfig] Warning: SUPABASE_URL or SUPABASE_ANON_KEY is empty. '
        'Ensure .env or --dart-define parameters are configured.',
      );
    }

    try {
      await Supabase.initialize(
        url: effectiveUrl,
        // ignore: deprecated_member_use
        anonKey: effectiveAnonKey,
        debug: debug,
      );
      _initialized = true;
      debugPrint(
          '[SupabaseConfig] Initialized successfully with: $effectiveUrl');
    } catch (e, stackTrace) {
      debugPrint('[SupabaseConfig] Initialization failed: $e\n$stackTrace');
      rethrow;
    }
  }

  // --------------------------------------------------------------------------
  // Client Accessors
  // --------------------------------------------------------------------------
  /// Direct handle to the singleton [SupabaseClient].
  static SupabaseClient get client {
    if (!_initialized) {
      try {
        return Supabase.instance.client;
      } catch (_) {
        throw StateError(
          'SupabaseConfig has not been initialized. Call SupabaseConfig.initialize() first.',
        );
      }
    }
    return Supabase.instance.client;
  }

  /// Direct handle to the authentication service.
  static GoTrueClient get auth => client.auth;

  /// Direct handle to the storage service.
  static SupabaseStorageClient get storage => client.storage;

  /// Direct handle to the private payment proofs bucket.
  static StorageFileApi get paymentProofsBucket =>
      storage.from(storageBucketName);

  /// Direct handle to the private payment methods bucket.
  static StorageFileApi get paymentMethodsBucket =>
      storage.from(paymentMethodsBucketName);

  /// Current authenticated user (or null if unauthenticated).
  static User? get currentUser => isInitialized ? auth.currentUser : null;

  /// Current authenticated user ID (or null if unauthenticated).
  static String? get currentUserId =>
      isInitialized ? auth.currentUser?.id : null;

  // --------------------------------------------------------------------------
  // Balance & Ledger RPC Helpers (Integer Centavos Standard)
  // --------------------------------------------------------------------------

  /// Computes the server-side net balance in integer centavos for [tabId] from [userId]'s perspective.
  ///
  /// Returns:
  /// - Positive (`> 0`): Counterpart owes user ("You're owed").
  /// - Negative (`< 0`): User owes counterpart ("You owe").
  /// - Zero (`0`): Settled up ("Fully settled").
  static Future<int> getNetBalance({
    required String tabId,
    required String userId,
  }) async {
    final response = await client.rpc(
      rpcGetNetBalance,
      params: {
        'p_tab_id': tabId,
        'p_user_id': userId,
      },
    );

    if (response is int) return response;
    if (response is num) return response.toInt();
    return int.tryParse(response.toString()) ?? 0;
  }

  /// Retrieves the rich tab summary breakdown and mascot emotion state.
  static Future<Map<String, dynamic>> getTabSummary({
    required String tabId,
    required String userId,
  }) async {
    final response = await client.rpc(
      rpcGetTabSummary,
      params: {
        'p_tab_id': tabId,
        'p_user_id': userId,
      },
    );

    if (response is Map<String, dynamic>) {
      return response;
    }
    return Map<String, dynamic>.from(response as Map);
  }

  /// Retrieves the aggregate dashboard summary ("You owe" / "You're owed" centavos).
  static Future<Map<String, dynamic>> getUserDashboardSummary({
    required String userId,
  }) async {
    final response = await client.rpc(
      rpcGetUserDashboardSummary,
      params: {
        'p_user_id': userId,
      },
    );

    if (response is Map<String, dynamic>) {
      return response;
    }
    return Map<String, dynamic>.from(response as Map);
  }

  /// Atomically retrieves or creates a canonical 1-on-1 bilateral tab between two users.
  static Future<String> getOrCreateBilateralTab({
    required String userA,
    required String userB,
  }) async {
    final response = await client.rpc(
      rpcGetOrCreateBilateralTab,
      params: {
        'p_user_a': userA,
        'p_user_b': userB,
      },
    );

    return response.toString();
  }

  /// Links an unonboarded virtual contact to a newly registered user account (ADR-007).
  static Future<bool> claimContact({
    required String contactId,
    required String claimedUserId,
  }) async {
    final response = await client.rpc(
      rpcClaimContact,
      params: {
        'p_contact_id': contactId,
        'p_claimed_user_id': claimedUserId,
      },
    );

    return response == true;
  }
}
