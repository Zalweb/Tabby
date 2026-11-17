import '../../../shared/widgets/tabby_mascot_widget.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, AuthState, Session;

import '../../../core/config/app_state.dart';
import '../../../core/config/supabase_config.dart';

import '../../../shared/widgets/tabby_button.dart';
import 'auth_welcome_widgets.dart';
import '../application/registration_flow.dart';
import '../../tabs/application/tabby_providers.dart';
import '../../tabs/data/supabase_tabby_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.googleAuthEvents});

  @visibleForTesting
  final Stream<AuthState>? googleAuthEvents;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _isGoogleLoading = false;

  String? _errorText;
  String? _infoText;
  StreamSubscription<AuthState>? _googleAuthWatch;
  int _googleAttempt = 0;
  bool _googleCallbackFailed = false;

  void _stopGoogleAuthWatch() {
    _googleAttempt++;
    final subscription = _googleAuthWatch;
    _googleAuthWatch = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  void _watchGoogleAuthCallback() {
    _stopGoogleAuthWatch();
    final attempt = _googleAttempt;
    final origin = SupabaseConfig.captureSession();
    _googleCallbackFailed = false;
    _googleAuthWatch =
        (widget.googleAuthEvents ?? SupabaseConfig.auth.onAuthStateChange)
            .listen(
              (event) {
                if (!mounted || attempt != _googleAttempt) return;
                if (event.event == AuthChangeEvent.signedIn &&
                    event.session != null &&
                    identical(
                      event.session,
                      SupabaseConfig.auth.currentSession,
                    )) {
                  setState(() {
                    _infoText = null;
                    _errorText = null;
                  });
                  _stopGoogleAuthWatch();
                }
              },
              onError: (Object error, StackTrace stack) {
                if (!mounted || attempt != _googleAttempt) return;
                if (!SupabaseConfig.isCurrentSession(origin)) {
                  _stopGoogleAuthWatch();
                  return;
                }
                _googleCallbackFailed = true;
                setState(() {
                  _isGoogleLoading = false;
                  _infoText = null;
                  _errorText = 'Google sign-in failed. Please try again.';
                });
                _stopGoogleAuthWatch();
              },
            );
  }

  @override
  void dispose() {
    _stopGoogleAuthWatch();

    super.dispose();
  }

  Future<void> _loginWithGoogle() async {
    if (_isGoogleLoading) return;
    setState(() {
      _isGoogleLoading = true;
      _errorText = null;
      _infoText = null;
    });

    if (!SupabaseTabbyRepository.instance.isConnected) {
      if (mounted) {
        setState(() {
          _isGoogleLoading = false;
          _errorText = 'Authentication service is unavailable. Please try again when online.';
        });
      }
      return;
    }

    if (!kIsWeb) _watchGoogleAuthCallback();
    try {
      final result = await SupabaseTabbyRepository.instance.signInWithGoogle();

      // The browser redirect returns to the app and is finalized by the
      // auth-state listener in main.dart.
      if (kIsWeb) {
        if (mounted) setState(() => _isGoogleLoading = false);
        return;
      }

      if (result.flow == GoogleSignInFlow.cancelled) {
        _stopGoogleAuthWatch();
        if (mounted) setState(() => _isGoogleLoading = false);
        return;
      }

      if (result.flow == GoogleSignInFlow.browserOpened) {
        if (mounted) {
          setState(() {
            _isGoogleLoading = false;
            if (!_googleCallbackFailed) {
              _errorText = null;
              _infoText =
                  'Finish signing in in your browser, then return to Tabby.';
            }
          });
        }
        return;
      }

      _stopGoogleAuthWatch();
      await _finishAuthenticatedLogin(expectedSession: result.session!);
    } catch (e) {
      _stopGoogleAuthWatch();
      debugPrint('[LoginScreen] Google sign-in error: $e');
      if (mounted) {
        setState(() {
          _isGoogleLoading = false;
          _errorText = 'Google sign-in failed. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  Future<void> _finishAuthenticatedLogin({
    required Session expectedSession,
  }) async {
    final session = await SupabaseConfig.captureAcknowledgedSession(
      expectedSession,
    );
    if (session == null) return;
    bool current() =>
        mounted &&
        session.accountId == expectedSession.user.id &&
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

    await RegistrationFlow.refresh();
    if (!current()) return;
    setState(() {
      _isGoogleLoading = false;
    });
    AppState.isAuthenticated.value = true;
    if (!mounted) return;
    context.go(
      AppState.introductionRequired.value
          ? '/onboarding'
          : AppState.profileCompletionRequired.value
          ? '/complete-profile'
          : '/home',
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: WelcomeColors.canvas(context),
    body: WelcomeBackdrop(
      vibrant: true,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final artSize = constraints.maxWidth >= 800
                ? 350.0
                : (constraints.maxHeight < 650 ? 220.0 : 290.0);
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 64).clamp(
                    0.0,
                    double.infinity,
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        WelcomeMascot(
                          size: artSize,
                          pose: _errorText != null
                              ? TabbyMascotPose.helpful
                              : _isGoogleLoading || _infoText != null
                              ? TabbyMascotPose.waiting
                              : TabbyMascotPose.welcome,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Tabby',
                          style: TextStyle(
                            fontSize: 64,
                            height: 1,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -2.5,
                            color: WelcomeColors.ink(context),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Keep tabs. Settle up.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontStyle: FontStyle.italic,
                            color: WelcomeColors.ink(context),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Shared expenses.\nBetter friendships.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            height: 1.45,
                            color: WelcomeColors.muted(context),
                          ),
                        ),
                        const SizedBox(height: 36),
                        TabbyButton(
                          label: 'Continue with Google',
                          height: 60,
                          variant: TabbyButtonVariant.neutral,
                          isLoading: _isGoogleLoading,
                          icon: Image.asset(
                            'assets/branding/google-g.png',
                            width: 24,
                            height: 24,
                          ),
                          onPressed: _isGoogleLoading ? null : _loginWithGoogle,
                        ),
                        if (_errorText != null || _infoText != null) ...[
                          const SizedBox(height: 18),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              _errorText ?? _infoText!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: WelcomeColors.ink(context),
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Text(
                          'One Google account. Your tabs, together.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: WelcomeColors.muted(context),
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}
