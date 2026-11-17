import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/account_draft_guard.dart';
import '../application/m2_saved_action.dart';
import '../data/m2_command_queue.dart';
import '../data/m2_queries.dart';
import '../domain/custom_split.dart';
import '../domain/models.dart';
import '../domain/recurrence.dart';

class RecurrenceEditor extends StatefulWidget {
  const RecurrenceEditor({
    super.key,
    required this.tabId,
    required this.template,
    required this.queue,
    this.rule,
  });
  final String tabId;
  final Map<String, dynamic> template;
  final Map<String, dynamic>? rule;
  final M2CommandQueue queue;
  @override
  State<RecurrenceEditor> createState() => _RecurrenceEditorState();
}

class _RecurrenceEditorState extends State<RecurrenceEditor> {
  late String _ruleId = widget.rule?['id'] as String? ?? const Uuid().v4();
  late final _action = M2SavedAction(
    queue: widget.queue,
    purpose: widget.rule == null
        ? 'recurrence:${widget.tabId}:create'
        : 'recurrence:$_ruleId:${widget.rule!['revision']}',
    scope: widget.rule == null
        ? {'p_tab_id': widget.tabId}
        : {'rule_id': _ruleId},
  );
  final _description = TextEditingController(),
      _base = TextEditingController(),
      _anchor = TextEditingController(),
      _step = TextEditingController(text: '1'),
      _end = TextEditingController();
  String _unit = 'monthly', _zone = 'Asia/Manila';
  late Map<String, dynamic> _template = widget.template;
  bool _loading = true,
      _busy = false,
      _failed = false,
      _confirmed = false,
      _mayLeave = false;
  String? _error, _message;
  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final saved = await _action.restore();
      if (!mounted || !widget.queue.current()) return;
      final data = saved?['command'] as Map? ?? widget.rule;
      if (saved != null) _ruleId = data!['rule_id'] as String;
      _template = Map<String, dynamic>.from(
        data?['template'] as Map? ?? widget.template,
      );
      _description.text = _template['p_description'] as String;
      final cents = _template['split']['base_centavos'] as int;
      _base.text =
          '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
      _anchor.text =
          data?['anchor'] as String? ??
          RecurrenceSchedule.label(DateTime.now());
      _zone = data?['timezone'] as String? ?? 'Asia/Manila';
      _unit = data?['unit'] as String? ?? 'monthly';
      _step.text = '${data?['step'] ?? 1}';
      _end.text = data?['end_date'] as String? ?? '';
    } catch (_) {
      _failed = true;
      _error = 'The saved rule could not be restored. Close and retry.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _command() {
    final anchor = RecurrenceSchedule.date(_anchor.text);
    final ending = _end.text.isEmpty
        ? null
        : RecurrenceSchedule.date(_end.text);
    if (ending != null && ending.isBefore(anchor)) {
      throw const FormatException('End date must follow the first date.');
    }
    final step = int.tryParse(_step.text) ?? 0;
    RecurrenceSchedule(
      anchor: anchor,
      timeZone: _zone,
      unit: RecurrenceUnit.values.byName(_unit),
      step: step,
    );
    final raw = _template['split'] as Map;
    final original = CustomSplit(
      baseShares: {
        for (final item in raw['base_shares'] as List)
          PartyRef.fromMap(Map<String, dynamic>.from(item['party'] as Map)):
              item['amount'] as int,
      },
      taxBasisPoints: raw['tax_basis_points'] as int,
      serviceBasisPoints: raw['service_basis_points'] as int,
    );
    final split = CustomSplit(
      baseShares: original.rescaleBase(
        CurrencyFormatter.parseToCentavos(_base.text),
      ),
      taxBasisPoints: original.taxBasisPoints,
      serviceBasisPoints: original.serviceBasisPoints,
    );
    final payer = split.baseShares.keys.singleWhere(
      (p) => p.id == _template['p_paid_by_user_id'],
    );
    final template = split.toCommand(
      actor: widget.queue.actor,
      tabId: widget.tabId,
      payer: payer,
      description: _description.text,
      category: _template['p_category'] as String? ?? 'other',
    );
    return {
      'action': widget.rule == null ? 'create' : 'edit',
      'rule_id': _ruleId,
      'expected_revision': widget.rule?['revision'] ?? 0,
      'p_tab_id': widget.tabId,
      'anchor': _anchor.text,
      'timezone': _zone,
      'unit': _unit,
      'step': step,
      'end_date': _end.text.isEmpty ? null : _end.text,
      'template': template,
    };
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final result = _action.pending == null
          ? await _action.send('change_recurrence_v1', _command())
          : await _action.retry();
      if (mounted && widget.queue.current()) {
        setState(() {
          _confirmed = result.confirmed;
          _mayLeave = true;
          _message = result.message;
        });
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

  Future<void> _leave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Leave without saving?'),
        content: const Text('Your unsaved rule changes will be discarded.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      setState(() => _mayLeave = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_description, _base, _anchor, _step, _end]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.queue.current()) {
      return const SizedBox.shrink();
    }
    Map<String, dynamic>? preview;
    try {
      preview = _command()['template'] as Map<String, dynamic>;
    } catch (_) {}
    final locked = _action.pending != null;
    return AccountDraftGuard(
      child: PopScope(
        canPop: _mayLeave || locked,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            _leave();
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              widget.rule == null ? 'Repeat expense' : 'Edit repeating expense',
            ),
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _failed
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const Text(
                      'Creates recorded expenses, never payments. Stored tax/service rates are retained; legacy recorded totals repeat as the base. Allocations scale proportionally. Older missed dates are not added after activation or resume.',
                    ),
                    for (final field in [
                      (_description, 'Description'),
                      (_base, 'Base amount (PHP)'),
                      (_anchor, 'First date (YYYY-MM-DD)'),
                      (_step, 'Every'),
                      (_end, 'Last date (optional YYYY-MM-DD)'),
                    ])
                      TextField(
                        controller: field.$1,
                        enabled:
                            !locked &&
                            !(widget.rule != null && field.$1 == _anchor),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(labelText: field.$2),
                      ),
                    DropdownButtonFormField<String>(
                      initialValue: _unit,
                      items: [
                        for (final unit in RecurrenceUnit.values)
                          DropdownMenuItem(
                            value: unit.name,
                            child: Text(unit.name),
                          ),
                      ],
                      onChanged: locked
                          ? null
                          : (v) {
                              if (v != null) setState(() => _unit = v);
                            },
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _zone,
                      items: [
                        for (final zone in {
                          'Asia/Manila',
                          'UTC',
                          'America/New_York',
                          _zone,
                        })
                          DropdownMenuItem(value: zone, child: Text(zone)),
                      ],
                      onChanged: locked || widget.rule != null
                          ? null
                          : (v) {
                              if (v != null) setState(() => _zone = v);
                            },
                    ),
                    const Text(
                      'Monthly dates keep the original day, clamped only for shorter months. Pausing or ending never deletes generated expenses.',
                    ),
                    if (preview != null) ...[
                      Text(
                        'Each occurrence: ${CurrencyFormatter.formatCentavos(preview['p_total_amount_centavos'] as int)}',
                      ),
                      for (final p in preview['p_participants'] as List)
                        Text(
                          '${p['user_id'] == widget.queue.actor ? 'You' : 'Member'}: ${CurrencyFormatter.formatCentavos(p['share_amount_centavos'] as int)}',
                        ),
                    ],
                    if (_error != null) Text(_error!),
                    if (_message != null) Text(_message!),
                    FilledButton(
                      onPressed: _busy || _confirmed ? null : _save,
                      child: Text(
                        locked
                            ? 'Retry saved request'
                            : 'Save repeating expense',
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class RecurrenceManager extends StatefulWidget {
  const RecurrenceManager({
    super.key,
    required this.tabId,
    required this.template,
    required this.queue,
    this.queries,
    this.templateTransactionId,
  });
  final String tabId;
  final Map<String, dynamic> template;
  final M2CommandQueue queue;
  final M2Queries? queries;
  final String? templateTransactionId;
  @override
  State<RecurrenceManager> createState() => _RecurrenceManagerState();
}

class _RecurrenceManagerState extends State<RecurrenceManager> {
  late final _queries = widget.queries ?? M2Queries.production();
  final _rows = <Map<String, dynamic>>[];
  String? _cursor, _message;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool next = false}) async {
    if (!widget.queue.current() || _queries.actor != widget.queue.actor) return;
    setState(() => _loading = true);
    try {
      final result = await _queries.read(
        'list_recurrences_v1',
        {'p_tab_id': widget.tabId, 'p_after': next ? _cursor : null},
        scope: {'tab_id': widget.tabId},
      );
      if (mounted) {
        setState(() {
          if (!next) _rows.clear();
          _rows.addAll(
            (result['records'] as List).map(
              (v) => Map<String, dynamic>.from(v as Map),
            ),
          );
          _cursor = result['next_cursor'] as String?;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Rules unavailable. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _control(Map<String, dynamic> rule, String action) async {
    final saved = M2SavedAction(
      queue: widget.queue,
      purpose: 'rule:${rule['id']}:$action:${rule['revision']}',
      scope: {'rule_id': rule['id']},
    );
    try {
      final result = await saved.send('change_recurrence_v1', {
        'rule_id': rule['id'],
        'action': action,
        'expected_revision': rule['revision'],
      });
      if (mounted) setState(() => _message = result.message);
      if (result.confirmed) await _load();
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Not confirmed. Retry the same action.');
      }
    }
  }

  Future<void> _edit(Map<String, dynamic>? rule) async {
    var template = Map<String, dynamic>.from(
      rule?['template'] as Map? ?? widget.template,
    );
    if (rule == null && widget.templateTransactionId != null) {
      try {
        final result = await _queries.read(
          'get_expense_split_v1',
          {'p_transaction_id': widget.templateTransactionId},
          scope: {'transaction_id': widget.templateTransactionId},
        );
        if (result['breakdown'] != null) {
          template = {...template, 'split': result['breakdown']};
        }
      } catch (_) {
        if (mounted) {
          setState(
            () => _message =
                'The recorded allocation could not be refreshed. Try again.',
          );
        }
        return;
      }
    }
    if (!mounted || !widget.queue.current()) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecurrenceEditor(
          tabId: widget.tabId,
          template: template,
          queue: widget.queue,
          rule: rule,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => !widget.queue.current()
      ? const SizedBox.shrink()
      : AccountDraftGuard(
          child: Scaffold(
            appBar: AppBar(title: const Text('Repeating expenses')),
            body: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                FilledButton(
                  onPressed: () => _edit(null),
                  child: const Text('Create repeating expense'),
                ),
                TextButton(
                  onPressed: _loading ? null : () => _load(),
                  child: const Text('Refresh rules'),
                ),
                if (_message != null) Text(_message!),
                for (final rule in _rows)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${rule['template']['p_description'] ?? 'Repeating expense'}',
                          ),
                          Text(
                            '${rule['status']} · next ${rule['next_date']} · ${rule['timezone']}',
                          ),
                          if (rule['status'] != 'ended')
                            Wrap(
                              children: [
                                TextButton(
                                  onPressed: () => _edit(rule),
                                  child: const Text('Edit rule'),
                                ),
                                TextButton(
                                  onPressed: () => _control(
                                    rule,
                                    rule['status'] == 'active'
                                        ? 'pause'
                                        : 'resume',
                                  ),
                                  child: Text(
                                    rule['status'] == 'active'
                                        ? 'Pause'
                                        : 'Resume',
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => _control(rule, 'end'),
                                  child: const Text('End rule'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                if (_cursor != null)
                  TextButton(
                    onPressed: _loading ? null : () => _load(next: true),
                    child: const Text('More rules'),
                  ),
              ],
            ),
          ),
        );
}
