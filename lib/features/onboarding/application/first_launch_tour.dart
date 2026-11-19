import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/app_state.dart';

/// Install-level acknowledgment for the signed-out first-launch tour.
///
/// The seen marker lives in a non-sensitive sandbox preference so a true
/// reinstall (which clears the sandbox) does not inherit the iOS Keychain.
/// Acknowledgment needs no account and no network; write failures stay
/// recoverable on the tour itself.
class FirstLaunchTour {
  FirstLaunchTour._();

  static const storageKey = 'tabby_has_seen_onboarding';
  static const _legacyStorage = FlutterSecureStorage();
  static const _ioTimeout = Duration(seconds: 3);
  static bool get _canUseLegacyStorage =>
      kIsWeb || defaultTargetPlatform != TargetPlatform.iOS;
  static Future<void>? _inflight;

  /// Restores the seen marker during the startup optional-preferences phase.
  ///
  /// Reads the sandbox preference first. When it is absent on non-iOS
  /// platforms, accepts a legacy secure `true` marker once and migrates it to
  /// the preference. iOS never inherits the Keychain for a signed-out launch,
  /// so a fresh reinstall or legacy upgrade may see the skippable tour once;
  /// returning authenticated sessions are handled independently by startup.
  static Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance().timeout(_ioTimeout);
    final seen = prefs.getBool(storageKey);
    if (seen == true) {
      AppState.hasSeenOnboarding.value = true;
      return;
    }
    if (seen != null) return; // Explicitly false: keep the tour available.
    if (!_canUseLegacyStorage) return;
    try {
      final legacy = await _legacyStorage
          .read(key: storageKey)
          .timeout(_ioTimeout);
      if (legacy == 'true') {
        AppState.hasSeenOnboarding.value = true;
        // Best-effort migration; the in-memory flag already covers this launch.
        await prefs.setBool(storageKey, true).timeout(_ioTimeout);
      }
    } catch (_) {
      // Legacy storage is optional; never block startup on it.
    }
  }

  /// Persists the seen marker, then updates app state so the router can yield
  /// to the Google-only welcome. Throws only when both the sandbox preference
  /// and legacy storage cannot be written, so the caller can offer Retry and a
  /// continue-for-now escape. Concurrent callers share the actual in-flight
  /// write; the state flag only changes after a write succeeds.
  static Future<void> acknowledge() {
    final existing = _inflight;
    if (existing != null) return existing;
    if (AppState.hasSeenOnboarding.value) return Future<void>.value();
    return _startWrite();
  }

  /// Best-effort marker for an already-authenticated session (startup restore
  /// and auth-state events). Never throws and shares the in-flight write with
  /// [acknowledge] so a session event racing tour completion cannot overlap
  /// saves or report a false success while the first save is pending.
  static Future<void> persistSeenBestEffort() {
    final existing = _inflight;
    if (existing != null) return existing.catchError((Object _) {});
    return _startWrite().catchError((Object _) {});
  }

  static Future<void> _startWrite() {
    late final Future<void> pending;
    pending = _persist().whenComplete(() {
      if (identical(_inflight, pending)) _inflight = null;
    });
    _inflight = pending;
    return pending;
  }

  static Future<void> _persist() async {
    late final Object preferenceError;
    try {
      final prefs = await SharedPreferences.getInstance().timeout(_ioTimeout);
      if (prefs.getBool(storageKey) == true ||
          await prefs.setBool(storageKey, true).timeout(_ioTimeout)) {
        AppState.hasSeenOnboarding.value = true;
        return;
      }
      preferenceError = StateError('Onboarding marker was not persisted.');
    } catch (error) {
      preferenceError = error;
    }
    // The secure store can back up an install only where restore can read it.
    // On iOS a Keychain value may outlive the install and is never restored.
    if (!_canUseLegacyStorage) throw preferenceError;
    try {
      await _legacyStorage
          .write(key: storageKey, value: 'true')
          .timeout(_ioTimeout);
      AppState.hasSeenOnboarding.value = true;
    } catch (_) {
      throw preferenceError;
    }
  }
}
