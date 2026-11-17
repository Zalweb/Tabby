import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import 'auth_email_assistance.dart';
import 'auth_recovery_state.dart';
import 'auth_user_mutation.dart';

class RecoveryPasswordUpdate {
  RecoveryPasswordUpdate(
      {required this.recovery,
      required this.account,
      required this.sessionId,
      required this.captureCurrent,
      required this.update});
  static final instance = RecoveryPasswordUpdate(
      recovery: AuthRecoveryState.instance,
      account: () => SupabaseConfig.currentUserId,
      sessionId: () => SupabaseConfig.isInitialized
          ? AuthRecoveryState.sessionIdFromToken(
              SupabaseConfig.auth.currentSession?.accessToken ?? '')
          : null,
      captureCurrent: () {
        final stamp = SupabaseConfig.captureSession();
        return () => SupabaseConfig.isCurrentSession(stamp);
      },
      update: (password) async {
        await AuthUserMutation.instance.updatePassword(password);
      });
  final AuthRecoveryState recovery;
  final String? Function() account, sessionId;
  final bool Function() Function() captureCurrent;
  final Future<void> Function(String) update;
  Future<void> save(String password, String confirmation) async {
    if (password.length < 8 ||
        password.length > 128 ||
        password != confirmation) {
      throw const AuthAssistanceException(
          'Use 8 to 128 characters and enter the same password twice.');
    }
    final actor = account(), session = sessionId(), current = captureCurrent();
    if (!recovery.allows(actor, session) || actor == null || session == null) {
      throw const AuthAssistanceException(
          'This recovery session is unavailable. Request a new link.');
    }
    try {
      await update(password);
    } on AuthWeakPasswordException {
      throw const AuthAssistanceException(
          'Choose a stronger password and try again.');
    } on AuthException catch (error) {
      if (error.code == 'same_password') {
        throw const AuthAssistanceException(
            'Choose a password different from your current one.');
      }
      rethrow;
    }
    if (!current() || !recovery.allows(actor, session)) {
      throw const AuthAssistanceException(
          'Your account changed. Please request a new recovery link.');
    }
    await recovery.complete(actor, session);
  }
}
