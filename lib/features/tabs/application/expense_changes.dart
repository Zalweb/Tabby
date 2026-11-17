import 'package:uuid/uuid.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/services/form_draft_store.dart';

class ExpenseChanges {
  ExpenseChanges(
      {required this.owner,
      required this.current,
      required this.rpc,
      this.drafts = const FormDraftStore(),
      String Function()? operationId})
      : operationId = operationId ?? const Uuid().v4;

  factory ExpenseChanges.production() {
    final stamp = SupabaseConfig.captureSession();
    return ExpenseChanges(
        owner: stamp.accountId ?? '',
        current: () => SupabaseConfig.isCurrentSession(stamp),
        rpc: (name, params) => SupabaseConfig.client.rpc(name, params: params));
  }

  final String owner;
  final bool Function() current;
  final Future<dynamic> Function(String, Map<String, dynamic>) rpc;
  final FormDraftStore drafts;
  final String Function() operationId;
  bool _busy = false;
  bool cleanupPending = false;
  bool canRequest = false;
  bool manualContact = false;
  String _purpose(String transactionId) => 'expense-change:$transactionId';

  void _check() {
    if (owner.isEmpty || !current()) throw StateError('The account changed.');
  }

  Future<T> _run<T>(Future<T> Function() work) async {
    _check();
    if (_busy) throw StateError('An expense change is already running.');
    _busy = true;
    try {
      return await work();
    } finally {
      _busy = false;
    }
  }

  Future<Map<String, dynamic>?> pending(String transactionId) => _run(() async {
        final saved = await drafts.read(owner, _purpose(transactionId));
        _check();
        if (saved != null) {
          final command = saved['command'];
          if (saved['operation_id'] is! String ||
              (saved['operation_id'] as String).isEmpty ||
              command is! Map ||
              command['p_transaction_id'] != transactionId ||
              (command['p_contact_agreement'] != null &&
                  command['p_contact_agreement'] is! bool) ||
              !const ['correct', 'cancel'].contains(command['p_kind']) ||
              command['p_reason'] is! String ||
              (command['p_reason'] as String).trim().isEmpty ||
              (command['p_reason'] as String).length > 500 ||
              (command['p_kind'] == 'correct' &&
                  (command['p_new_total'] is! int ||
                      command['p_new_total'] <= 0 ||
                      command['p_new_total'] > 99999999999)) ||
              (command['p_kind'] == 'cancel' &&
                  command['p_new_total'] != null)) {
            throw const FormatException('Invalid saved change.');
          }
        }
        return saved;
      });

  Future<String> request(String transactionId,
          {required String kind,
          required int? newTotal,
          required String reason,
          bool contactAgreement = false}) =>
      _run(() async {
        if (!const ['correct', 'cancel'].contains(kind) ||
            reason.trim().isEmpty ||
            reason.trim().length > 500 ||
            (kind == 'correct' &&
                (newTotal == null ||
                    newTotal <= 0 ||
                    newTotal > 99999999999)) ||
            (kind == 'cancel' && newTotal != null)) {
          throw const FormatException(
              'Choose a valid change and give a reason.');
        }
        final command = <String, dynamic>{
          'p_transaction_id': transactionId,
          'p_kind': kind,
          'p_new_total': newTotal,
          'p_reason': reason.trim()
        };
        if (contactAgreement) command['p_contact_agreement'] = true;
        final purpose = _purpose(transactionId);
        var saved = await drafts.read(owner, purpose);
        _check();
        if (saved == null) {
          saved = {'operation_id': operationId(), 'command': command};
          await drafts.write(owner, purpose, saved);
          _check();
        } else if (saved['operation_id'] is! String ||
            saved['command'] is! Map ||
            (saved['command'] as Map).length != command.length ||
            !command.entries.every((entry) =>
                (saved!['command'] as Map)[entry.key] == entry.value)) {
          throw StateError(
              'Retry the saved change before starting a different one.');
        }
        final id = await rpc(
            contactAgreement
                ? 'request_expense_change_v2'
                : 'request_expense_change_v1',
            {
              'p_expected_actor': owner,
              'p_operation_id': saved['operation_id'],
              ...command
            }).timeout(const Duration(seconds: 30));
        _check();
        if (id is! String || id.isEmpty) {
          throw const FormatException('Change not acknowledged.');
        }
        cleanupPending = false;
        try {
          await drafts.removeIf(
              owner, purpose, 'operation_id', saved['operation_id']);
        } catch (_) {
          cleanupPending = true;
        }
        _check();
        return id;
      });

  Future<List<Map<String, dynamic>>> list(String transactionId) =>
      _run(() async {
        canRequest = false;
        final result = await rpc(
            'list_expense_changes_v1', {'p_transaction_id': transactionId});
        _check();
        if (result is! Map ||
            result['account_id'] != owner ||
            result['transaction_id'] != transactionId ||
            result['changes'] is! List ||
            result['can_request'] is! bool) {
          throw const FormatException('Invalid expense change history.');
        }
        final changes = (result['changes'] as List).map((value) {
          if (value is! Map ||
              value['id'] is! String ||
              value['transaction_id'] != transactionId ||
              value['reason'] is! String ||
              value['requested_by'] is! String ||
              (value['reviewer_id'] != null &&
                  value['reviewer_id'] is! String) ||
              !const ['correct', 'cancel'].contains(value['kind']) ||
              (value['kind'] == 'correct' &&
                  (value['new_total_centavos'] is! int ||
                      value['new_total_centavos'] <= 0 ||
                      value['new_total_centavos'] > 99999999999)) ||
              !const ['pending', 'applied', 'rejected', 'superseded']
                  .contains(value['status'])) {
            throw const FormatException('Invalid expense change.');
          }
          return Map<String, dynamic>.from(value);
        }).toList();
        canRequest = result['can_request'] as bool;
        manualContact = result['manual_contact'] == true;
        return changes;
      });

  Future<void> decide(String changeId, {required bool accept}) =>
      _run(() async {
        final result = await rpc('decide_expense_change_v1', {
          'p_expected_actor': owner,
          'p_change_id': changeId,
          'p_accept': accept
        }).timeout(const Duration(seconds: 30));
        _check();
        if (result != changeId) {
          throw const FormatException('Decision not acknowledged.');
        }
      });
}
