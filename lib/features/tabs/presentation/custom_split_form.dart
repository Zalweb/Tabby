import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/form_draft_store.dart';
import '../../../core/widgets/account_draft_guard.dart';
import '../../../core/utils/currency_formatter.dart';
import '../data/m2_command_queue.dart';
import '../domain/custom_split.dart';
import '../domain/models.dart';

/// Hidden production entry until CAP-002 acceptance. Tests may mount the form
/// directly without opening the application's rollout gate.
class CustomSplitForm extends StatefulWidget {
  const CustomSplitForm({
    super.key,
    required this.tabId,
    required this.parties,
    required this.queue,
    this.drafts = const FormDraftStore(),
  });
  final String tabId;
  final Map<PartyRef, String> parties;
  final M2CommandQueue queue;
  final FormDraftStore drafts;
  @override
  State<CustomSplitForm> createState() => _CustomSplitFormState();
}

class _CustomSplitFormState extends State<CustomSplitForm> {
  final _description = TextEditingController(),
      _tax = TextEditingController(text: '0'),
      _service = TextEditingController(text: '0');
  late final _amounts = {
    for (final p in widget.parties.keys) p: TextEditingController(text: '0.00'),
  };
  late PartyRef _payer = widget.parties.keys.first;
  String _operation = const Uuid().v4();
  Map<String, dynamic>? _frozen;
  bool _loading = true,
      _busy = false,
      _recorded = false,
      _restoreFailed = false;
  String? _error, _message;
  String get _purpose => 'custom-split:${widget.tabId}';
  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final saved = await widget.drafts.read(widget.queue.actor, _purpose);
      if (!mounted || !widget.queue.current()) return;
      if (saved != null) {
        _operation = saved['operation_id'] as String;
        _description.text = saved['description'] as String;
        _tax.text = saved['tax'] as String;
        _service.text = saved['service'] as String;
        for (final p in _amounts.keys) {
          _amounts[p]!.text =
              (saved['amounts'] as Map)[CustomSplit.key(p)] as String? ??
              '0.00';
        }
        _payer = widget.parties.keys.singleWhere(
          (p) => CustomSplit.key(p) == saved['payer'],
        );
        _frozen = saved['command'] == null
            ? null
            : Map<String, dynamic>.from(saved['command'] as Map);
        if (_operation.isEmpty ||
            (_frozen != null &&
                (_frozen!['p_tab_id'] != widget.tabId ||
                    _frozen!['p_expected_actor'] != widget.queue.actor))) {
          throw const FormatException('Saved split scope mismatch');
        }
      }
    } catch (_) {
      _restoreFailed = true;
      if (mounted) {
        _error = 'The saved draft could not be restored. Close and retry.';
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() => widget.drafts.write(widget.queue.actor, _purpose, {
    'operation_id': _operation,
    'description': _description.text,
    'tax': _tax.text,
    'service': _service.text,
    'amounts': {
      for (final p in _amounts.keys) CustomSplit.key(p): _amounts[p]!.text,
    },
    'payer': CustomSplit.key(_payer),
    'command': _frozen,
  });
  void _changed() {
    setState(() => _error = null);
    unawaited(
      _save().catchError((Object _) {
        if (mounted) {
          setState(
            () => _error = 'The draft could not be saved. Please retry.',
          );
        }
      }),
    );
  }

  int _rate(String value) {
    if (!RegExp(r'^\d{1,3}(\.\d{1,2})?$').hasMatch(value.trim())) {
      throw const FormatException('Enter a percentage from 0 to 100.');
    }
    final rate = CurrencyFormatter.parseToCentavos(value);
    if (rate > 10000) {
      throw const FormatException('Enter a percentage from 0 to 100.');
    }
    return rate;
  }

  CustomSplit _split() => CustomSplit(
    baseShares: {
      for (final p in _amounts.keys)
        p: CurrencyFormatter.parseToCentavos(_amounts[p]!.text),
    },
    taxBasisPoints: _rate(_tax.text),
    serviceBasisPoints: _rate(_service.text),
  );
  Future<void> _submit() async {
    if (_busy || _restoreFailed || !widget.queue.current()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _frozen ??= _split().toCommand(
        actor: widget.queue.actor,
        tabId: widget.tabId,
        payer: _payer,
        description: _description.text,
      );
      await _save();
      await widget.queue.enqueue(_operation, 'create_expense_v3', _frozen!);
      final result = await widget.queue.result(_operation);
      final attention = await widget.queue.needsAttention(_operation);
      if (!mounted || !widget.queue.current()) return;
      _recorded = result != null;
      if (_recorded) await widget.drafts.remove(widget.queue.actor, _purpose);
      if (mounted) {
        setState(
          () => _message = _recorded
              ? 'Expense recorded.'
              : attention
              ? 'The saved request needs attention. Check server availability before retrying.'
              : 'Saved on this device. Sync pending.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : 'Not confirmed. Retry the saved request.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _description.dispose();
    _tax.dispose();
    _service.dispose();
    for (final c in _amounts.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.queue.current()) {
      return const SizedBox.shrink();
    }
    if (widget.parties.isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text('Refresh the tab participants before entering a split.'),
        ),
      );
    }
    CustomSplit? preview;
    try {
      preview = _split();
    } catch (_) {}
    return AccountDraftGuard(
      child: Scaffold(
        appBar: AppBar(title: const Text('Custom split')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _restoreFailed
            ? Center(child: Text(_error!))
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    'Tax and service are calculated independently on the base shares. Review every total before saving.',
                  ),
                  TextField(
                    controller: _description,
                    enabled: _frozen == null,
                    onChanged: (_) => _changed(),
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  for (final p in widget.parties.keys)
                    TextField(
                      controller: _amounts[p],
                      enabled: _frozen == null,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => _changed(),
                      decoration: InputDecoration(
                        labelText: '${widget.parties[p]} base share (PHP)',
                      ),
                    ),
                  DropdownButtonFormField<PartyRef>(
                    initialValue: _payer,
                    items: [
                      for (final p in widget.parties.keys)
                        DropdownMenuItem(
                          value: p,
                          child: Text(widget.parties[p]!),
                        ),
                    ],
                    decoration: const InputDecoration(labelText: 'Who paid?'),
                    onChanged: _frozen != null
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _payer = value);
                              _changed();
                            }
                          },
                  ),
                  for (final field in [
                    (_tax, 'Tax (%)'),
                    (_service, 'Service (%)'),
                  ])
                    TextField(
                      controller: field.$1,
                      enabled: _frozen == null,
                      onChanged: (_) => _changed(),
                      decoration: InputDecoration(labelText: field.$2),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  if (preview != null) ...[
                    Text(
                      'Base: ${CurrencyFormatter.formatCentavos(preview.base)}',
                    ),
                    Text(
                      'Tax: ${CurrencyFormatter.formatCentavos(preview.tax)}',
                    ),
                    Text(
                      'Service: ${CurrencyFormatter.formatCentavos(preview.service)}',
                    ),
                    Text(
                      'Total: ${CurrencyFormatter.formatCentavos(preview.total)}',
                    ),
                    for (final p in widget.parties.keys)
                      Text(
                        '${widget.parties[p]} total: ${CurrencyFormatter.formatCentavos(preview.shares[p]!)}',
                      ),
                  ],
                  if (_error != null) Text(_error!),
                  if (_message != null) Text(_message!),
                  FilledButton(
                    onPressed: _busy || _recorded ? null : _submit,
                    child: Text(
                      _frozen == null ? 'Save expense' : 'Retry saved request',
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
