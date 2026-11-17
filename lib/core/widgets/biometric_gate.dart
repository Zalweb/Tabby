import '../theme/tabby_palette.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/tabs/application/tabby_providers.dart';
import '../config/supabase_config.dart';
import '../services/device_auth_service.dart';
import '../services/pin_protection_service.dart';

/// Sensitive descendants are not mounted until security settings are loaded
/// and the configured cold/resume lock has been satisfied.
class BiometricGate extends ConsumerStatefulWidget {
  const BiometricGate({super.key, required this.child, this.auth});
  final Widget child;
  final DeviceAuthService? auth;
  @override
  ConsumerState<BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends ConsumerState<BiometricGate>
    with WidgetsBindingObserver {
  late final DeviceAuthService _auth;
  String? _scope;
  bool _locked = true;
  bool _authenticating = false;
  @override
  void initState() {
    super.initState();
    _auth = widget.auth ?? LocalDeviceAuthService();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final settings = ref.read(userSettingsProvider);
    if (!settings.isLoaded ||
        settings.securityMethod == SecurityMethod.none ||
        !settings.autoLockEnabled) {
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (mounted) setState(() => _locked = true);
    } else if (state == AppLifecycleState.resumed &&
        _locked &&
        settings.biometricsEnabled) {
      _unlockBiometric();
    }
  }

  Future<void> _unlockBiometric() async {
    if (_authenticating || !mounted) return;
    _authenticating = true;
    final session = SupabaseConfig.captureSession();
    try {
      final success = await _auth.authenticate(
        reason: 'Unlock Tabby',
        allowDeviceCredential: false,
      );
      if (mounted && success && SupabaseConfig.isCurrentSession(session)) {
        setState(() => _locked = false);
      }
    } catch (_) {
      // Cancellation/failure always leaves the gate locked.
    } finally {
      _authenticating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(userSettingsProvider);
    final notifier = ref.read(userSettingsProvider.notifier);
    final scope =
        '${notifier.scopeId}:${SupabaseConfig.captureSession().generation}';
    if (!settings.isLoaded) {
      return Material(
        color: TabbyPalette.of(context).canvas,
        child: SafeArea(
          child: Center(
            child: settings.loadError == null
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        settings.loadError!,
                        style: TextStyle(color: TabbyPalette.of(context).text),
                      ),
                      TextButton(
                        onPressed: notifier.reloadSecuritySettings,
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
          ),
        ),
      );
    }
    if (_scope != scope) {
      _scope = scope;
      _locked = settings.securityMethod != SecurityMethod.none;
    }
    if (!_locked || settings.securityMethod == SecurityMethod.none) {
      return widget.child;
    }
    return Navigator(
      key: ValueKey('lock-$scope'),
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        builder: (_) => _InlineLockScreen(
          key: ValueKey(scope),
          biometrics: settings.biometricsEnabled,
          pin: settings.passcodeEnabled,
          onBiometric: _unlockBiometric,
          resetPin: () async {
            final session = SupabaseConfig.captureSession();
            final reset = await notifier.clearPin();
            if (!mounted || !SupabaseConfig.isCurrentSession(session)) {
              return false;
            }
            if (reset) setState(() => _locked = false);
            return reset;
          },
          verifyPin: (pin) async {
            final session = SupabaseConfig.captureSession();
            final valid = await notifier.verifyPin(pin);
            final currentSession = SupabaseConfig.isCurrentSession(session);
            if (!mounted || !currentSession) {
              return false;
            }
            if (valid) setState(() => _locked = false);
            return valid;
          },
        ),
      ),
    );
  }
}

class _InlineLockScreen extends StatefulWidget {
  const _InlineLockScreen({
    super.key,
    required this.biometrics,
    required this.pin,
    required this.onBiometric,
    required this.resetPin,
    required this.verifyPin,
  });
  final bool biometrics;
  final bool pin;
  final VoidCallback onBiometric;
  final Future<bool> Function() resetPin;
  final Future<bool> Function(String) verifyPin;
  @override
  State<_InlineLockScreen> createState() => _InlineLockScreenState();
}

class _InlineLockScreenState extends State<_InlineLockScreen> {
  final _pin = TextEditingController();
  bool _busy = false;
  bool _verifyingPin = false;
  String? _error;
  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: TabbyPalette.of(context).canvas,
    child: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                color: TabbyPalette.of(context).text,
                size: 44,
              ),
              Text(
                'Tabby is locked',
                style: TextStyle(
                  color: TabbyPalette.of(context).text,
                  fontSize: 22,
                ),
              ),
              if (widget.biometrics)
                ElevatedButton(
                  onPressed: widget.onBiometric,
                  child: const Text('Unlock Tabby'),
                ),
              if (widget.pin) ...[
                TextField(
                  controller: _pin,
                  obscureText: true,
                  maxLength: 6,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: TabbyPalette.of(context).text),
                  decoration: InputDecoration(
                    labelText: 'PIN',
                    errorText: _error,
                  ),
                ),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() {
                            _busy = true;
                            _verifyingPin = true;
                            _error = null;
                          });
                          try {
                            final valid = await widget.verifyPin(_pin.text);
                            if (mounted && !valid) {
                              setState(
                                () => _error =
                                    'That PIN did not match. Try again.',
                              );
                            }
                          } on PinLockedException catch (error) {
                            if (mounted) {
                              setState(
                                () => _error =
                                    'Too many attempts. Try again in ${error.retryAfter.inSeconds + 1} seconds.',
                              );
                            }
                          } catch (_) {
                            if (mounted) {
                              setState(
                                () => _error = 'PIN unlock is unavailable. Please try again.',
                              );
                            }
                          } finally {
                            if (mounted) {
                              setState(() {
                                _busy = false;
                                _verifyingPin = false;
                              });
                            }
                          }
                        },
                  child: const Text('Unlock with PIN'),
                ),
                if (_verifyingPin)
                  Semantics(
                    liveRegion: true,
                    label: 'Verifying PIN',
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: TabbyPalette.of(context).text,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Verifying PIN',
                            style: TextStyle(
                              color: TabbyPalette.of(context).text,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() {
                            _busy = true;
                            _error = null;
                          });
                          final reset = await widget.resetPin();
                          if (mounted) {
                            setState(() {
                              _busy = false;
                              if (!reset) {
                                _error = 'Device authentication is required to reset your PIN.';
                              }
                            });
                          }
                        },
                  child: const Text('Forgot PIN? Authenticate on this device'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _pin.clear();
                          _error = null;
                        }),
                  child: const Text('Cancel'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
