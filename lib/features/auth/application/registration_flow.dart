import '../../../core/config/app_state.dart';
import '../../../core/config/supabase_config.dart';
import '../../tabs/data/supabase_tabby_repository.dart';

/// Registration uses the authenticated account and the live session, never a
/// name or device-wide onboarding flag. The first-launch tour is install-level
/// and precedes sign-in. Completed server profiles go Home; incomplete
/// profiles go straight to required setup without a post-auth introduction.
class RegistrationFlow {
  /// Legacy per-account introduction marker from the former post-Google
  /// introduction. Retained as a historical local record for older installs;
  /// it no longer gates routing and is never rewritten or deleted here.
  static String key(String account) => 'tabby_${account}_introduction_v1';
  static String? _actor;
  static String? _inflightKey;
  static Future<void>? _inflight;

  static Future<void> refresh({Future<bool?> Function(String)? profileCheck}) {
    final stamp = SupabaseConfig.captureSession();
    final actor = stamp.accountId;
    if (actor == null) {
      reset();
      return Future.value();
    }
    final requestKey = '$actor:${stamp.generation}';
    if (_inflightKey == requestKey && _inflight != null) return _inflight!;
    if (_actor != requestKey) {
      _actor = requestKey;
      AppState.registrationCheckPending.value = true;
    }
    AppState.registrationError.value = null;
    Future<void> run() async {
      try {
        final incomplete =
            await (profileCheck ??
                SupabaseTabbyRepository.instance.requiresProfileCompletion)(
              actor,
            );
        if (!SupabaseConfig.isCurrentSession(stamp)) return;
        if (incomplete == null) throw StateError('Profile lookup unavailable');
        AppState.profileCompletionRequired.value = incomplete;
        AppState.registrationCheckPending.value = false;
      } catch (_) {
        if (SupabaseConfig.isCurrentSession(stamp)) {
          AppState.registrationCheckPending.value = true;
          AppState.registrationError.value =
              'Your account setup could not be checked. Please try again.';
        }
        rethrow;
      }
    }

    _inflightKey = requestKey;
    late final Future<void> pending;
    pending = run().whenComplete(() {
      if (identical(_inflight, pending)) {
        _inflight = null;
        _inflightKey = null;
      }
    });
    _inflight = pending;
    return pending;
  }

  static void reset() {
    _actor = null;
    _inflight = null;
    _inflightKey = null;
    AppState.registrationCheckPending.value = false;
    AppState.registrationError.value = null;
    AppState.profileCompletionRequired.value = false;
  }
}
