import 'package:flutter/material.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/utils/currency_formatter.dart';
import '../application/expense_changes.dart';
import '../domain/models.dart';

class ExpenseChangeScreen extends StatefulWidget {
  const ExpenseChangeScreen(
      {super.key,
      required this.entry,
      required this.service,
      required this.refreshHistory});
  final LedgerEntry entry;
  final ExpenseChanges service;
  final Future<bool> Function() refreshHistory;
  @override
  State<ExpenseChangeScreen> createState() => _ExpenseChangeScreenState();
}

class _ExpenseChangeScreenState extends State<ExpenseChangeScreen> {
  final _reason = TextEditingController();
  late final TextEditingController _amount;
  String _kind = 'correct';
  bool _busy = true;
  bool _frozen = false;
  bool _contactAgreement = false;
  late final String _initialAmount;
  bool _allowExit = false;
  bool _exitDialog = false;
  String? _message;
  List<Map<String, dynamic>> _changes = [];

  @override
  void initState() {
    super.initState();
    final n = widget.entry.totalAmountCentavos;
    _amount = TextEditingController(
        text: '${n ~/ 100}.${(n % 100).toString().padLeft(2, '0')}');
    _initialAmount = _amount.text;
    _reason.addListener(_edited);
    _amount.addListener(_edited);
    SupabaseConfig.sessionRevision.addListener(_changedSession);
    _restore();
  }

  void _edited() {
    if (mounted) setState(() {});
  }

