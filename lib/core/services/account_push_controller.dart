import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Serializes remote registration and native scope changes. A binding is unique
/// to this account/session; queued messages from earlier bindings are ignored.
class AccountPushController {
  AccountPushController(
      {required this.nativeScope,
      required this.token,
      required this.register,
      required this.revoke,
      this.storage = const FlutterSecureStorage()});
  final Future<void> Function(String? account, String? binding) nativeScope;
  final Future<String?> Function() token;
  final Future<void> Function(String installation, String binding, String token)
      register;
  final Future<void> Function(String installation, String binding) revoke;
  final FlutterSecureStorage storage;
  String? _account, _binding;
  Object? _session;
  int _generation = 0;
  Future<void>? _work;
  String? get account => _account;
  String? get binding => _binding;
  Future<void> _enqueue(Future<void> Function() work) {
    final previous = _work;
    late final Future<void> guard;
    Future<void> run() async {
      try {
        await Future<void>.value();
        if (previous != null) await previous;
        await work();
      } finally {
        if (identical(_work, guard)) _work = null;
      }
    }

    final future = run();
    guard = future.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _work = guard;
    return future;
  }

  Future<void> bind(String? account, Object? session) {
    if (_account == account && _session == session) return Future.value();
    _account = account;
    _session = session;
    _binding = account == null ? null : const Uuid().v4();
    ++_generation;
    // Send native invalidation now, even while an old HTTP registration waits.
    Object? failure;
    StackTrace? trace;
    final clearing =
        nativeScope(null, null).onError((Object error, StackTrace stack) {
      failure = error;
      trace = stack;
    });
    return _enqueue(() async {
      await clearing;
      if (failure != null) Error.throwWithStackTrace(failure!, trace!);
    });
  }

  Future<bool> synchronize({required bool enabled}) async {
    final actor = _account, binding = _binding, generation = _generation;
    bool current() =>
        _account == actor && _binding == binding && _generation == generation;
    var ready = false;
    await _enqueue(() async {
      if (!current()) return;
      await nativeScope(null, null);
      if (!current()) return;
      final previous = await storage.read(key: 'tabby_push_registration_v1');
      final saved = previous == null ? null : jsonDecode(previous) as Map;
      if (!enabled || actor == null || binding == null) {
        if (saved != null && (actor == null || saved['account'] == actor)) {
          await revoke(
              saved['installation'] as String, saved['binding'] as String);
          if (current()) {
            await storage.delete(key: 'tabby_push_registration_v1');
          }
        }
        return;
      }
      final value = await token();
      if (!current() || value == null || value.isEmpty) return;
      var installation = await storage.read(key: 'tabby_push_installation_v1');
      installation ??= const Uuid().v4();
      await storage.write(
          key: 'tabby_push_installation_v1', value: installation);
      if (!current()) return;
      // Persist the revocation target before an ambiguous registration response.
      await storage.write(
          key: 'tabby_push_registration_v1',
          value: jsonEncode({
            'account': actor,
            'installation': installation,
            'binding': binding,
          }));
      if (!current()) return;
      await register(installation, binding, value);
      if (!current()) return;
      await nativeScope(actor, binding);
      ready = current();
    });
    return ready;
  }
}
