import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/supabase_config.dart';
import '../../auth/application/registration_flow.dart';
import '../../auth/presentation/auth_welcome_widgets.dart';

/// Post-Google introduction for an unfinished Tabby registration.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  bool _saving = false;
  String? _error;
  static const _slides = [
    (
      title: "Hi, I'm Tabby.",
      body: 'A little companion for the expenses you share. Let’s make keeping tabs feel simple.',
      art: 'assets/branding/tabby-welcome-v3.png',
    ),
    (
      title: 'One tab for every friend.',
      body: 'Add a shared meal, a ride, or borrowed cash. Keep a clear record of who owes what, together.',
      art: 'assets/branding/tabby-notebook-v3.png',
    ),
    (
      title: 'Settle up, stay friends.',
      body: 'Pay with your usual wallet, bank, or cash. Record it in Tabby; your friend confirms when it arrives.',
      art: 'assets/branding/tabby-welcome-v3.png',
    ),
  ];
  Future<void> _finish() async {
    if (_saving) return;
    final stamp = SupabaseConfig.captureSession();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await RegistrationFlow.finishIntroduction();
      if (!mounted || !SupabaseConfig.isCurrentSession(stamp)) return;
      if (!saved) throw StateError('No current account');
      context.go('/complete-profile');
    } catch (_) {
      if (mounted && SupabaseConfig.isCurrentSession(stamp)) {
        setState(
          () => _error = 'Your progress could not be saved. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final slide = _slides[_step];
    return PopScope<Object?>(
      canPop: _step == 0 && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving && _step > 0) setState(() => _step--);
      },
      child: Scaffold(
        backgroundColor: WelcomeColors.canvas(context),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 56).clamp(
                    0.0,
                    double.infinity,
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Semantics(
                                label: 'Step ${_step + 1} of 3',
                                child: LinearProgressIndicator(
                                  value: (_step + 1) / 3,
                                  minHeight: 4,
                                  borderRadius: BorderRadius.circular(8),
                                  color: WelcomeColors.amber,
                                  backgroundColor: WelcomeColors.amber
                                      .withValues(alpha: 0.18),
                                ),
                              ),
                            ),
                            const SizedBox(width: 24),
                            TextButton(
                              onPressed: _saving ? null : _finish,
                              child: Text(
                                'Skip',
                                style: TextStyle(
                                  color: WelcomeColors.muted(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        WelcomeMascot(
                          asset: slide.art,
                          size: constraints.maxHeight < 600 ? 190 : 290,
                        ),
                        const SizedBox(height: 28),
                        Text(
                          slide.title,
                          style: TextStyle(
                            color: WelcomeColors.ink(context),
                            fontSize: 30,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          slide.body,
                          style: TextStyle(
                            color: WelcomeColors.muted(context),
                            fontSize: 16,
                            height: 1.6,
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: WelcomeColors.ink(context),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 40),
                        Row(
                          children: [
                            TextButton(
                              onPressed: _step == 0 || _saving
                                  ? null
                                  : () => setState(() => _step--),
                              child: const Text('Back'),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: WelcomeColors.amber,
                                  foregroundColor: const Color(0xFF292321),
                                  minimumSize: const Size(0, 54),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                onPressed: _saving
                                    ? null
                                    : _step < 2
                                    ? () => setState(() => _step++)
                                    : _finish,
                                child: Text(
                                  _saving
                                      ? 'Saving…'
                                      : _step < 2
                                      ? 'Next'
                                      : 'Set up my profile',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
