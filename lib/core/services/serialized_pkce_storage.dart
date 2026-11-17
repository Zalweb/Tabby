import 'package:supabase_flutter/supabase_flutter.dart';

/// Both the SDK and account mutations use this one verifier store. Queueing
/// writes prevents a slow obsolete writer from overwriting a newer flow.
class SerializedPkceStorage extends GotrueAsyncStorage {
  SerializedPkceStorage({required this.delegate, required this.captureCurrent});
  final GotrueAsyncStorage delegate;
  final bool Function() Function() captureCurrent;
  Future<void> _tail = Future<void>.value();
  Future<T> _run<T>(Future<T> Function() work) {
    final result = _tail.then((_) => work());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace stack) {});
    return result;
  }

  @override
  Future<String?> getItem({required String key}) =>
      _run(() => delegate.getItem(key: key));
  @override
  Future<void> setItem({required String key, required String value}) {
    final current = captureCurrent();
    return _run(() async {
      if (!current()) {
        throw const AuthException('Your account changed. Request a new link.');
      }
      await delegate.setItem(key: key, value: value);
    });
  }

  @override
  Future<void> removeItem({required String key}) =>
      _run(() => delegate.removeItem(key: key));
}
