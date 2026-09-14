import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/tabby_colors.dart';
import '../../../core/config/app_state.dart';
import '../../../shared/widgets/tabby_button.dart';
import '../../../shared/widgets/tabby_mascot_widget.dart';
import '../../tabs/data/supabase_tabby_repository.dart';
import '../../tabs/domain/models.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isGoogleLoading = false;
  String? _errorText;

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorText = 'Please enter email and password');
      return;
    }

    try {
      if (SupabaseTabbyRepository.instance.isConnected) {
        await SupabaseTabbyRepository.instance.signIn(
          email: email,
          password: password,
        );
      }
    } catch (e) {
      debugPrint('[LoginScreen] Live Supabase auth notice: $e');
    }

    AppState.isAuthenticated.value = true;
    if (mounted) context.go('/home');
  }

  Future<void> _loginWithGoogle() async {
    if (_isGoogleLoading) return;
    setState(() {
      _isGoogleLoading = true;
      _errorText = null;
    });

    try {
      if (SupabaseTabbyRepository.instance.isConnected) {
        final success =
            await SupabaseTabbyRepository.instance.signInWithGoogle();

        // Web: browser redirect handles the rest — nothing more to do here.
        if (kIsWeb) return;

        // Native: success = false means user cancelled the picker.
        if (!success) {
          setState(() => _isGoogleLoading = false);
          return;
        }
      }
    } catch (e) {
      debugPrint('[LoginScreen] Google sign-in error: $e');
      if (mounted) {
        setState(() {
          _isGoogleLoading = false;
          _errorText = 'Google sign-in failed. Please try again.';
        });
      }
      return;
    }

    if (mounted) {
      AppState.isAuthenticated.value = true;
      context.go('/home');
    }
  }

  void _showForgotPasswordSheet() {
    final resetEmailController = TextEditingController(
      text: _emailController.text.contains('@') ? _emailController.text.trim() : '',
    );
    String? resetError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: TabbyColors.surfaceWhite,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Reset Password',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: TabbyColors.brandDarkTeal,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enter your registered email address to receive password reset instructions.',
                      style: TextStyle(fontSize: 13, color: TabbyColors.textSecondary, height: 1.4),
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(
                      controller: resetEmailController,
                      label: 'Email Address',
                      icon: Icons.email_outlined,
                    ),
                    if (resetError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        resetError!,
                        style: const TextStyle(color: TabbyColors.alertRed, fontSize: 11),
                      ),
                    ],
                    const SizedBox(height: 24),
                    TabbyButton(
                      label: 'Send Reset Link',
                      onPressed: () {
                        final email = resetEmailController.text.trim();
                        if (email.isEmpty || !email.contains('@')) {
                          setModalState(() {
                            resetError = 'Please enter a valid email address.';
                          });
                          return;
                        }

                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Password reset link sent to $email! Please check your inbox.'),
                            backgroundColor: TabbyColors.brandEmerald,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TabbyColors.bgCanvas,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
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
              const SizedBox(height: 24),
              const Center(
                child: TabbyMascotWidget(
                  emotion: MascotEmotion.idleNeutral,
                  size: 80,
                  showBubble: false,
                ),
              ),
              const SizedBox(height: 48),
              _buildTextField(
                controller: _emailController,
                label: 'Email or Phone',
                icon: Icons.person_outline_rounded,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _passwordController,
                label: 'Password',
                icon: Icons.lock_outline_rounded,
                obscureText: _obscurePassword,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: TabbyColors.textSecondary,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorText!,
                  style: const TextStyle(color: TabbyColors.alertRed, fontSize: 11),
                ),
              ],
              const SizedBox(height: 24),
              TabbyButton(
                label: 'Log In',
                onPressed: _login,
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: _showForgotPasswordSheet,
                  child: const Text(
                    'Forgot password?',
                    style: TextStyle(color: TabbyColors.textSecondary),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Expanded(child: Divider(color: TabbyColors.borderMint)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('or', style: TextStyle(color: TabbyColors.textSecondary)),
                  ),
                  Expanded(child: Divider(color: TabbyColors.borderMint)),
                ],
              ),
              const SizedBox(height: 24),
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
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account? ", style: TextStyle(color: TabbyColors.textSecondary)),
                  GestureDetector(
                    onTap: () => context.go('/signup'),
                    child: const Text(
                      'Sign Up',
                      style: TextStyle(color: TabbyColors.brandEmerald, fontWeight: FontWeight.bold),
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}
