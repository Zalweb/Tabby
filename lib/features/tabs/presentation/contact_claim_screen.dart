import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/widgets/account_draft_guard.dart';
import '../../../core/utils/currency_formatter.dart';
import '../application/m2_saved_action.dart';
import '../data/m2_command_queue.dart';
import '../data/m2_queries.dart';

class ContactClaimInvite extends StatefulWidget {
  const ContactClaimInvite({
    super.key,
    required this.contactId,
    required this.tabId,
    required this.queue,
    this.queries,
  });
  final String contactId, tabId;
  final M2CommandQueue queue;
  final M2Queries? queries;
  @override
  State<ContactClaimInvite> createState() => _ContactClaimInviteState();
}

class _ContactClaimInviteState extends State<ContactClaimInvite> {
  late final _queries = widget.queries ?? M2Queries.production();
  late final _action = M2SavedAction(
    queue: widget.queue,
    purpose: 'claim:${widget.contactId}:${widget.tabId}',
    scope: {'contact_id': widget.contactId, 'source_tab_id': widget.tabId},
  );
  final _code = TextEditingController();
  Map<String, dynamic>? _target, _snapshot;
  String? _message;
  bool _busy = true, _consent = false, _failed = false, _done = false;
  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      await _action.restore();
      if (!mounted || !widget.queue.current()) return;
      if (_action.pending != null) {
        _target = {'id': _action.pending!['command']['target_id']};
      } else {
        final p = await _queries.read(
          'contact_claim_preview_v1',
          {'p_contact_id': widget.contactId, 'p_source_tab_id': widget.tabId},
          scope: {
            'contact_id': widget.contactId,
            'source_tab_id': widget.tabId,
          },
        );
        _snapshot = Map<String, dynamic>.from(p['snapshot']);
      }
    } catch (_) {
      _failed = true;
      _message = 'History or saved request unavailable. Close and retry.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _lookup() async {
    setState(() => _busy = true);
    try {
      if (_queries.actor != widget.queue.actor) {
        throw StateError('Account changed');
      }
      final value = await _queries.read('find_claim_target_v1', {
        'p_friend_code': _code.text.trim(),
      });
      if (!mounted || !widget.queue.current()) return;
      setState(() {
        _target = value['target'] == null
            ? null
            : Map<String, dynamic>.from(value['target']);
        _consent = false;
        _message = _target == null ? 'No eligible account found.' : null;
      });
    } catch (_) {
      if (mounted) setState(() => _message = 'Account lookup unavailable.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      final r = _action.pending != null
          ? await _action.retry()
          : await _action.send('invite_contact_claim_v1', {
              'claim_id': const Uuid().v4(),
              'contact_id': widget.contactId,
              'source_tab_id': widget.tabId,
              'target_id': _target!['id'],
              'snapshot_digest': _snapshot!['digest'],
            });
      if (mounted && widget.queue.current()) {
        setState(() {
          _message = r.message;
          _done = r.confirmed;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Not confirmed. Retry the saved invitation; changed history requires a fresh review.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.queue.current()) return const SizedBox.shrink();
    return AccountDraftGuard(
      child: Scaffold(
        appBar: AppBar(title: const Text('Invite contact claim')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Select the exact registered account using their Tabby friend code. The recipient must consent. Accepting retains the original history and transfers its net balance to your registered tab.',
            ),
            if (_snapshot != null)
              Text(
                'Current balance owed to you: ${CurrencyFormatter.formatCentavos(_snapshot!['owner_net_centavos'] as int)}',
              ),
            if (_action.pending == null) ...[
              TextField(
                controller: _code,
                decoration: const InputDecoration(
                  labelText: 'Tabby friend code',
                ),
                enabled: !_busy && !_done,
                onChanged: (_) => setState(() {
                  _target = null;
                  _consent = false;
                }),
              ),
              TextButton(
                onPressed: _busy || _done ? null : _lookup,
                child: const Text('Find exact account'),
              ),
            ],
            if (_target != null) ...[
              Text('Recipient: ${_target!['display_name'] ?? _target!['id']}'),
              Text('Account ID: ${_target!['id']}'),
              CheckboxListTile(
                value: _consent,
                onChanged: _busy || _action.pending != null || _done
                    ? null
                    : (v) => setState(() => _consent = v ?? false),
                title: const Text(
                  'I intend to share this contact history with this exact account.',
                ),
              ),
            ],
            if (_message != null) Text(_message!),
            FilledButton(
              onPressed:
                  _busy ||
                      _failed ||
                      _done ||
                      (_action.pending == null &&
                          (!_consent || _target == null))
                  ? null
                  : _send,
              child: Text(
                _action.pending != null
                    ? 'Retry saved invitation'
                    : 'Send invitation',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ContactClaimInbox extends StatefulWidget {
  const ContactClaimInbox({super.key, required this.queue, this.queries});
  final M2CommandQueue queue;
  final M2Queries? queries;
  @override
  State<ContactClaimInbox> createState() => _ContactClaimInboxState();
}

class _ContactClaimInboxState extends State<ContactClaimInbox> {
  late final _queries = widget.queries ?? M2Queries.production();
  final _records = <Map<String, dynamic>>[];
  String? _cursor, _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (_busy || !widget.queue.current()) return;
    setState(() => _busy = true);
    try {
      if (_queries.actor != widget.queue.actor) {
        throw StateError('Account changed');
      }
      final p = await _queries.read('list_contact_claims_v1', {
        'p_after': more ? _cursor : null,
      });
      if (!mounted || !widget.queue.current()) return;
      setState(() {
        if (!more) _records.clear();
        _records.addAll(
          (p['records'] as List).map((v) => Map<String, dynamic>.from(v)),
        );
        _cursor = p['next_cursor'];
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Invitations unavailable. Retry refresh.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.queue.current()) return const SizedBox.shrink();
    return AccountDraftGuard(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Contact claims'),
          actions: [
            IconButton(
              onPressed: _busy ? null : () => _load(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: ListView(
          children: [
            if (_error != null) Text(_error!),
            for (final c in _records)
              ListTile(
                title: Text(c['status'] as String),
                subtitle: Text(
                  'Owner: ${c['owner_id']}\nRecipient: ${c['target_id']}',
                ),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ContactClaimDecision(
                        claim: c,
                        queue: widget.queue,
                        queries: _queries,
                      ),
                    ),
                  );
                  if (mounted) _load();
                },
              ),
            if (_cursor != null)
              TextButton(
                onPressed: _busy ? null : () => _load(more: true),
                child: const Text('More invitations'),
              ),
          ],
        ),
      ),
    );
  }
}

class ContactClaimDecision extends StatefulWidget {
  const ContactClaimDecision({
    super.key,
    required this.claim,
    required this.queue,
    required this.queries,
  });
  final Map<String, dynamic> claim;
  final M2CommandQueue queue;
  final M2Queries queries;
  @override
  State<ContactClaimDecision> createState() => _ContactClaimDecisionState();
}

class _ContactClaimDecisionState extends State<ContactClaimDecision> {
  late final _action = M2SavedAction(
    queue: widget.queue,
    purpose: 'claim-decision:${widget.claim['id']}',
    scope: {'claim_id': widget.claim['id']},
  );
  bool _consent = false, _busy = true, _done = false, _failed = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      await _action.restore();
    } catch (_) {
      _failed = true;
      _message = 'Saved decision cannot be restored.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(bool accept) async {
    setState(() => _busy = true);
    try {
      final r = _action.pending != null
          ? await _action.retry()
          : await _action.send('decide_contact_claim_v1', {
              'claim_id': widget.claim['id'],
              'accept': accept,
              'snapshot_digest': widget.claim['snapshot']['digest'],
            });
      if (mounted && widget.queue.current()) {
        setState(() {
          _message = r.message;
          _done = r.confirmed;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Not confirmed. Retry the saved decision. If history changed, ask the owner for a new invitation.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.queue.current()) return const SizedBox.shrink();
    final c = widget.claim;
    return AccountDraftGuard(
      child: Scaffold(
        appBar: AppBar(title: const Text('Review contact claim')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Invited account: ${c['target_id']}\nOwner: ${c['owner_id']}\nStatus: ${c['status']}',
            ),
            Text(
              'Balance owed to the owner: ${CurrencyFormatter.formatCentavos(c['snapshot']['owner_net_centavos'] as int)}. A negative amount means the owner owes you.',
            ),
            const Text(
              'Accepting links this contact to your account, retains the original entries and payments, closes the old contact ledger and appends its net balance to your registered tab. Declining changes neither identity nor balances.',
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ContactClaimHistory(
                    claimId: c['id'] as String,
                    queue: widget.queue,
                    queries: widget.queries,
                  ),
                ),
              ),
              child: const Text('Review expenses and payments'),
            ),
            if (c['status'] == 'pending' &&
                c['target_id'] == widget.queue.actor) ...[
              CheckboxListTile(
                value: _consent,
                onChanged: _busy || _done || _action.pending != null
                    ? null
                    : (v) => setState(() => _consent = v ?? false),
                title: const Text(
                  'This is my history. I consent to this link and balance transfer.',
                ),
              ),
              if (_action.pending != null)
                FilledButton(
                  onPressed: _busy || _done || _failed
                      ? null
                      : () => _decide(false),
                  child: const Text('Retry saved decision'),
                )
              else
                Row(
                  children: [
                    TextButton(
                      onPressed: _busy || _done || _failed
                          ? null
                          : () => _decide(false),
                      child: const Text('Decline'),
                    ),
                    FilledButton(
                      onPressed: _busy || _done || _failed || !_consent
                          ? null
                          : () => _decide(true),
                      child: const Text('Accept claim'),
                    ),
                  ],
                ),
            ],
            if (_message != null) Text(_message!),
          ],
        ),
      ),
    );
  }
}

class ContactClaimHistory extends StatefulWidget {
  const ContactClaimHistory({
    super.key,
    required this.claimId,
    required this.queue,
    required this.queries,
  });
  final String claimId;
  final M2CommandQueue queue;
  final M2Queries queries;
  @override
  State<ContactClaimHistory> createState() => _ContactClaimHistoryState();
}

class _ContactClaimHistoryState extends State<ContactClaimHistory> {
  final _records = <Map<String, dynamic>>[];
  String? _cursor, _message;
  bool _payments = false, _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (_busy || !widget.queue.current()) return;
    setState(() => _busy = true);
    try {
      if (widget.queries.actor != widget.queue.actor) {
        throw StateError('Account changed');
      }
      final p = await widget.queries.read(
        _payments
            ? 'contact_claim_payments_page_v1'
            : 'contact_claim_history_page_v1',
        {'p_claim_id': widget.claimId, 'p_after': more ? _cursor : null},
        scope: {'claim_id': widget.claimId},
      );
      if (!mounted || !widget.queue.current()) return;
      setState(() {
        if (!more) _records.clear();
        _records.addAll(
          (p['records'] as List).map((v) => Map<String, dynamic>.from(v)),
        );
        _cursor = p['next_cursor'];
        _message = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'History unavailable. Retry refresh.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.queue.current()) return const SizedBox.shrink();
    return AccountDraftGuard(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Retained history'),
          actions: [
            IconButton(
              onPressed: _busy ? null : () => _load(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: ListView(
          children: [
            SwitchListTile(
              title: const Text('Show payments'),
              value: _payments,
              onChanged: _busy
                  ? null
                  : (v) {
                      setState(() {
                        _payments = v;
                        _records.clear();
                        _cursor = null;
                      });
                      _load();
                    },
            ),
            if (_message != null) Text(_message!),
            for (final r in _records)
              ListTile(
                title: Text(_payments ? 'Payment' : r['description'] as String),
                subtitle: Text(
                  '${r['status']} • ${r['created_at']}\n${r['participants'] ?? r['payer_user_id'] ?? r['payer_contact_id'] ?? ''}',
                ),
                trailing: Text(
                  CurrencyFormatter.formatCentavos(
                    (r[_payments ? 'amount_centavos' : 'total_amount_centavos'])
                        as int,
                  ),
                ),
              ),
            if (_cursor != null)
              TextButton(
                onPressed: _busy ? null : () => _load(more: true),
                child: const Text('More history'),
              ),
          ],
        ),
      ),
    );
  }
}
