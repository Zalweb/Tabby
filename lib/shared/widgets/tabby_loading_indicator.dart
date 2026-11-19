import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/tabby_palette.dart';
import 'tabby_mascot_art.dart';

/// Indeterminate work, never a simulated percentage or minimum waiting time.
/// Uses the approved thinking art and its existing blink/tail frame sheet.
class TabbyLoadingIndicator extends StatefulWidget {
  const TabbyLoadingIndicator({
    super.key,
    this.label = 'Loading…',
    this.size = 88,
    this.color,
  }) : inline = false,
       dotsOnly = false;

  const TabbyLoadingIndicator.startup({super.key})
    : label = 'Starting Tabby…',
      size = 148,
      color = null,
      inline = false,
      dotsOnly = false;

  /// Sized to replace small progress glyphs inside existing controls.
  const TabbyLoadingIndicator.inline({
    super.key,
    this.label = 'Loading…',
    this.size = 22,
    this.color,
  }) : inline = true,
       dotsOnly = false;

  /// Compact activity feedback for a pending action.
  const TabbyLoadingIndicator.dots({super.key, required this.label, this.color})
    : inline = false,
      dotsOnly = true,
      size = 16;

  final String label;
  final double size;
  final Color? color;
  final bool inline;
  final bool dotsOnly;

  @override
  State<TabbyLoadingIndicator> createState() => _TabbyLoadingIndicatorState();
}

class _TabbyLoadingIndicatorState extends State<TabbyLoadingIndicator>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  bool _foreground = true;
  bool _active = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  void _syncMotion() {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _active =
        !reduced &&
        _foreground &&
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    if (_active) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
      if (reduced) _controller.value = 0;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      _syncMotion();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = TabbyPalette.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      label: widget.label,
      value: 'In progress',
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final requested = widget.size.clamp(16.0, 180.0);
              final size = constraints.maxWidth.isFinite
                  ? math.min(requested, constraints.maxWidth)
                  : requested;
              final artwork = SizedBox.square(
                dimension: size,
                child: TabbyMascotArt(
                  pose: TabbyMascotPose.thinking,
                  animate: _active && !widget.inline,
                  size: size,
                ),
              );
              return AnimatedBuilder(
                animation: _controller,
                child: artwork,
                builder: (context, art) {
                  final phase = _active ? _controller.value : 0.0;
                  if (widget.dotsOnly) {
                    return CustomPaint(
                      key: const ValueKey('tabby-loading-dots'),
                      size: const Size(42, 12),
                      painter: TabbyLoadingDotsPainter(
                        phase: phase,
                        color: widget.color ?? p.link,
                        active: _active,
                      ),
                    );
                  }
                  final lift = (1 - math.cos(phase * math.pi * 2)) / 2;
                  final move = Transform(
                    key: const ValueKey('tabby-loading-mascot-motion'),
                    alignment: Alignment.bottomCenter,
                    transform: Matrix4.identity()
                      ..translateByDouble(0, -size * 0.035 * lift, 0, 1)
                      ..rotateZ(math.sin(phase * math.pi * 2) * 0.025),
                    child: art,
                  );
                  if (widget.inline) return move;
                  final panel = Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: size + 24,
                        height: size + 20,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: size * 0.9,
                              height: size * 0.9,
                              decoration: BoxDecoration(
                                color: p.soft,
                                shape: BoxShape.circle,
                              ),
                            ),
                            Positioned(
                              bottom: 3,
                              child: Transform.scale(
                                scaleX: 1 - lift * 0.12,
                                child: Container(
                                  width: size * 0.52,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: p.controlBorder.withValues(
                                      alpha: 0.16,
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: move,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      CustomPaint(
                        key: const ValueKey('tabby-loading-dots'),
                        size: const Size(42, 12),
                        painter: TabbyLoadingDotsPainter(
                          phase: phase,
                          color: widget.color ?? p.link,
                          active: _active,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: p.secondaryText,
                          fontSize: 14,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  );
                  return constraints.hasBoundedHeight
                      ? SingleChildScrollView(primary: false, child: panel)
                      : panel;
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Painted activity dots do not create three noisy semantic announcements.
class TabbyLoadingDotsPainter extends CustomPainter {
  const TabbyLoadingDotsPainter({
    required this.phase,
    required this.color,
    required this.active,
  });
  final double phase;
  final Color color;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 3; i++) {
      final pulse = active
          ? math.max(0.0, math.sin((phase - i * 0.16) * math.pi * 2))
          : 0.0;
      canvas.drawCircle(
        Offset(size.width / 2 + (i - 1) * 13, size.height / 2 - pulse * 2),
        2.5 + pulse * 0.5,
        Paint()
          ..color = color.withValues(
            alpha: active ? 0.35 + pulse * 0.65 : 0.65,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(TabbyLoadingDotsPainter oldDelegate) =>
      phase != oldDelegate.phase ||
      color != oldDelegate.color ||
      active != oldDelegate.active;
}
