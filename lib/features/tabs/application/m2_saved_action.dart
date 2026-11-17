import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/services/form_draft_store.dart';
import '../data/m2_command_queue.dart';

class M2ActionResult {
  const M2ActionResult(this.id, this.needsAttention);
  final String? id;
  final bool needsAttention;
  bool get confirmed => id != null;
  String get message => confirmed
      ? 'Saved by the server.'
      : needsAttention
      ? 'The saved request needs attention. Check server availability before retrying.'
      : 'Saved on this device. Sync pending.';
}

/// All M2 control forms use frozen, owner-scoped retry requests and the shared
/// queue. A retry cannot turn an uncertain old decision into a new intent.
class M2SavedAction {
  M2SavedAction({
    required this.queue,
    required this.purpose,
    this.scope = const {},
    this.drafts = const FormDraftStore(),
  });
  final M2CommandQueue queue;
  final String purpose;
  final Map<String, Object?> scope;
  final FormDraftStore drafts;
  Map<String, dynamic>? pending;
  bool _busy = false;
  M2ActionResult? _completed;
  String? _completedIntent;
  void _current() {
    if (!queue.current() || queue.actor.isEmpty) {
      throw StateError('Account changed.');
    }
  }

  Future<Map<String, dynamic>?> restore() async {
    _current();
    final saved = await drafts.read(queue.actor, purpose);
    _current();
    if (saved != null) {
      final command = saved['command'];
      if (saved['operation_id'] is! String ||
          saved['rpc'] is! String ||
          !M2CommandQueue.rpcs.contains(saved['rpc']) ||
          command is! Map ||
          command['p_expected_actor'] != queue.actor ||
          !scope.entries.every((e) => command[e.key] == e.value)) {
        throw const FormatException('Saved request scope mismatch.');
      }
    }
    pending = saved;
    return saved;
  }

  Future<M2ActionResult> send(String rpc, Map<String, dynamic> command) async {
    _current();
    if (_busy) {
      throw StateError('Request already running.');
    }
    _busy = true;
    try {
      if ((command['p_expected_actor'] != null &&
              command['p_expected_actor'] != queue.actor) ||
          !scope.entries.every((e) => command[e.key] == e.value)) {
        throw StateError('Request scope changed.');
      }
      final intent = _canonical({
        'rpc': rpc,
        'command': {...command, 'p_expected_actor': queue.actor},
      });
      if (_completed != null) {
        if (_completedIntent != intent) {
          throw StateError('This request already completed.');
        }
        return _completed!;
      }
      await restore();
      final frozen = {...command, 'p_expected_actor': queue.actor};
      if (pending == null) {
        pending = {
          'operation_id': const Uuid().v4(),
          'rpc': rpc,
          'command': frozen,
        };
        await drafts.write(queue.actor, purpose, pending!);
        _current();
      } else if (pending!['rpc'] != rpc ||
          _canonical(pending!['command']) != _canonical(frozen)) {
        throw StateError('Retry the saved request before changing it.');
      }
      final operation = pending!['operation_id'] as String;
      await queue.enqueue(
        operation,
        rpc,
        Map<String, dynamic>.from(pending!['command'] as Map),
      );
      final id = await queue.result(operation),
          attention = await queue.needsAttention(operation);
      _current();
      if (id != null) {
        await drafts.removeIf(queue.actor, purpose, 'operation_id', operation);
        _current();
      }
      final result = M2ActionResult(id, attention);
      if (id != null) {
        _completed = result;
        _completedIntent = intent;
      }
      return result;
    } finally {
      _busy = false;
    }
  }

  Future<M2ActionResult> retry() {
    final saved = pending;
    if (saved == null) {
      throw StateError('No saved request.');
    }
    return send(
      saved['rpc'] as String,
      Map<String, dynamic>.from(saved['command'] as Map),
    );
  }

  static String _canonical(Object? value) {
    Object? sort(Object? item) {
      if (item is Map) {
        final keys = item.keys.cast<String>().toList()..sort();
        return {for (final k in keys) k: sort(item[k])};
      }
      if (item is List) {
        return item.map(sort).toList();
      }
      return item;
    }

    return jsonEncode(sort(value));
  }
}
