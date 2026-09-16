import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/tabby_colors.dart';
import '../../../core/config/app_state.dart';
import '../../../core/config/supabase_config.dart';
import '../../../shared/widgets/tabby_button.dart';
import '../../tabs/application/tabby_providers.dart';
import '../../tabs/data/supabase_tabby_repository.dart';

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
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  String? _errorText;

  Future<void> _signup() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();

    if (name.isEmpty ||
        email.isEmpty ||
        phone.isEmpty ||
        password.isEmpty ||
        confirm.isEmpty) {
      setState(() => _errorText = 'Please fill in all fields');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _errorText = 'Please enter a valid email address');
      return;
    }
    if (phone.replaceAll(RegExp(r'\D'), '').length < 10) {
      setState(() => _errorText =
          'Please enter a valid phone number (at least 10 digits)');
      return;
    }
    if (password.length < 6) {
      setState(() => _errorText = 'Password must be at least 6 characters');
      return;
    }
    if (password != confirm) {
      setState(() => _errorText = 'Passwords do not match');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    if (!SupabaseTabbyRepository.instance.isConnected) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorText =
              'Authentication service is unavailable. Please try again when online.';
        });
      }
      return;
    }

    try {
      final res = await SupabaseTabbyRepository.instance.signUp(
        email: email,
        password: password,
        displayName: name,
        phone: phone,
      );
      final session = res?.session ?? SupabaseConfig.auth.currentSession;

      if (res?.user == null || session == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorText = res?.user != null
                ? 'Account created. Please confirm your email before logging in.'
                : 'Account creation failed. Please try again.';
          });
        }
        return;
      }

      // Successfully created and authenticated the account. Load its profile and tabs.
      await ref.read(currentUserProvider.notifier).loadFromSupabase();
      await ref.read(tabbyProvider.notifier).refreshTabs();

      if (mounted) {
        setState(() => _isLoading = false);
        AppState.isAuthenticated.value = true;
        context.go('/home');
      }
    } catch (e) {
      debugPrint('[SignUpScreen] Live Supabase auth error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          final err = e.toString().toLowerCase();
          if (err.contains('already registered') ||
              err.contains('user already exists')) {
            _errorText =
                'An account with this email already exists. Please log in.';
          } else if (err.contains('weak password') ||
              err.contains('at least 6 characters')) {
            _errorText = 'Password must be at least 6 characters.';
          } else {
            _errorText =
                'Sign up failed: ${e.toString().replaceAll('AuthApiException', '').replaceAll('AuthException', '').trim()}';
          }
        });
      }
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TabbyColors.bgCanvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: TabbyColors.brandDarkTeal),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Create your account',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: TabbyColors.brandDarkTeal,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Start keeping tabs with your friends',
                style: TextStyle(
                  fontSize: 16,
                  color: TabbyColors.textSecondary,
                ),
              ),
              const SizedBox(height: 32),
              _buildTextField(
                controller: _nameController,
                label: 'Full Name',
                icon: Icons.person_outline_rounded,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _emailController,
                label: 'Email',
                icon: Icons.email_outlined,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _phoneController,
                label: '+63 9XX XXX XXXX',
                icon: Icons.phone_outlined,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _passwordController,
                label: 'Password',
                icon: Icons.lock_outline_rounded,
                obscureText: _obscurePassword,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: TabbyColors.textSecondary,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _confirmPasswordController,
                label: 'Confirm Password',
                icon: Icons.lock_outline_rounded,
                obscureText: _obscureConfirmPassword,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: TabbyColors.textSecondary,
                  ),
                  onPressed: () => setState(
                      () => _obscureConfirmPassword = !_obscureConfirmPassword),
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorText!,
                  style: const TextStyle(
                      color: TabbyColors.alertRed, fontSize: 11),
                ),
              ],
              const SizedBox(height: 32),
              TabbyButton(
                label: 'Create Account',
                isLoading: _isLoading,
                onPressed: _isLoading ? null : _signup,
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Already have an account? ',
                      style: TextStyle(color: TabbyColors.textSecondary)),
                  GestureDetector(
                    onTap: () => context.go('/login'),
                    child: const Text(
                      'Log In',
                      style: TextStyle(
                          color: TabbyColors.brandEmerald,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: TabbyColors.brandMintAccent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        decoration: InputDecoration(
          hintText: label,
          hintStyle: const TextStyle(color: TabbyColors.textMuted),
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
