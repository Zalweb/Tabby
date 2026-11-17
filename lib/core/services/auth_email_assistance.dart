import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

enum AuthEmailKind { recovery, confirmation }

String get authEmailRedirect =>
    kIsWeb ? '${Uri.base.origin}/' : 'io.supabase.tabby://login-callback';

class AuthEmailAssistance {
  AuthEmailAssistance(
      {required this.request,
      this.storage = const FlutterSecureStorage(),
      DateTime Function()? now})
      : now = now ?? DateTime.now;
  static final instance = AuthEmailAssistance(request: (kind, email) async {
    if (!SupabaseConfig.isInitialized) {
      throw StateError('Authentication unavailable');
    }
    if (kind == AuthEmailKind.recovery) {
      await SupabaseConfig.auth
          .resetPasswordForEmail(email, redirectTo: authEmailRedirect);
    } else {
      await SupabaseConfig.auth.resend(
          type: OtpType.signup,
          email: email,
          emailRedirectTo: authEmailRedirect);
    }
  });
  final Future<void> Function(AuthEmailKind, String) request;
  final FlutterSecureStorage storage;
  final DateTime Function() now;
  bool _busy = false;
  static bool validEmail(String value) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value) &&
      value.length <= 254;
  Future<int> remainingSeconds() async {
    final raw = await storage.read(key: 'tabby_auth_email_next_request_v1');
    if (raw == null) return 0;
    final until = DateTime.tryParse(raw);
    if (until == null) {
      throw const FormatException('Invalid email request cooldown');
    }
    final milliseconds = until.difference(now()).inMilliseconds;
    return milliseconds <= 0 ? 0 : (milliseconds / 1000).ceil();
  }

  Future<void> send(AuthEmailKind kind, String input) async {
    final email = input.trim();
    if (!validEmail(email)) {
      throw const AuthAssistanceException('Enter a valid email address.');
    }
    if (_busy) {
      throw const AuthAssistanceException(
          'An email request is already in progress.');
    }
    _busy = true;
    try {
      final remaining = await remainingSeconds();
      if (remaining > 0) {
        throw AuthAssistanceException(
            'Please wait $remaining seconds before requesting another email.');
      }
      // Reserve the interval before the request: concurrent taps, response loss
      // and restarts cannot bypass the local limit. Server limits still apply.
      await storage.write(
          key: 'tabby_auth_email_next_request_v1',
          value:
              now().add(const Duration(seconds: 60)).toUtc().toIso8601String());
      await request(kind, email);
    } on AuthException catch (error) {
      if (['over_email_send_rate_limit', 'over_request_rate_limit']
              .contains(error.code) ||
          error.statusCode == '429') {
        throw const AuthAssistanceException(
            'Too many email requests. Please wait before trying again.');
      }
      throw const AuthAssistanceException(
          'The email request could not be accepted. Please try again later.');
    } finally {
      _busy = false;
    }
  }
}

class AuthAssistanceException implements Exception {
  const AuthAssistanceException(this.message);
  final String message;
}
