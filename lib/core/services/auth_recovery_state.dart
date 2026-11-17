import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores only opaque account/session IDs, never an auth link or token.
class AuthRecoveryState extends ChangeNotifier {
  AuthRecoveryState({this.storage = const FlutterSecureStorage()});
  static final instance = AuthRecoveryState();
  final FlutterSecureStorage storage;
  String? _account, _session;
  bool active = false;
  String? linkError;
  int _revision = 0;
  Future<void>? _writes;
  Future<void> _store(Future<void> Function() action) {
    final previous = _writes;
    late final Future<void> guard;
    Future<void> run() async {
      try {
        await Future<void>.value();
        if (previous != null) await previous;
        await action();
      } finally {
        if (identical(_writes, guard)) _writes = null;
      }
    }

    final result = run();
    guard = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _writes = guard;
    return result;
  }

  String? get account => _account;
  String? get sessionId => _session;
  String _key(String account, String session) =>
      'tabby_recovery_${account}_$session';
  static String? sessionIdFromToken(String token) {
    try {
      final payload = jsonDecode(utf8.decode(
          base64Url.decode(base64Url.normalize(token.split('.')[1])))) as Map;
      final id = payload['session_id'];
      return id is String && RegExp(r'^[0-9a-f-]{36}$').hasMatch(id)
          ? id
          : null;
    } catch (_) {
      return null;
    }
  }

  bool allows(String? account, String? session) =>
      active &&
      account != null &&
      session != null &&
      account == _account &&
      session == _session;
  Future<void> observe(
      {required String? account,
      required String? session,
      bool recovery = false,
      bool signedOut = false}) async {
    if (!signedOut && !recovery && allows(account, session)) return;
    final revision = ++_revision;
    final oldAccount = _account, oldSession = _session;
    if (account != oldAccount || session != oldSession) active = false;
    _account = account;
    _session = session;
    if (signedOut || account == null || session == null) {
      active = false;
      if (recovery) {
        linkError =
            'This recovery session could not be verified. Request a new link.';
      }
      notifyListeners();
      if (signedOut && oldAccount != null && oldSession != null) {
        try {
          await _store(() => storage.delete(key: _key(oldAccount, oldSession)));
        } catch (_) {}
      }
      return;
    }
    if (recovery) {
      active = true;
      linkError = null;
      notifyListeners();
      try {
        await _store(() =>
            storage.write(key: _key(account, session), value: 'required'));
      } catch (_) {
        if (revision == _revision) {
          linkError = 'Finish this password reset before closing Tabby.';
          notifyListeners();
        }
      }
      return;
    }
    try {
      final saved = await storage.read(key: _key(account, session));
      if (revision != _revision) return;
      active = saved == 'required';
      notifyListeners();
    } catch (_) {
      if (revision == _revision) {
        linkError =
            'Account recovery could not be restored. Please request a new link.';
        notifyListeners();
      }
    }
  }

  Future<void> complete(String account, String session) async {
    if (!allows(account, session)) throw StateError('Recovery session changed');
    final revision = ++_revision;
    try {
      await _store(() => storage.delete(key: _key(account, session)));
    } catch (_) {}
    if (revision != _revision) return;
    active = false;
    linkError = null;
    notifyListeners();
  }

  void reportInvalidLink() {
    linkError =
        'This sign-in link has expired, was already used, or could not be verified. Request a new link.';
    notifyListeners();
  }

  void clearLinkError() {
    linkError = null;
    notifyListeners();
  }
}
