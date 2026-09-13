import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../domain/models.dart';
import 'mock_tabby_repository.dart';

/// Live Supabase Repository for Tabby.
/// Communicates with Supabase PostgreSQL 15+ backend via PostgREST and GoTrue.
/// Falls back to MockTabbyRepository only when Supabase is not initialized (unit tests / offline).
class SupabaseTabbyRepository {
  SupabaseTabbyRepository._();
  static final SupabaseTabbyRepository instance = SupabaseTabbyRepository._();

  bool get isConnected => SupabaseConfig.isInitialized;

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

  /// Ensures a user row exists in public.users.
  /// For real UUID IDs, upserts the record. For synthetic IDs (non-UUID),
  /// looks up or creates a user by display_name and returns the canonical UUID.
  Future<String> ensureUserExists(String id, String displayName) async {
    if (!isConnected) return id;

    if (_isValidUuid(id)) {
      try {
        await SupabaseConfig.client.from(SupabaseConfig.tableUsers).upsert({
          'id': id,
          'display_name': displayName,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'id');
      } catch (e) {
        debugPrint('[SupabaseTabbyRepository] ensureUserExists upsert warning: $e');
      }
      return id;
    }

    // Synthetic ID: find or create by display_name
    try {
      final existing = await SupabaseConfig.client
          .from(SupabaseConfig.tableUsers)
          .select('id')
          .eq('display_name', displayName)
          .maybeSingle();
      if (existing != null && existing['id'] != null) {
        return existing['id'] as String;
      }
      final inserted = await SupabaseConfig.client
          .from(SupabaseConfig.tableUsers)
          .insert({'display_name': displayName})
          .select('id')
          .maybeSingle();
      if (inserted != null && inserted['id'] != null) {
        return inserted['id'] as String;
      }
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] ensureUserExists synthetic warning: $e');
    }
    return id;
  }

  // ---------------------------------------------------------------------------
  // Authentication
  // ---------------------------------------------------------------------------

  /// Sign up with Email and Password
  Future<AuthResponse?> signUp({
    required String email,
    required String password,
    required String displayName,
    required String phone,
  }) async {
    if (!isConnected) return null;

    try {
      final response = await SupabaseConfig.auth.signUp(
        email: email,
        password: password,
        data: {
          'display_name': displayName,
          'phone': phone,
        },
      );

      if (response.user != null) {
        try {
          await SupabaseConfig.client.from(SupabaseConfig.tableUsers).upsert({
            'id': response.user!.id,
            'display_name': displayName,
            'phone': phone,
            'email': email,
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'id');
        } catch (e) {
          debugPrint('[SupabaseTabbyRepository] Profile table sync note: $e');
        }
      }

      return response;
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] Sign up error: $e');
      rethrow;
    }
  }

