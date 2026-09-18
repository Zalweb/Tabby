import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/tabs/application/tabby_providers.dart';
import '../services/device_auth_service.dart';
import '../theme/tabby_colors.dart';

/// Locks the app after it is backgrounded when the user has configured
/// biometric or PIN security. Cancellation leaves the app locked.
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
  bool _isLocked = false;
  bool _isAuthenticating = false;

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
    final shouldLock = settings.securityMethod != SecurityMethod.none &&
        settings.autoLockEnabled;
    if (!shouldLock) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (mounted) setState(() => _isLocked = true);
    } else if (state == AppLifecycleState.resumed && _isLocked) {
      _promptAuthentication();
    }
  }

  Future<void> _promptAuthentication() async {
    if (_isAuthenticating || !mounted) return;
    _isAuthenticating = true;
    final settings = ref.read(userSettingsProvider);

    try {
      final success = settings.biometricsEnabled
          ? await _auth.authenticate(
              reason: 'Use biometrics to unlock Tabby',
              allowDeviceCredential: settings.passcodeEnabled,
            )
          : await _showPinUnlockDialog();
      if (mounted && success) setState(() => _isLocked = false);
    } catch (error) {
      debugPrint('[BiometricGate] Authentication error: $error');
    } finally {
      _isAuthenticating = false;
    }
  }

  Future<bool> _showPinUnlockDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enter your Tabby PIN'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(labelText: 'PIN'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final valid = await ref
                  .read(userSettingsProvider.notifier)
                  .verifyPin(controller.text);
              if (dialogContext.mounted) Navigator.pop(dialogContext, valid);
            },
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_isLocked) _LockScreen(onUnlock: _promptAuthentication),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: TabbyColors.brandDarkTeal,
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_outline_rounded,
                    size: 44, color: Colors.white),
              ),
              const SizedBox(height: 24),
              const Text('Tabby is locked',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
              const SizedBox(height: 8),
              const Text('Authenticate to access your tabs',
                  style: TextStyle(fontSize: 14, color: Colors.white70)),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                onPressed: onUnlock,
                icon: const Icon(Icons.lock_open_rounded, size: 18),
                label: const Text('Unlock Tabby'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: TabbyColors.brandDarkTeal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
