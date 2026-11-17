import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/account_draft_guard.dart';
import '../application/m2_saved_action.dart';
import '../data/m2_command_queue.dart';
import '../data/m2_queries.dart';

class ExpenseReviewScreen extends StatefulWidget {
  const ExpenseReviewScreen({
    super.key,
    required this.transactionId,
    required this.queue,
    this.queries,
  });
  final String transactionId;
  final M2CommandQueue queue;
  final M2Queries? queries;
  @override
  State<ExpenseReviewScreen> createState() => _ExpenseReviewScreenState();
}

class _ExpenseReviewScreenState extends State<ExpenseReviewScreen> {
  late final _queries = widget.queries ?? M2Queries.production();
  Map<String, dynamic>? _state;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_busy || !widget.queue.current()) return;
    setState(() => _busy = true);
    try {
      if (_queries.actor != widget.queue.actor) {
        throw StateError('Account changed');
      }
      final data = await _queries.read(
        'expense_review_state_v1',
        {'p_transaction_id': widget.transactionId},
        scope: {'transaction_id': widget.transactionId},
      );
      if (mounted && widget.queue.current()) {
        setState(() {
          _state = data;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Expense review unavailable. Retry refresh.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _action(
    String action, {
    Map<String, dynamic> resource = const {},
    String? summary,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExpenseReviewAction(
          transactionId: widget.transactionId,
          queue: widget.queue,
          action: action,
          resource: resource,
          summary:
              '${_state!['expense']['description']} • ${CurrencyFormatter.formatCentavos(_state!['expense']['total_centavos'] as int)}\n${summary ?? ''}',
        ),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.queue.current()) return const SizedBox.shrink();
    final state = _state;
    return AccountDraftGuard(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Expense review'),
          actions: [
            IconButton(
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Recorded expenses affect balances. Acknowledgment is a separate attestation. Proposals need the frozen parties’ approvals; opening or resolving a dispute leaves balances unchanged. Financial adjustments use the approved proposal workflow.',
            ),
            if (_error != null) Text(_error!),
            if (state != null) ...[
              Text(
                '${state['expense']['description']} • ${CurrencyFormatter.formatCentavos(state['expense']['total_centavos'] as int)}',
              ),
              const Text('Acknowledgments'),
              for (final a in state['acknowledgments'] as List)
                ListTile(
                  title: Text(a['actor_id'] as String),
                  subtitle: Text(
                    a['required'] == false
                        ? 'Creator (not a counterpart acknowledgment)'
                        : a['acknowledged'] == true
                        ? 'Acknowledged'
                        : 'Awaiting acknowledgment',
                  ),
                ),
              if (state['can_acknowledge'] == true)
                FilledButton(
                  onPressed: () => _action('acknowledge'),
                  child: const Text('Acknowledge this recorded expense'),
                ),
              if (state['can_propose'] == true)
                TextButton(
                  onPressed: () => _action('propose'),
                  child: const Text('Propose correction or cancellation'),
                ),
              const Text('Latest 50 proposals'),
              for (final p in state['proposals'] as List)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${p['kind']} • ${p['status']}'),
                        Text(p['reason'] as String),
                        if (p['new_total_centavos'] != null)
                          Text(
                            'Proposed total: ${CurrencyFormatter.formatCentavos(p['new_total_centavos'] as int)}',
                          ),
                        Text(
                          '${p['accepted_reviewers']} / ${p['required_reviewers']} reviewer approvals',
                        ),
                        if (p['can_review'] == true)
                          Wrap(
                            children: [
                              TextButton(
                                onPressed: () => _action(
                                  'decide_proposal',
                                  resource: {
                                    'change_id': p['id'],
                                    'accept': false,
                                  },
                                  summary: p['reason'] as String,
                                ),
                                child: const Text('Reject proposal'),
                              ),
                              FilledButton(
                                onPressed: () => _action(
                                  'decide_proposal',
                                  resource: {
                                    'change_id': p['id'],
                                    'accept': true,
                                  },
                                  summary:
                                      'Approve ${p['kind']}: ${p['new_total_centavos'] == null ? 'cancel' : CurrencyFormatter.formatCentavos(p['new_total_centavos'] as int)}. ${p['reason']}',
                                ),
                                child: const Text('Approve proposal'),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              if (state['can_dispute'] == true)
                TextButton(
                  onPressed: () => _action('open_dispute'),
                  child: const Text('Open a dispute'),
                ),
              const Text('Open and recent disputes (up to 50)'),
              for (final d in state['disputes'] as List)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Dispute: ${d['status']}'),
                        Text(d['reason'] as String),
                        Text(
                          'Required parties: ${(d['required_parties'] as List).join(', ')}',
                        ),
                        for (final r in d['resolutions'] as List) ...[
                          Text('${r['resolution']} • ${r['status']}'),
                          Text(
                            '${r['accepted_count']} / ${(d['required_parties'] as List).length} approvals',
                          ),
                          if (d['status'] == 'open' &&
                              r['status'] == 'pending' &&
                              r['my_vote'] == null)
                            Wrap(
                              children: [
                                TextButton(
                                  onPressed: () => _action(
                                    'vote_resolution',
                                    resource: {
                                      'dispute_id': d['id'],
                                      'resolution_id': r['id'],
                                      'accept': false,
                                    },
                                    summary: r['resolution'] as String,
                                  ),
                                  child: const Text('Reject resolution'),
                                ),
                                FilledButton(
                                  onPressed: () => _action(
                                    'vote_resolution',
                                    resource: {
                                      'dispute_id': d['id'],
                                      'resolution_id': r['id'],
                                      'accept': true,
                                    },
                                    summary: r['resolution'] as String,
                                  ),
                                  child: const Text('Agree to resolution'),
                                ),
                              ],
                            ),
                        ],
                        if (d['status'] == 'open' &&
                            !(d['resolutions'] as List).any(
                              (r) => r['status'] == 'pending',
                            ))
                          TextButton(
                            onPressed: () => _action(
                              'propose_resolution',
                              resource: {'dispute_id': d['id']},
                            ),
                            child: const Text('Propose a resolution'),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class ExpenseReviewAction extends StatefulWidget {
  const ExpenseReviewAction({
    super.key,
    required this.transactionId,
    required this.queue,
    required this.action,
    this.resource = const {},
    this.summary,
  });
  final String transactionId, action;
  final M2CommandQueue queue;
  final Map<String, dynamic> resource;
  final String? summary;
  @override
  State<ExpenseReviewAction> createState() => _ExpenseReviewActionState();
}

class _ExpenseReviewActionState extends State<ExpenseReviewAction> {
  late final _action = M2SavedAction(
    queue: widget.queue,
    purpose:
        'expense-review:${widget.transactionId}:${widget.action}:${widget.resource['change_id'] ?? widget.resource['resolution_id'] ?? widget.resource['dispute_id'] ?? 'new'}',
    scope: {
      'transaction_id': widget.transactionId,
      'action': widget.action,
      ...widget.resource,
    },
  );
  final _reason = TextEditingController(), _amount = TextEditingController();
  String _kind = 'correct';
  bool _busy = true, _done = false, _failed = false, _consent = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final saved = await _action.restore();
      if (!mounted || !widget.queue.current()) return;
      final c = saved?['command'];
      if (c != null) {
        _reason.text = c['reason'] ?? c['resolution'] ?? '';
        _kind = c['kind'] ?? 'correct';
        final n = c['new_total_centavos'];
        if (n != null) {
          _amount.text = '${n ~/ 100}.${(n % 100).toString().padLeft(2, '0')}';
        }
      }
    } catch (_) {
      _failed = true;
      _message = 'Saved review request cannot be restored. Close and retry.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> _command() {
    final action = widget.action;
    final c = <String, dynamic>{
      'transaction_id': widget.transactionId,
      'action': action,
      ...widget.resource,
    };
    if (action == 'propose') {
      c.addAll({
        'kind': _kind,
        'new_total_centavos': _kind == 'cancel'
            ? null
            : CurrencyFormatter.parseToCentavos(_amount.text),
        'reason': _reason.text.trim(),
      });
      if (_kind != 'cancel' && (c['new_total_centavos'] as int) <= 0) {
        throw const FormatException('Enter a positive total.');
      }
    }
    if (action == 'open_dispute') {
      c['dispute_id'] = const Uuid().v4();
      c['reason'] = _reason.text.trim();
    }
    if (action == 'propose_resolution') {
      c['resolution_id'] = const Uuid().v4();
      c['resolution'] = _reason.text.trim();
    }
    if (['propose', 'open_dispute', 'propose_resolution'].contains(action) &&
        (_reason.text.trim().isEmpty || _reason.text.trim().length > 500)) {
      throw const FormatException('Enter 1–500 characters.');
    }
    return c;
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      final r = _action.pending != null
          ? await _action.retry()
          : await _action.send('review_expense_v1', _command());
      if (mounted && widget.queue.current()) {
        setState(() {
          _message = r.confirmed
              ? 'Saved by the server. Refresh expense review to see the approval or dispute state.'
              : r.message;
          _done = r.confirmed;
        });
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Not confirmed. Retry the saved review request.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.queue.current()) return const SizedBox.shrink();
    final frozen = _action.pending != null;
    final editable = !_busy && !_done && !frozen;
    return AccountDraftGuard(
      child: Scaffold(
        appBar: AppBar(title: const Text('Confirm expense review')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              widget.action == 'acknowledge'
                  ? 'I acknowledge this exact recorded expense. This is not a payment confirmation.'
                  : widget.action == 'open_dispute'
                  ? 'Explain the dispute. The recorded balance remains.'
                  : widget.action == 'propose_resolution'
                  ? 'Propose a resolution all affected registered parties must agree to. A financial adjustment still requires the separate proposal workflow.'
                  : 'Review the exact request before confirming.',
            ),
            if (widget.summary != null) Text(widget.summary!),
            if (widget.action == 'propose') ...[
              DropdownButtonFormField<String>(
                initialValue: _kind,
                items: const [
                  DropdownMenuItem(
                    value: 'correct',
                    child: Text('Correct amount'),
                  ),
                  DropdownMenuItem(
                    value: 'cancel',
                    child: Text('Cancel expense'),
                  ),
                ],
                onChanged: editable ? (v) => setState(() => _kind = v!) : null,
              ),
              if (_kind == 'correct')
                TextField(
                  controller: _amount,
                  enabled: editable,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Proposed total (PHP)',
                  ),
                ),
            ],
            if ([
              'propose',
              'open_dispute',
              'propose_resolution',
            ].contains(widget.action))
              TextField(
                controller: _reason,
                enabled: editable,
                maxLength: 500,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: widget.action == 'propose_resolution'
                      ? 'Resolution text'
                      : 'Reason',
                ),
              ),
            CheckboxListTile(
              value: _consent,
              onChanged: editable
                  ? (v) => setState(() => _consent = v ?? false)
                  : null,
              title: const Text('I confirm this exact request.'),
            ),
            if (_message != null) Text(_message!),
            FilledButton(
              onPressed: _busy || _done || _failed || (!frozen && !_consent)
                  ? null
                  : _send,
              child: Text(
                frozen ? 'Retry saved review request' : 'Confirm request',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