  bool get _dirty =>
      !_frozen &&
      (_reason.text.isNotEmpty ||
          _amount.text != _initialAmount ||
          _contactAgreement ||
          _kind == 'cancel');
  Future<void> _confirmExit() async {
    if (_exitDialog) return;
    _exitDialog = true;
    final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Leave expense changes?'),
              content: const Text(
                  'Unsubmitted edits will be discarded. Saved requests remain available for retry and review.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Keep editing')),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Leave form'))
              ],
            ));
    _exitDialog = false;
    if (leave != true || !mounted || !widget.service.current()) return;
    setState(() => _allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop();
      }
    });
  }

  void _changedSession() {
    if (!widget.service.current() && mounted) {
      _reason.clear();
      _amount.clear();
      setState(() {
        _changes = [];
        _message = null;
      });
    }
  }

  Future<void> _restore() async {
    try {
      final saved = await widget.service.pending(widget.entry.id);
      if (!mounted || !widget.service.current()) return;
      _frozen = saved != null;
      if (saved != null) {
        final command = saved['command'] as Map;
        _kind = command['p_kind'] as String;
        _contactAgreement = command['p_contact_agreement'] == true;
        _reason.text = command['p_reason'] as String;
        final amount = command['p_new_total'] as int?;
        if (amount != null) {
          _amount.text =
              '${amount ~/ 100}.${(amount % 100).toString().padLeft(2, '0')}';
        }
        _frozen = true;
      }
      final changes = await widget.service.list(widget.entry.id);
      if (!mounted || !widget.service.current()) return;
      _changes = changes;
    } catch (_) {
      _message =
          'Could not load change history. Refresh before making changes.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    SupabaseConfig.sessionRevision.removeListener(_changedSession);
    _reason.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !widget.service.current()) return;
    if (widget.service.manualContact && !_contactAgreement) {
      setState(() => _message =
          'Confirm that you agreed this change with the contact outside Tabby.');
      return;
    }
    final amount = _kind == 'cancel'
        ? null
        : CurrencyFormatter.tryParseToCentavos(_amount.text);
    if (_reason.text.trim().isEmpty ||
        (_kind == 'correct' &&
            (amount == null ||
                amount <= 0 ||
                amount == widget.entry.totalAmountCentavos))) {
      setState(() => _message =
          'Give a reason and a different valid total, or choose cancellation.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.service.request(widget.entry.id,
          kind: _kind,
          newTotal: amount,
          reason: _reason.text,
          contactAgreement: widget.service.manualContact && _contactAgreement);
      if (!mounted || !widget.service.current()) return;
      _frozen = widget.service.cleanupPending;
      _message = _frozen
          ? 'Request recorded. Retry to finish local cleanup.'
          : 'Request recorded. Your balance changes only if the other person accepts.';
      if (!_frozen) {
        _reason.clear();
        _amount.text = _initialAmount;
        _kind = 'correct';
        _contactAgreement = false;
      }
      try {
        _changes = await widget.service.list(widget.entry.id);
        if (!mounted || !widget.service.current()) return;
        if (_changes.any((change) => change['status'] == 'applied')) {
          final refreshed = await widget.refreshHistory();
          _message = refreshed
              ? 'Agreed change recorded and applied.'
              : 'Change applied. Refresh the tab to load its latest balance.';
        } else if (widget.entry.participants.length > 2) {
          _message =
              'Request recorded. Every other registered participant must accept before the balance changes.';
        }
      } catch (_) {
        _message = 'Request recorded. Refresh to load its status.';
      }
    } catch (_) {
      try {
        _frozen = await widget.service.pending(widget.entry.id) != null;
      } catch (_) {
        _frozen = true;
      }
      _message = 'Request not confirmed. Retry keeps the same saved change.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(Map<String, dynamic> change, bool accept) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(accept
                  ? 'Accept this expense change?'
                  : 'Reject this expense change?'),
              content: Text(
                  '${change['reason']}\n\n${accept ? 'This appends the agreed reversal and, for a correction, a replacement. The original stays in history.' : 'The original expense and balance stay as they are.'}'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Go back')),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(accept ? 'Accept change' : 'Reject change'))
              ],
            ));
    if (confirmed != true || !mounted || !widget.service.current() || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.service.decide(change['id'] as String, accept: accept);
      if (!mounted || !widget.service.current()) return;
      _message = 'Decision recorded.';
      try {
        final refreshed = await widget.refreshHistory();
        if (!refreshed) {
          _message =
              'Decision recorded. Refresh the tab to load its latest balance.';
        }
        _changes = await widget.service.list(widget.entry.id);
      } catch (_) {
        _message = 'Decision recorded. Refresh to load the latest history.';
      }
    } catch (_) {
      _message = 'Decision not confirmed. Refresh and retry.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.service.current()) {
      return const Scaffold(
          body: Center(
              child: Text('The account changed. Open this expense again.')));
    }
    final applied = _changes
        .any((c) => c['status'] == 'applied' || c['status'] == 'superseded');
    return PopScope<void>(
        canPop: _allowExit || (!_busy && !_dirty),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmExit();
        },
        child: Scaffold(
            appBar: AppBar(title: const Text('Expense changes')),
            body: ListView(padding: const EdgeInsets.all(20), children: [
              Text(widget.entry.title,
                  style: Theme.of(context).textTheme.titleLarge),
              Text(
                  'Original total: ${CurrencyFormatter.formatCentavos(widget.entry.totalAmountCentavos)}'),
              const SizedBox(height: 12),
              Text(widget.service.manualContact
                  ? 'This is a manual contact record. Only record a change you have agreed outside Tabby; the contact cannot review it in the app. Originals and payments stay in history.'
                  : 'Every other registered participant must agree before a balance changes. Originals and payments stay in history.'),
              const Text(
                  'A correction keeps the original payer and split proportion, rounds to centavos with the remainder assigned to the payer, and appends reversals and a replacement.'),
              const SizedBox(height: 12),
              if (_message != null)
                Semantics(liveRegion: true, child: Text(_message!)),
              TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          setState(() => _busy = true);
                          _restore();
                        },
                  child: const Text('Refresh changes')),
              for (final change in _changes)
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  '${change['kind'] == 'cancel' ? 'Cancellation' : 'Correction'} · ${change['status']}'),
                              if (change['new_total_centavos'] is int)
                                Text(
                                    'Proposed total: ${CurrencyFormatter.formatCentavos(change['new_total_centavos'] as int)}'),
                              Text('Reason: ${change['reason']}'),
                              if (change['required_reviewers'] is int)
                                Text(
                                    'Approvals: ${change['accepted_reviewers']} of ${change['required_reviewers']}'),
                              if (change['manual_contact_agreement'] == true)
                                const Text(
                                    'Outside-app agreement recorded by the contact owner.'),
                              if (change['reversal_ids'] is List)
                                for (final id in change['reversal_ids'] as List)
                                  SelectableText('Reversal: $id')
                              else if (change['reversal_id'] != null)
                                SelectableText(
                                    'Reversal: ${change['reversal_id']}'),
                              if (change['replacement_id'] != null)
                                SelectableText(
                                    'Replacement: ${change['replacement_id']}'),
                              if (change['status'] == 'pending' &&
                                  (change['can_review'] == true ||
                                      (change['can_review'] == null &&
                                          change['reviewer_id'] ==
                                              widget.service.owner)))
                                Wrap(spacing: 12, children: [
                                  TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _decide(change, true),
                                      child: const Text('Review and accept')),
                                  TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _decide(change, false),
                                      child: const Text('Review and reject'))
                                ]),
                            ]))),
              if (!applied && widget.service.canRequest) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                    initialValue: _kind,
                    decoration:
                        const InputDecoration(labelText: 'Requested change'),
                    items: const [
                      DropdownMenuItem(
                          value: 'correct', child: Text('Correct the total')),
                      DropdownMenuItem(
                          value: 'cancel', child: Text('Cancel this expense'))
                    ],
                    onChanged: _busy || _frozen
                        ? null
                        : (value) => setState(() => _kind = value!)),
                if (_kind == 'correct')
                  TextField(
                      controller: _amount,
                      enabled: !_busy && !_frozen,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'New total in PHP')),
                TextField(
                    controller: _reason,
                    enabled: !_busy && !_frozen,
                    maxLength: 500,
                    decoration: const InputDecoration(labelText: 'Reason')),
                if (widget.service.manualContact)
                  CheckboxListTile(
                      value: _contactAgreement,
                      onChanged: _busy || _frozen
                          ? null
                          : (value) =>
                              setState(() => _contactAgreement = value == true),
                      title: const Text(
                          'I agreed this change with the contact outside Tabby')),
                FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(_frozen
                        ? 'Retry saved change'
                        : widget.service.manualContact
                            ? 'Record agreed change'
                            : 'Request change')),
              ],
            ])));
  }
}
