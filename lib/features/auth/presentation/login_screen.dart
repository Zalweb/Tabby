import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/app_state.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/theme/tabby_colors.dart';
import '../../../shared/widgets/tabby_button.dart';
import '../../../shared/widgets/tabby_mascot_widget.dart';
import '../../tabs/application/tabby_providers.dart';
import '../../tabs/data/supabase_tabby_repository.dart';
import '../../tabs/domain/models.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _isGoogleLoading = false;
  String? _errorText;

  Future<void> _loginWithGoogle() async {
    if (_isGoogleLoading) return;
    setState(() {
      _isGoogleLoading = true;
      _errorText = null;
    });

    if (!SupabaseTabbyRepository.instance.isConnected) {
      if (mounted) {
        setState(() {
          _isGoogleLoading = false;
          _errorText =
              'Authentication service is unavailable. Please try again when online.';
        });
      }
      return;
    }

    try {
      final success = await SupabaseTabbyRepository.instance.signInWithGoogle();

      // The browser redirect returns to the app and is finalized by the
      // auth-state listener in main.dart.
      if (kIsWeb) {
        if (mounted) setState(() => _isGoogleLoading = false);
        return;
      }

      if (!success) {
        if (mounted) setState(() => _isGoogleLoading = false);
        return;
      }

      if (SupabaseConfig.auth.currentSession == null) {
        if (mounted) {
          setState(() {
            _isGoogleLoading = false;
            _errorText =
                'Google sign-in is still in progress. Please try again after it finishes.';
          });
        }
        return;
      }

      await ref.read(currentUserProvider.notifier).loadFromSupabase();
      await ref.read(tabbyProvider.notifier).refreshTabs();

      final userId = SupabaseConfig.currentUserId;
      final requiresProfile = userId == null
          ? true
          : await SupabaseTabbyRepository.instance
              .requiresProfileCompletion(userId);
      if (requiresProfile != null) {
        AppState.profileCompletionRequired.value = requiresProfile;
      }

      if (!mounted) return;
      setState(() => _isGoogleLoading = false);
      AppState.isAuthenticated.value = true;
      context.go(AppState.profileCompletionRequired.value
          ? '/complete-profile'
          : '/home');
    } catch (e) {
      debugPrint('[LoginScreen] Google sign-in error: $e');
      if (mounted) {
        setState(() {
          _isGoogleLoading = false;
          _errorText = 'Google sign-in failed. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TabbyColors.bgCanvas,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Center(
                child: Column(
                  children: [
                    Text(
                      'Tabby',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: TabbyColors.brandDarkTeal,
                        letterSpacing: -0.5,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Keep tabs. Settle up.',
                      style: TextStyle(
                        fontSize: 14,
                        color: TabbyColors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const Center(
                child: TabbyMascotWidget(
                  emotion: MascotEmotion.idleNeutral,
                  size: 84,
                  showBubble: false,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Sign in securely with Google',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: TabbyColors.brandDarkTeal,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Use your Google account to create or access your Tabby account. Your Google password is entered only on Google’s secure sign-in screen.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: TabbyColors.textSecondary,
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 18),
                Text(
                  _errorText!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: TabbyColors.alertRed,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 28),
              _isGoogleLoading
                  ? const SizedBox(
                      height: 52,
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              TabbyColors.brandEmerald,
                            ),
                          ),
                        ),
                      ),
                    )
                  : TabbyButton(
                      label: 'Continue with Google',
                      variant: TabbyButtonVariant.outline,
                      icon: const Icon(
                        Icons.g_mobiledata_rounded,
                        color: TabbyColors.brandEmerald,
                      ),
                      onPressed: _loginWithGoogle,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
