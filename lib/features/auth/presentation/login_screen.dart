import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isGoogleLoading = false;
  bool _isEmailLoading = false;
  bool _obscurePassword = true;
  String? _errorText;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loginWithEmailPassword() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (!_isValidEmail(email)) {
      setState(() => _errorText = 'Please enter a valid email address.');
      return;
    }
    if (password.isEmpty) {
      setState(() => _errorText = 'Please enter your password.');
      return;
    }
    if (_isEmailLoading || _isGoogleLoading) return;

    if (!SupabaseTabbyRepository.instance.isConnected) {
      setState(() {
        _errorText =
            'Authentication service is unavailable. Please try again when online.';
      });
      return;
    }

    setState(() {
      _isEmailLoading = true;
      _errorText = null;
    });

    try {
      final response = await SupabaseTabbyRepository.instance
          .signInWithEmailPassword(email: email, password: password);
      if (response?.session == null) {
        throw StateError('No authenticated session was returned.');
      }
      await _finishAuthenticatedLogin();
    } catch (error) {
      debugPrint('[LoginScreen] Email sign-in error: $error');
      if (mounted) {
        setState(() {
          _isEmailLoading = false;
          _errorText = _friendlyCredentialError(error);
        });
      }
    }
  }

  Future<void> _loginWithGoogle() async {
    if (_isGoogleLoading || _isEmailLoading) return;
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

      await _finishAuthenticatedLogin();
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

  Future<void> _finishAuthenticatedLogin() async {
    AppState.hasSeenOnboarding.value = true;
    try {
      const FlutterSecureStorage().write(
        key: 'tabby_has_seen_onboarding',
        value: 'true',
      );
    } catch (_) {}
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
    setState(() {
      _isGoogleLoading = false;
      _isEmailLoading = false;
    });
    AppState.isAuthenticated.value = true;
    context.go(
      AppState.profileCompletionRequired.value ? '/complete-profile' : '/home',
    );
  }

  String _friendlyCredentialError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('invalid login credentials') ||
        message.contains('invalid credentials')) {
      return 'The email or password is incorrect.';
    }
    if (message.contains('email not confirmed')) {
      return 'Please confirm your email address before signing in.';
    }
    return 'We could not sign you in. Please check your details and try again.';
  }

  static bool _isValidEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
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
                'Sign in to Tabby',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: TabbyColors.brandDarkTeal,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Continue with Google or use your Tabby email and password.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: TabbyColors.textSecondary,
                ),
              ),
              const SizedBox(height: 22),
              _buildField(
                controller: _emailController,
                label: 'Email',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _passwordController,
                label: 'Password',
                icon: Icons.lock_outline_rounded,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _loginWithEmailPassword(),
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 14),
                Text(
                  _errorText!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: TabbyColors.alertRed,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              TabbyButton(
                label: 'Sign in',
                isLoading: _isEmailLoading,
                onPressed: _isEmailLoading || _isGoogleLoading
                    ? null
                    : _loginWithEmailPassword,
              ),
              const SizedBox(height: 22),
              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'or',
                      style: TextStyle(color: TabbyColors.textSecondary),
                    ),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 22),
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
                      onPressed: _isEmailLoading ? null : _loginWithGoogle,
                    ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => context.go('/signup'),
                child: const Text('Create an account'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    bool obscureText = false,
    Widget? suffixIcon,
    ValueChanged<String>? onSubmitted,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: TabbyColors.brandMintAccent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        obscureText: obscureText,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: TabbyColors.textSecondary),
          prefixIcon: Icon(icon, color: TabbyColors.textSecondary),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}
