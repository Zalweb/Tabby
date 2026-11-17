import 'dart:convert';

import '../../../core/config/supabase_config.dart';

/// A limited server snapshot, never a substitute for a full ledger export.
class PrivacyExport {
  PrivacyExport({
    required this.accountId,
    required this.captureCurrent,
    required this.fetch,
    this.requestDeletion,
    this.fetchDeletionStatus,
    this.fetchLedgerPage,
  });

  factory PrivacyExport.production() => PrivacyExport(
    accountId: () => SupabaseConfig.currentUserId,
    captureCurrent: () {
      final stamp = SupabaseConfig.captureSession();
      return () => SupabaseConfig.isCurrentSession(stamp);
    },
    fetch: () => SupabaseConfig.client.rpc('export_account_data_v1'),
    requestDeletion: () =>
        SupabaseConfig.client.rpc('request_account_deletion_v1'),
    fetchDeletionStatus: () =>
        SupabaseConfig.client.rpc('get_account_deletion_request_v1'),
    fetchLedgerPage: (section, after) => SupabaseConfig.client.rpc(
      const [
            'receiving_methods',
            'connections',
            'contacts',
            'notifications',
            'reminders',
          ].contains(section)
          ? 'export_private_page_v1'
          : 'export_ledger_page_v1',
      params: {'p_section': section, 'p_after': after, 'p_limit': 50},
    ),
  );

  final String? Function() accountId;
  final bool Function() Function() captureCurrent;
  final Future<dynamic> Function() fetch;
  final Future<dynamic> Function()? requestDeletion;
  final Future<dynamic> Function()? fetchDeletionStatus;
  final Future<dynamic> Function(String section, String? after)?
  fetchLedgerPage;
  bool _busy = false;

  static const ledgerSections = [
    'tabs',
    'expenses',
    'shares',
    'payments',
    'receiving_methods',
    'connections',
    'contacts',
    'notifications',
    'reminders',
  ];

  Future<Map<String, dynamic>?> deletionStatus() async {
    final current = captureCurrent();
    final fetchStatus = fetchDeletionStatus;
    if (fetchStatus == null) throw StateError('Status is unavailable.');
    final result = await _readScoped(fetchStatus);
    if (!current()) throw StateError('The account changed.');
    if (result == null) return null;
    return _validateRequest(result);
  }

  Map<String, dynamic> _validateRequest(dynamic result) {
    if (result is! Map ||
        result['account_id'] != accountId() ||
        result['id'] is! String ||
        (result['id'] as String).isEmpty ||
        !const [
          'requested',
          'processing',
          'completed',
        ].contains(result['status'])) {
      throw const FormatException('Invalid deletion request acknowledgment.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<dynamic> _readScoped(Future<dynamic> Function() read) async {
    if (_busy) throw StateError('A privacy request is already running.');
    final actor = accountId();
    final current = captureCurrent();
    if (actor == null || !current()) throw StateError('Sign in again.');
    _busy = true;
    try {
      final result = await read();
      if (!current() || accountId() != actor) {
        throw StateError('The account changed.');
      }
      return result;
    } finally {
      _busy = false;
    }
  }

  Future<Map<String, dynamic>> ledgerPage(
    String section, {
    String? after,
  }) async {
    final actor = accountId();
    final current = captureCurrent();
    final read = fetchLedgerPage;
    if (!ledgerSections.contains(section) || read == null) {
      throw ArgumentError('Unsupported ledger section.');
    }
    final result = await _readScoped(() => read(section, after));
    if (!current() || accountId() != actor) {
      throw StateError('The account changed.');
    }
    if (result is! Map ||
        result['version'] != 1 ||
        result['account_id'] != actor ||
        result['section'] != section ||
        result['records'] is! List ||
        result['records'].length > 50) {
      throw const FormatException('Invalid ledger export page.');
    }
    final records = result['records'] as List;
    String? previous = after;
    for (final record in records) {
      if (record is! Map ||
          record['id'] is! String ||
          !RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          ).hasMatch(record['id'] as String) ||
          (previous != null &&
              (record['id'] as String).compareTo(previous) <= 0)) {
        throw const FormatException('Invalid ledger record order.');
      }
      previous = record['id'] as String;
    }
    final cursor = result['next_cursor'];
    if (cursor != null && (records.isEmpty || cursor != previous)) {
      throw const FormatException('Invalid ledger export cursor.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> submitDeletionRequest() async {
    if (_busy) throw StateError('A privacy request is already running.');
    final actor = accountId();
    final current = captureCurrent();
    final submit = requestDeletion;
    if (actor == null || !current() || submit == null) {
      throw StateError('Sign in again before requesting deletion.');
    }
    _busy = true;
    try {
      final result = await submit();
      if (!current() || accountId() != actor) {
        throw StateError('The account changed.');
      }
      return _validateRequest(result);
    } finally {
      _busy = false;
    }
  }

  Future<String> load() async {
    if (_busy) throw StateError('An export is already being prepared.');
    final actor = accountId();
    final current = captureCurrent();
    if (actor == null || !current()) {
      throw StateError('Sign in to prepare an export.');
    }
    _busy = true;
    try {
      final response = await fetch();
      if (!current() || accountId() != actor) {
        throw StateError('The account changed. Open privacy controls again.');
      }
      if (response is! Map ||
          response['account_id'] != actor ||
          response['version'] != 1 ||
          response['scope'] != 'profile_and_owned_contacts') {
        throw const FormatException('The server returned an invalid export.');
      }
      return const JsonEncoder.withIndent('  ').convert(response);
    } finally {
      _busy = false;
    }
  }
}