  /// Sign in with Email and Password
  Future<AuthResponse?> signIn({
    required String email,
    required String password,
  }) async {
    if (!isConnected) return null;

    try {
      final response = await SupabaseConfig.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return response;
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] Sign in error: $e');
      rethrow;
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

    // ── Native iOS / Android: native Google Sign-In SDK ──────────────────────
    try {
      // Read compile-time client IDs injected via --dart-define
      const iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
      const androidClientId = String.fromEnvironment('GOOGLE_ANDROID_CLIENT_ID');

      final googleSignIn = GoogleSignIn(
        clientId: iosClientId.isNotEmpty ? iosClientId : null,
        serverClientId: androidClientId.isNotEmpty ? androidClientId : null,
        scopes: ['email', 'profile'],
      );

      // Trigger native account picker
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        // User cancelled the picker
        debugPrint('[SupabaseTabbyRepository] Google sign-in cancelled by user.');
        return false;
      }

      // Obtain auth tokens from Google
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null) {
        debugPrint('[SupabaseTabbyRepository] Google sign-in: idToken is null.');
        return false;
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
      debugPrint('[SupabaseTabbyRepository] Native Google sign-in error: $e');
      rethrow;
    }
  }


  /// Sign out
  Future<void> signOut() async {
    if (!isConnected) return;
    try {
      await SupabaseConfig.auth.signOut();
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] Sign out error: $e');
    }
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
            'id, tab_type, status, created_at, updated_at,'
            'tab_members ('
            '  user_id,'
            '  users ( id, display_name, email, phone )'
            '),'
            'transactions ('
            '  id, created_by, transaction_type, category, description,'
            '  total_amount_centavos, currency, due_date, status, created_at,'
            '  transaction_participants ('
            '    user_id, participant_role, share_amount_centavos, acknowledged'
            '  )'
            '),'
            'payments ('
            '  id, submitted_by, amount_centavos, payment_method, note, status, submitted_at'
            ')',
          )
          .or('user_a.eq.$currentUserId,user_b.eq.$currentUserId');

      if (tabsData.isEmpty) {
        return [];
      }

      final List<BilateralTab> loadedTabs = [];

      for (final tabRow in tabsData) {
        final tabId = tabRow['id'] as String? ?? '';
        if (tabId.isEmpty) continue;

        // Find counterpart member (anyone who is not the current user)
        final membersList = (tabRow['tab_members'] as List<dynamic>?) ?? [];
        Map<String, dynamic>? counterpartMember;
        for (final m in membersList) {
          if ((m as Map<String, dynamic>)['user_id'] != currentUserId) {
            counterpartMember = m;
            break;
          }
        }

        if (counterpartMember == null) continue;

        final counterpartUserId = counterpartMember['user_id'] as String? ?? '';
        final counterpartUserRow =
            counterpartMember['users'] as Map<String, dynamic>?;

        final counterpart = TabbyUser(
          id: counterpartUserId,
          displayName:
              counterpartUserRow?['display_name'] as String? ?? 'Friend',
          email: counterpartUserRow?['email'] as String? ?? '',
          phone: counterpartUserRow?['phone'] as String? ?? '',
        );

        // Build ledger entries from transactions
        final List<LedgerEntry> entries = [];

        final txList = (tabRow['transactions'] as List<dynamic>?) ?? [];
        for (final txRaw in txList) {
          final tx = txRaw as Map<String, dynamic>;
          final pList =
              (tx['transaction_participants'] as List<dynamic>?) ?? [];
          int myShare = 0;
          int counterpartShare = 0;

          for (final pRaw in pList) {
            final p = pRaw as Map<String, dynamic>;
            final pUserId = p['user_id'] as String?;
            final shareAmt = (p['share_amount_centavos'] as num?)?.toInt() ?? 0;
            if (pUserId == currentUserId) {
              myShare = shareAmt;
            } else if (pUserId == counterpart.id) {
              counterpartShare = shareAmt;
            }
          }

          final dateStr = tx['created_at'] as String?;
          final dueDateStr = tx['due_date'] as String?;
          final totalAmt =
              (tx['total_amount_centavos'] as num?)?.toInt() ?? 0;
          final createdBy = tx['created_by'] as String? ?? '';

          entries.add(LedgerEntry(
            id: tx['id'] as String? ?? 'tx-$tabId',
            tabId: tabId,
            title: tx['description'] as String? ?? '',
            category: _unmapCategory(tx['category']),
            totalAmountCentavos: totalAmt,
            myShareCentavos: myShare,
            counterpartShareCentavos: counterpartShare,
            paidByUserId: createdBy,
            paidByName:
                createdBy == currentUserId ? 'You' : counterpart.displayName,
            date: dateStr != null
                ? DateTime.tryParse(dateStr) ?? DateTime.now()
                : DateTime.now(),
            dueDate: dueDateStr != null ? DateTime.tryParse(dueDateStr) : null,
            status: _unmapTransactionStatus(tx['status']),
          ));
        }

        // Build ledger entries from payments
        final payList = (tabRow['payments'] as List<dynamic>?) ?? [];
        for (final payRaw in payList) {
          final pay = payRaw as Map<String, dynamic>;
          final submittedBy = pay['submitted_by'] as String? ?? '';
          final isCounterpartPaying = submittedBy == counterpart.id;
          final dateStr = pay['submitted_at'] as String?;
          final payAmt = (pay['amount_centavos'] as num?)?.toInt() ?? 0;

          entries.add(LedgerEntry(
            id: pay['id'] as String? ?? 'pay-$tabId',
            tabId: tabId,
            title: isCounterpartPaying
                ? '${counterpart.displayName} paid'
                : 'You paid',
            category: ExpenseCategory.borrowedCash,
            totalAmountCentavos: payAmt,
            myShareCentavos: 0,
            counterpartShareCentavos: 0,
            paidByUserId: submittedBy,
            paidByName:
                isCounterpartPaying ? counterpart.displayName : 'You',
            date: dateStr != null
                ? DateTime.tryParse(dateStr) ?? DateTime.now()
                : DateTime.now(),
            status: TransactionStatus.settled,
            isPayment: true,
            paymentMethod: _unmapPaymentMethod(pay['payment_method']),
            note: pay['note'] as String?,
          ));
        }

        // Sort entries newest-first
        entries.sort((a, b) => b.date.compareTo(a.date));

        // Fetch live RPC balance for this tab
        int netBalance = 0;
        try {
          netBalance = await SupabaseConfig.getNetBalance(
            tabId: tabId,
            userId: currentUserId,
          );
        } catch (e) {
          debugPrint(
              '[SupabaseTabbyRepository] getNetBalance error for $tabId: $e');
        }

        final lastUpdatedStr = tabRow['updated_at'] as String? ??
            tabRow['created_at'] as String?;

        loadedTabs.add(BilateralTab(
          id: tabId,
          counterpart: counterpart,
          netBalanceCentavos: netBalance,
          itemCount: entries.length,
          entries: entries,
          lastUpdated: lastUpdatedStr != null
              ? DateTime.tryParse(lastUpdatedStr) ?? DateTime.now()
              : DateTime.now(),
        ));
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
  }) async {
    if (!isConnected) return;

    try {
      final inserted = await SupabaseConfig.client
          .from(SupabaseConfig.tableTransactions)
          .insert({
            'tab_id': tabId,
            'created_by': paidByUserId,
            'transaction_type': 'shared_expense',
            'category': _mapCategory(category),
            'description': title.isEmpty ? category.displayName : title,
            'total_amount_centavos': totalAmountCentavos,
            'currency': 'PHP',
            'status': 'acknowledged',
            if (dueDate != null)
              'due_date': dueDate.toIso8601String().split('T')[0],
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

        // Debtor participant
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
  }) async {
    if (!isConnected) return;

    // Only insert if tabId is a valid UUID (bilateral tabs created via RPC return UUIDs)
    if (!_isValidUuid(tabId)) {
      debugPrint(
          '[SupabaseTabbyRepository] recordPayment skipped: tabId is not a valid UUID');
      return;
    }

    try {
      await SupabaseConfig.client.from(SupabaseConfig.tablePayments).insert({
        'tab_id': tabId,
        'submitted_by': paidByUserId,
        'amount_centavos': amountCentavos,
        'payment_method': _mapPaymentMethod(method),
        if (note != null && note.isNotEmpty) 'note': note,
        'status': 'confirmed',
      });
    } catch (e) {
      debugPrint('[SupabaseTabbyRepository] recordPayment error: $e');
    }
  }
}
