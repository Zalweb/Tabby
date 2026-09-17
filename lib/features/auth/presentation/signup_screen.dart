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

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  String? _errorText;
  String? _successText;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _createAccount() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;
    final confirmation = _confirmPasswordController.text;

    final validationError = _validate(
      name: name,
      email: email,
      phone: phone,
      password: password,
      confirmation: confirmation,
    );
    if (validationError != null) {
      setState(() => _errorText = validationError);
      return;
    }
    if (_isSubmitting) return;

    if (!SupabaseTabbyRepository.instance.isConnected) {
      setState(() {
        _errorText =
            'Authentication service is unavailable. Please try again when online.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorText = null;
      _successText = null;
    });

    try {
      final response =
          await SupabaseTabbyRepository.instance.signUpWithEmailPassword(
        email: email,
        password: password,
        displayName: name,
        phone: phone,
      );
      if (response?.user == null) {
        throw StateError('No account was returned.');
      }

      if (response?.session == null) {
        if (!mounted) return;
        setState(() {
          _isSubmitting = false;
          _successText =
              'Account created. Check your email to confirm it, then sign in.';
        });
        return;
      }

      await ref.read(currentUserProvider.notifier).loadFromSupabase();
      await ref.read(tabbyProvider.notifier).refreshTabs();
      final userId = SupabaseConfig.currentUserId;
      final requiresProfile = userId == null
          ? true
          : await SupabaseTabbyRepository.instance
              .requiresProfileCompletion(userId);
      AppState.profileCompletionRequired.value = requiresProfile ?? false;
      AppState.isAuthenticated.value = true;

      if (!mounted) return;
      setState(() => _isSubmitting = false);
      context.go(
        AppState.profileCompletionRequired.value
            ? '/complete-profile'
            : '/home',
      );
    } catch (error) {
      debugPrint('[SignUpScreen] Email signup error: $error');
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorText = _friendlySignupError(error);
        });
      }
    }
  }

  String? _validate({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String confirmation,
  }) {
    if (name.isEmpty) return 'Please enter your full name.';
    if (!_isValidEmail(email)) return 'Please enter a valid email address.';
    if (phone.replaceAll(RegExp(r'\D'), '').length < 10) {
      return 'Please enter a valid mobile number.';
    }
    if (password.length < 8) {
      return 'Password must be at least 8 characters.';
    }
    if (password != confirmation) return 'Passwords do not match.';
    return null;
  }

  String _friendlySignupError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('already registered') ||
        message.contains('already exists')) {
      return 'An account with this email already exists. Try signing in.';
    }
    if (message.contains('password')) {
      return 'Please choose a stronger password and try again.';
    }
    return 'We could not create your account. Please try again.';
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
              const SizedBox(height: 20),
              const Center(
                child: TabbyMascotWidget(
                  emotion: MascotEmotion.idleNeutral,
                  size: 78,
                  showBubble: false,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Create your Tabby account',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: TabbyColors.brandDarkTeal,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Use these details when you sign in without Google.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: TabbyColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              _buildField(
                controller: _nameController,
                label: 'Full name',
                icon: Icons.person_outline_rounded,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _emailController,
                label: 'Email',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _phoneController,
                label: 'Mobile number',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _passwordController,
                label: 'Password',
                icon: Icons.lock_outline_rounded,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.next,
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
              const SizedBox(height: 12),
              _buildField(
                controller: _confirmPasswordController,
                label: 'Confirm password',
                icon: Icons.lock_reset_outlined,
                obscureText: _obscureConfirmation,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _createAccount(),
                suffixIcon: IconButton(
                  onPressed: () => setState(
                    () => _obscureConfirmation = !_obscureConfirmation,
                  ),
                  icon: Icon(
                    _obscureConfirmation
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
              if (_successText != null) ...[
                const SizedBox(height: 14),
                Text(
                  _successText!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: TabbyColors.brandEmerald,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              TabbyButton(
                label: 'Create account',
                isLoading: _isSubmitting,
                onPressed: _isSubmitting ? null : _createAccount,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _isSubmitting ? null : () => context.go('/login'),
                child: const Text('Already have an account? Sign in'),
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
