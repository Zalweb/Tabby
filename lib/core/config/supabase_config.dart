import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'session_scope.dart';
import '../services/auth_recovery_state.dart';
import '../services/auth_link_failure.dart';
import '../services/serialized_pkce_storage.dart';

/// Type-safe Supabase configuration and initialization service for Tabby.
///
/// Follows ADR-001 (Integer centavos BIGINT) and ADR-011 (Supabase BaaS).
/// Supports compile-time environment flags `--dart-define` as well as runtime initialization.
class SupabaseConfig {
  SupabaseConfig._();
  static final _sessionScope = SessionScope();
  static final sessionRevision = ValueNotifier<int>(0);
  static Uri? _authUserEndpoint;
  static GotrueAsyncStorage? _authPkceStorage;
  static GotrueAsyncStorage get authPkceStorage =>
      _authPkceStorage ??= SerializedPkceStorage(
          delegate: SharedPreferencesGotrueAsyncStorage(),
          captureCurrent: () {
            final stamp = captureSession();
            return () => isCurrentSession(stamp);
          });
  static Uri get authUserEndpoint =>
      _authUserEndpoint ??
      (throw StateError('Authentication is not initialized.'));
  static SessionStamp captureSession() => _sessionScope.capture(currentUserId);
  static bool isCurrentSession(SessionStamp stamp) =>
      _sessionScope.isCurrent(stamp, currentUserId);

  /// Wait for the public SDK auth-event acknowledgment before capturing a
  /// successful sign-in. Its queued signedIn event must advance our generation
  /// before this completion starts, rather than invalidating its own stamp.
  static Future<SessionStamp?> captureAcknowledgedSession(Session expected) async {
    await auth.onAuthStateChange.first;
    if (!identical(auth.currentSession, expected)) return null;
    return captureSession();
  }

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
  static const String rpcGetOrCreateBilateralTab =
      'get_or_create_bilateral_tab';
  static const String rpcValidateTransactionSplit =
      'validate_transaction_split';
  static const String rpcFindUserByFriendCode = 'find_user_by_friend_code';
  static const String rpcSendFriendRequest = 'send_friend_request';
  static const String rpcListFriendRequests = 'list_friend_requests';
  static const String rpcRespondFriendRequest = 'respond_friend_request';
  static const String rpcListPaymentMethodsForTab =
      'list_payment_methods_for_tab';
  static const String rpcCreateExpenseAtomic = 'create_expense_atomic';
  static const String rpcSubmitPayment = 'submit_payment';
  static const String rpcCreateExpenseV1 = 'create_expense_v1';
  static const String rpcSubmitPaymentV1 = 'submit_payment_v1';
  static const String rpcConfirmPayment = 'confirm_payment';

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
        authOptions:
            FlutterAuthClientOptions(pkceAsyncStorage: authPkceStorage),
        debug: debug,
      );
      _initialized = true;
      _authUserEndpoint = Uri.parse(
          '${effectiveUrl.replaceFirst(RegExp(r'/+$'), '')}/auth/v1/user');
      _sessionScope.advance(currentUserId);
      auth.onAuthStateChange.listen((event) {
        if (event.event == AuthChangeEvent.signedIn ||
            event.event == AuthChangeEvent.signedOut ||
            event.event == AuthChangeEvent.passwordRecovery) {
          _sessionScope.advance(event.session?.user.id);
          sessionRevision.value++;
        } else {
          _sessionScope.capture(event.session?.user.id);
        }
        unawaited(AuthRecoveryState.instance.observe(
            account: event.session?.user.id,
            session: AuthRecoveryState.sessionIdFromToken(
                event.session?.accessToken ?? ''),
            recovery: event.event == AuthChangeEvent.passwordRecovery,
            signedOut: event.event == AuthChangeEvent.signedOut));
      }, onError: (Object error, StackTrace stack) {
        if (isAuthLinkFailure(error)) {
          AuthRecoveryState.instance.reportInvalidLink();
        }
      });
      await AuthRecoveryState.instance.observe(
          account: currentUserId,
          session: AuthRecoveryState.sessionIdFromToken(
              auth.currentSession?.accessToken ?? ''));
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

  /// Debug override for testing authenticated user ID without active network session.
  static String? debugUserIdOverride;

  /// Current authenticated user ID (or null if unauthenticated).
  static String? get currentUserId =>
      debugUserIdOverride ?? (isInitialized ? auth.currentUser?.id : null);

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
    final parsed = int.tryParse(response.toString());
    if (parsed == null) throw const FormatException('Invalid server balance.');
    return parsed;
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
}
