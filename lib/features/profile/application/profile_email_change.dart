import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/services/auth_email_assistance.dart';
import '../../../core/services/auth_user_mutation.dart';

/// Requests verification without writing a proposed email to the profile.
class ProfileEmailChange {
  ProfileEmailChange(
      {required this.account,
      required this.captureCurrent,
      required this.request,
      this.storage = const FlutterSecureStorage(),
      DateTime Function()? now})
      : now = now ?? DateTime.now;

  static final instance = ProfileEmailChange(
      account: () => SupabaseConfig.currentUserId,
      captureCurrent: () {
        final stamp = SupabaseConfig.captureSession();
        return () => SupabaseConfig.isCurrentSession(stamp);
      },
      request: (email) async {
        await AuthUserMutation.instance
            .updateEmail(email, redirectTo: authEmailRedirect);
      });

  final String? Function() account;
  final bool Function() Function() captureCurrent;
  final Future<void> Function(String) request;
  final FlutterSecureStorage storage;
  final DateTime Function() now;
  bool _busy = false;

  Future<void> send(String email) async {
    email = email.trim();
    final actor = account(), current = captureCurrent();
    if (actor == null || !AuthEmailAssistance.validEmail(email)) {
      throw const AuthAssistanceException(
          'Sign in and enter a valid email address.');
    }
    if (_busy) {
      throw const AuthAssistanceException(
          'An email request is already in progress.');
    }
    _busy = true;
    try {
      final key = 'tabby_${actor}_email_change_after_v1';
      final raw = await storage.read(key: key);
      final until = raw == null ? null : DateTime.tryParse(raw);
      if (raw != null && until == null) {
        throw const FormatException('Invalid email cooldown');
      }
      if (until != null && until.isAfter(now())) {
        throw const AuthAssistanceException(
            'Please wait a minute before requesting another email change.');
      }
      if (!current() || account() != actor) {
        throw const AuthAssistanceException(
            'Your account changed. Reopen your profile.');
      }
      await storage.write(
          key: key,
          value:
              now().add(const Duration(minutes: 1)).toUtc().toIso8601String());
      if (!current() || account() != actor) {
        throw const AuthAssistanceException(
            'Your account changed. Reopen your profile.');
      }
      await request(email);
      if (!current() || account() != actor) {
        throw const AuthAssistanceException(
            'Your account changed. Reopen your profile.');
      }
    } finally {
      _busy = false;
    }
  }
}
