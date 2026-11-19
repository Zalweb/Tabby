import 'package:flutter/material.dart';

import '../../../core/config/app_state.dart';
import '../../../core/theme/motion_preferences.dart';
import '../../../core/theme/tabby_palette.dart';
import '../../auth/presentation/auth_welcome_widgets.dart';
import '../application/first_launch_tour.dart';

/// Signed-out first-launch tour shown before Google sign-in on fresh installs.
/// Acknowledgment is a local install marker; it needs no account or network.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  bool _saving = false;
  String? _error;
  final ScrollController _scroll = ScrollController();
  static const _slides = [
    (
      title: 'One tab for every friend.',
      body: 'Hi, I’m Tabby — your friendly tab keeper. Add a shared meal or any cost you split, and I’ll keep a clear record of who paid and who owes what.',
      art: 'assets/branding/tabby-welcome-v3.png',
    ),
    (
      title: 'Balances and receipts, together.',
      body: 'Each tab keeps a running balance. Attach receipts to expenses so everyone on that tab can see the same record.',
      art: 'assets/branding/tabby-notebook-v3.png',
    ),
    (
      title: 'Settle up, stay friends.',
      body: 'Pay with your usual wallet, bank, or cash. Record it in Tabby. Your friend confirms when it arrives.',
      art: 'assets/branding/tabby-welcome-v3.png',
    ),
  ];

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _goToStep(int step) {
    setState(() => _step = step);
    // Each step starts reading from the top, even after scrolling a long
    // large-text step to reach the actions.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  Future<void> _acknowledge() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await FirstLaunchTour.acknowledge();
      if (!mounted) return;
      // The router reacts to the seen marker and keeps recovery/auth
      // precedence; a session that arrived mid-save owns its destination.
      // No redundant manual navigation is needed.
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Your progress could not be saved. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Clears the intro for this launch only when the marker cannot be saved.
  /// The router reacts to the in-memory flag and keeps recovery/auth
  /// precedence, so sign-in is never blocked by an optional marker.
  void _continueForNow() {
    AppState.hasSeenOnboarding.value = true;
  }

  @override
  Widget build(BuildContext context) {
    final slide = _slides[_step];
    return PopScope<Object?>(
      canPop: _step == 0 && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving && _step > 0) _goToStep(_step - 1);
      },
      child: Scaffold(
        backgroundColor: WelcomeColors.canvas(context),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.all(28),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 460,
                    minHeight: (constraints.maxHeight - 56).clamp(
                      0.0,
                      double.infinity,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? WelcomeColors.amber
                                    : TabbyPalette.of(context).link,
                                backgroundColor: WelcomeColors.amber.withValues(
                                  alpha: 0.18,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 24),
                          TextButton(
                            style: TextButton.styleFrom(
                              minimumSize: const Size(48, 48),
                            ),
                            onPressed: _saving ? null : _acknowledge,
                            child: Text(
                              'Skip',
                              style: TextStyle(
                                color: WelcomeColors.muted(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 28, bottom: 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedSwitcher(
                              duration: TabbyMotion.duration(
                                context,
                                const Duration(milliseconds: 200),
                              ),
                              child: Column(
                                key: ValueKey<int>(_step),
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Center(
                                    child: WelcomeMascot(
                                      asset: slide.art,
                                      size: (constraints.maxHeight * 0.29)
                                          .clamp(170.0, 290.0),
                                    ),
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
                                ],
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
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      minimumSize: const Size(48, 48),
                                    ),
                                    onPressed: _saving ? null : _acknowledge,
                                    child: const Text('Retry'),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextButton(
                                      style: TextButton.styleFrom(
                                        minimumSize: const Size(48, 48),
                                      ),
                                      onPressed: _saving
                                          ? null
                                          : _continueForNow,
                                      child: const Text(
                                        'Continue to sign in for now',
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          TextButton(
                            style: TextButton.styleFrom(
                              minimumSize: const Size(48, 48),
                            ),
                            onPressed: _step == 0 || _saving
                                ? null
                                : () => _goToStep(_step - 1),
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
                                  ? () => _goToStep(_step + 1)
                                  : _acknowledge,
                              child: Text(
                                _saving
                                    ? 'Saving…'
                                    : _step < 2
                                    ? 'Next'
                                    : 'Continue to sign in',
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
    );
  }
}
