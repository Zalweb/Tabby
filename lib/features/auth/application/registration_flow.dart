import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/config/app_state.dart';
import '../../../core/config/supabase_config.dart';
import '../../tabs/data/supabase_tabby_repository.dart';

/// Registration uses the authenticated account, never a name or device-wide
/// onboarding flag. Completed server profiles do not repeat the introduction.
class RegistrationFlow {
  static const _storage = FlutterSecureStorage();
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
      AppState.introductionRequired.value = false;
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
        final seen = incomplete ? await _storage.read(key: key(actor)) : 'true';
        if (!SupabaseConfig.isCurrentSession(stamp)) return;
        AppState.profileCompletionRequired.value = incomplete;
        AppState.introductionRequired.value = incomplete && seen != 'true';
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

  static Future<bool> finishIntroduction() async {
    final stamp = SupabaseConfig.captureSession();
    final actor = stamp.accountId;
    if (actor == null) return false;
    await _storage.write(key: key(actor), value: 'true');
    if (!SupabaseConfig.isCurrentSession(stamp)) return false;
    AppState.introductionRequired.value = false;
    return true;
  }

  static void reset() {
    _actor = null;
    _inflight = null;
    _inflightKey = null;
    AppState.registrationCheckPending.value = false;
    AppState.registrationError.value = null;
    AppState.introductionRequired.value = false;
    AppState.profileCompletionRequired.value = false;
  }
}
