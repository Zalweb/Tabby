import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../../core/config/app_state.dart';
import '../../../core/theme/motion_preferences.dart';
import '../../../core/theme/tabby_colors.dart';
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

  final PageController _pageController = PageController();
  final List<ScrollController> _slideScrollControllers = List.generate(
    _slides.length,
    (_) => ScrollController(),
  );
  final ValueNotifier<double> _pageProgress = ValueNotifier(0);
  int _step = 0;
  bool _pageMoving = false;
  bool _saving = false;
  String? _error;

  bool get _canAct {
    if (_saving || _pageMoving) return false;
    final page = _pageController.hasClients
        ? _pageController.page
        : _pageProgress.value;
    return page != null && (page - _step).abs() < 0.001;
  }

  @override
  void initState() {
    super.initState();
    _pageController.addListener(_updatePageProgress);
  }

  @override
  void dispose() {
    _pageController
      ..removeListener(_updatePageProgress)
      ..dispose();
    for (final controller in _slideScrollControllers) {
      controller.dispose();
    }
    _pageProgress.dispose();
    super.dispose();
  }

  void _updatePageProgress() {
    if (!_pageController.hasClients) return;
    final next = (_pageController.page ?? _step.toDouble()).clamp(
      0.0,
      (_slides.length - 1).toDouble(),
    );
    if ((next - _pageProgress.value).abs() < 0.001) return;
    _pageProgress.value = next;
  }

  void _settleAtCurrentPage() {
    if (!_pageController.hasClients) return;
    final page = (_pageController.page ?? _step.toDouble()).clamp(
      0.0,
      (_slides.length - 1).toDouble(),
    );
    final settledStep = page.round();
    _pageProgress.value = page;
    if ((page - settledStep).abs() >= 0.001) return;
    if (!_pageMoving && _step == settledStep) return;
    setState(() {
      _step = settledStep;
      _pageMoving = false;
    });
  }

  bool _onPageScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification && !_pageMoving) {
      setState(() => _pageMoving = true);
    } else if (notification is ScrollEndNotification) {
      _settleAtCurrentPage();
    }
    return false;
  }

  Future<void> _moveToStep(int step) async {
    if (!_canAct || step < 0 || step >= _slides.length || step == _step) {
      return;
    }
    setState(() => _pageMoving = true);
    if (TabbyMotion.disabled(context)) {
      _pageController.jumpToPage(step);
      _settleAtCurrentPage();
    } else {
      await _pageController.animateToPage(
        step,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeInOutCubic,
      );
      if (mounted) _settleAtCurrentPage();
    }
  }

  Future<void> _acknowledge() async {
    if (!_canAct) return;
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

  Widget _buildSlide(int index, BoxConstraints constraints) {
    final slide = _slides[index];
    final artSize = (constraints.maxHeight * 0.32).clamp(84.0, 252.0);
    return ExcludeSemantics(
      excluding: index != _step,
      child: SingleChildScrollView(
        key: PageStorageKey<String>('first-launch-slide-$index'),
        controller: _slideScrollControllers[index],
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: WelcomeMascot(asset: slide.art, size: artSize),
                ),
                const SizedBox(height: 24),
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
                      style: TextStyle(color: WelcomeColors.ink(context)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: _canAct ? _acknowledge : null,
                        child: const Text('Retry'),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: _canAct ? _continueForNow : null,
                        child: const Text(
                          'Continue to sign in for now',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = TabbyPalette.of(context);
    final trackColor = Theme.of(context).brightness == Brightness.dark
        ? palette.soft
        : Color.alphaBlend(
            TabbyColors.brandAmber.withValues(alpha: 0.36),
            palette.canvas,
          );

    return PopScope<Object?>(
      canPop: _step == 0 && _canAct,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _canAct && _step > 0) {
          unawaited(_moveToStep(_step - 1));
        }
      },
      child: Scaffold(
        backgroundColor: WelcomeColors.canvas(context),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        ValueListenableBuilder<double>(
                          valueListenable: _pageProgress,
                          builder: (context, progress, _) => WormPageIndicator(
                            progress: progress,
                            step: _step,
                            indicatorColor: palette.link,
                            trackColor: trackColor,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: _canAct ? _acknowledge : null,
                          child: Text(
                            'Skip',
                            style: TextStyle(
                              color: WelcomeColors.muted(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: _onPageScroll,
                        child: PageView.builder(
                          controller: _pageController,
                          itemCount: _slides.length,
                          allowImplicitScrolling: false,
                          itemBuilder: (context, index) => LayoutBuilder(
                            builder: (context, constraints) =>
                                _buildSlide(index, constraints),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        TextButton(
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: _canAct && _step > 0
                              ? () => _moveToStep(_step - 1)
                              : null,
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
                            onPressed: _canAct
                                ? () {
                                    if (_step < _slides.length - 1) {
                                      _moveToStep(_step + 1);
                                    } else {
                                      _acknowledge();
                                    }
                                  }
                                : null,
                            child: Text(
                              _saving
                                  ? 'Saving…'
                                  : _step < _slides.length - 1
                                  ? 'Next'
                                  : 'Get started',
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
    );
  }
}

/// Three page markers with a worm that follows the shared page offset.
class WormPageIndicator extends StatelessWidget {
  const WormPageIndicator({
    required this.progress,
    required this.step,
    required this.indicatorColor,
    required this.trackColor,
    super.key,
  });

  final double progress;
  final int step;
  final Color indicatorColor;
  final Color trackColor;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    label: 'Step ${step + 1} of 3',
    child: ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: const Size(58, 16),
          painter: _WormIndicatorPainter(
            progress: progress,
            indicatorColor: indicatorColor,
            trackColor: trackColor,
          ),
        ),
      ),
    ),
  );
}

class _WormIndicatorPainter extends CustomPainter {
  const _WormIndicatorPainter({
    required this.progress,
    required this.indicatorColor,
    required this.trackColor,
  });

  final double progress;
  final Color indicatorColor;
  final Color trackColor;

  static const _radius = 5.0;
  static const _trackRadius = 4.0;
  static const _spacing = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final trackPaint = Paint()..color = trackColor;
    for (var index = 0; index < 3; index++) {
      canvas.drawCircle(
        Offset(_radius + index * _spacing, centerY),
        _trackRadius,
        trackPaint,
      );
    }

    final page = progress.clamp(0.0, 2.0);
    final segment = page >= 2 ? 1 : page.floor();
    final fraction = page >= 2 ? 1.0 : page - segment;
    final startCenter = _radius + segment * _spacing;
    final endCenter = startCenter + _spacing;
    late final double left;
    late final double right;
    if (fraction <= 0.5) {
      left = startCenter - _radius;
      right = lerpDouble(
        startCenter + _radius,
        endCenter + _radius,
        fraction * 2,
      )!;
    } else {
      left = lerpDouble(
        startCenter - _radius,
        endCenter - _radius,
        (fraction - 0.5) * 2,
      )!;
      right = endCenter + _radius;
    }
    final wormPaint = Paint()..color = indicatorColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(left, centerY - _radius, right, centerY + _radius),
        const Radius.circular(_radius),
      ),
      wormPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _WormIndicatorPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.indicatorColor != indicatorColor ||
      oldDelegate.trackColor != trackColor;
}
