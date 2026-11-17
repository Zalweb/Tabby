import '../../../core/theme/motion_preferences.dart';
import '../../../core/utils/philippine_phone.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_state.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/services/tabby_api_services.dart';
import '../../../core/theme/tabby_palette.dart';
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

  // Advisory check (soft warning, does not block form submission)
  String? _emailWarning;
  bool _allowLeave = false, _confirmingLeave = false;
  bool get _dirty =>
      _successText == null &&
      [
        _nameController,
        _emailController,
        _phoneController,
        _passwordController,
        _confirmPasswordController,
      ].any((controller) => controller.text.isNotEmpty);
  @override
  void initState() {
    super.initState();
    for (final controller in [
      _nameController,
      _emailController,
      _phoneController,
      _passwordController,
      _confirmPasswordController,
    ]) {
      controller.addListener(_edited);
    }
  }

  void _edited() {
    if (mounted) {
      setState(() {
        _allowLeave = false;
        _successText = null;
      });
    }
  }

  Future<void> _leave({bool signIn = false}) async {
    if (_isSubmitting || _confirmingLeave) return;
    var leave = true;
    if (_dirty) {
      _confirmingLeave = true;
      try {
        leave =
            await showDialog<bool>(
              animationStyle: TabbyMotion.style(context),
              context: context,
              builder: (dialog) => AlertDialog(
                scrollable: true,
                title: const Text('Leave account setup?'),
                content: const Text('Your unsaved details will be discarded.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: const Text('Keep editing'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: const Text('Discard draft'),
                  ),
                ],
              ),
            ) ??
            false;
      } finally {
        _confirmingLeave = false;
      }
    }
    if (!mounted || !leave) return;
    setState(() => _allowLeave = true);
    if (signIn) {
      context.go('/login');
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (!await Navigator.of(context).maybePop()) await SystemNavigator.pop();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  /// Fires on email field blur. Shows a grey advisory for disposable or
  /// badly-formatted addresses without ever preventing the user from continuing.
  void _checkEmail() {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    final allowed = TabbyApiServices.isEmailAcceptable(email);
    setState(() {
      _emailWarning = allowed
          ? null
          : 'This looks like a temporary email address. '
                'Use a real email so you can recover your account.';
    });
  }

  Future<void> _createAccount() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final phoneInput = _phoneController.text.trim();
    final phone = normalizePhilippineMobile(phoneInput) ?? phoneInput;
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
        _errorText = 'Authentication service is unavailable. Please try again when online.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorText = null;
      _successText = null;
    });

    try {
      final response = await SupabaseTabbyRepository.instance
          .signUpWithEmailPassword(
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

      final session = await SupabaseConfig.captureAcknowledgedSession(
        response!.session!,
      );
      if (session == null) return;
      bool current() =>
          mounted &&
          session.accountId == response.user!.id &&
          SupabaseConfig.isCurrentSession(session);
      if (!current()) return;
      AppState.hasSeenOnboarding.value = true;
      try {
        await const FlutterSecureStorage().write(
          key: 'tabby_has_seen_onboarding',
          value: 'true',
        );
      } catch (_) {}
      if (!current()) return;
      await ref.read(currentUserProvider.notifier).loadFromSupabase();
      if (!current()) return;
      await ref.read(tabbyProvider.notifier).refreshTabs();
      if (!current()) return;
      final requiresProfile = await SupabaseTabbyRepository.instance
          .requiresProfileCompletion(session.accountId!);
      if (!current()) return;
      if (!mounted) return;
      AppState.profileCompletionRequired.value = requiresProfile ?? false;
      AppState.isAuthenticated.value = true;

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
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
    if (normalizePhilippineMobile(phone) == null) {
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
    return PopScope<Object?>(
      canPop: !_isSubmitting && (!_dirty || _allowLeave),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: TabbyPalette.of(context).canvas,
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
                Text(
                  'Create your Tabby account',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: TabbyPalette.of(context).text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Use these details when you sign in without Google.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: TabbyPalette.of(context).secondaryText,
                  ),
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => context.go('/auth-help?kind=confirmation'),
                  child: const Text('Need a new confirmation email?'),
                ),
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
                  onEditingComplete: _checkEmail,
                ),
                if (_emailWarning != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 14,
                        color: TabbyPalette.of(context).secondaryText,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _emailWarning!,
                          style: TextStyle(
                            fontSize: 11,
                            color: TabbyPalette.of(context).secondaryText,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
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
                    style: TextStyle(
                      color: TabbyPalette.of(context).errorText,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (_successText != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _successText!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: TabbyPalette.of(context).link,
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
                  onPressed: _isSubmitting ? null : () => _leave(signIn: true),
                  child: const Text('Already have an account? Sign in'),
                ),
              ],
            ),
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
    VoidCallback? onEditingComplete,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: TabbyPalette.of(context).soft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        enabled: !_isSubmitting,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        obscureText: obscureText,
        onSubmitted: onSubmitted,
        onEditingComplete: onEditingComplete,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: TabbyPalette.of(context).secondaryText),
          prefixIcon: Icon(icon, color: TabbyPalette.of(context).secondaryText),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
    );
  }
}
