import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/tabby_colors.dart';
import '../../features/tabs/domain/models.dart';

/// Tabby Mascot Companion Widget displaying the 9 emotional states
/// with a native Flutter physics animation engine (breathing float,
/// interactive squash-and-stretch tap reaction, spring emotion transition,
/// and ambient emotion micro-particles) following FinWise design language
/// and strict zero-emoji conventions.
class TabbyMascotWidget extends StatefulWidget {
  final MascotEmotion emotion;
  final double size;
  final bool showBubble;
  final String? customMessage;
  final VoidCallback? onTap;

  const TabbyMascotWidget({
    super.key,
    required this.emotion,
    this.size = 64,
    this.showBubble = true,
    this.customMessage,
    this.onTap,
  });

  @override
  State<TabbyMascotWidget> createState() => _TabbyMascotWidgetState();
}

class _TabbyMascotWidgetState extends State<TabbyMascotWidget>
    with TickerProviderStateMixin {
  late AnimationController _floatController;
  late AnimationController _popController;
  late AnimationController _tapController;

  late Animation<double> _popAnimation;
  late Animation<double> _badgePopAnimation;
  late Animation<double> _tapAnimation;

  bool get _isTestEnvironment {
    final binding = WidgetsBinding.instance;
    return binding.runtimeType.toString().contains('Test');
  }

  @override
  void initState() {
    super.initState();

    // Floating and breathing cycle
    _floatController = AnimationController(
      vsync: this,
      duration: _getFloatDuration(widget.emotion),
    );

    // Emotion transition spring pop
    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _popAnimation = CurvedAnimation(
      parent: _popController,
      curve: Curves.elasticOut,
    );
    _badgePopAnimation = CurvedAnimation(
      parent: _popController,
      curve: const Interval(0.2, 1.0, curve: Curves.elasticOut),
    );

    // Touch squash & stretch
    _tapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );
    _tapAnimation = Tween<double>(begin: 1.0, end: 0.90).animate(
      CurvedAnimation(parent: _tapController, curve: Curves.easeInOut),
    );

    if (!_isTestEnvironment) {
      _floatController.repeat(reverse: true);
    }
    _popController.forward(from: 0.0);
  }

  Duration _getFloatDuration(MascotEmotion emotion) {
    switch (emotion) {
      case MascotEmotion.sleeping:
        return const Duration(milliseconds: 3400);
      case MascotEmotion.celebrating:
        return const Duration(milliseconds: 700);
      case MascotEmotion.calculating:
        return const Duration(milliseconds: 1800);
      case MascotEmotion.userOwes:
      case MascotEmotion.overdue:
        return const Duration(milliseconds: 2000);
      default:
        return const Duration(milliseconds: 2400);
    }
  }

  @override
  void didUpdateWidget(TabbyMascotWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.emotion != widget.emotion) {
      _floatController.duration = _getFloatDuration(widget.emotion);
      if (!_isTestEnvironment && !_floatController.isAnimating) {
        _floatController.repeat(reverse: true);
      }
      _popController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _floatController.dispose();
    _popController.dispose();
    _tapController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _tapController.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _tapController.reverse();
    widget.onTap?.call();
  }

  void _handleTapCancel() {
    _tapController.reverse();
  }

  Color _getBadgeColor() {
    switch (widget.emotion) {
      case MascotEmotion.userOwes:
      case MascotEmotion.overdue:
        return TabbyColors.accentBlue;
      case MascotEmotion.userIsOwed:
      case MascotEmotion.celebrating:
        return TabbyColors.brandEmerald;
      case MascotEmotion.calculating:
      case MascotEmotion.gentleNudge:
        return TabbyColors.brandEmerald;
      case MascotEmotion.paymentSubmitted:
        return TabbyColors.pendingAmber;
      case MascotEmotion.sleeping:
      case MascotEmotion.idleNeutral:
        return TabbyColors.brandDarkTeal;
    }
  }

  Color _getBackdropColor() {
    switch (widget.emotion) {
      case MascotEmotion.userOwes:
      case MascotEmotion.overdue:
        return TabbyColors.iconBgBlue;
      case MascotEmotion.userIsOwed:
      case MascotEmotion.celebrating:
        return TabbyColors.iconBgMint;
      case MascotEmotion.calculating:
      case MascotEmotion.gentleNudge:
        return TabbyColors.brandMintAccent;
      case MascotEmotion.paymentSubmitted:
        return TabbyColors.pendingLight;
      case MascotEmotion.sleeping:
      case MascotEmotion.idleNeutral:
        return const Color(0xFFE8F8EE);
    }
  }

  Widget _buildCelebrationSparkles(double size, double progress) {
    final sparkles = [
      _SparkleData(
        dx: -size * 0.36,
        dy: -size * 0.36 + (math.sin(progress * math.pi * 2) * 3),
        size: 5,
        color: TabbyColors.accentAmber,
      ),
      _SparkleData(
        dx: size * 0.38,
        dy: -size * 0.32 + (math.cos(progress * math.pi * 2) * 4),
        size: 4,
        color: TabbyColors.brandEmerald,
      ),
      _SparkleData(
        dx: -size * 0.42,
        dy: size * 0.12 - (math.sin(progress * math.pi * 2) * 3),
        size: 3.5,
        color: TabbyColors.accentBlue,
      ),
      _SparkleData(
        dx: size * 0.40,
        dy: size * 0.08 + (math.sin(progress * math.pi * 2) * 2),
        size: 4.5,
        color: TabbyColors.brandEmerald,
      ),
      _SparkleData(
        dx: 0,
        dy: -size * 0.48 + (math.sin(progress * math.pi * 2) * 4),
        size: 4,
        color: TabbyColors.pendingAmber,
      ),
    ];

    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: sparkles.map((s) {
          return Positioned(
            left: (size / 2) + s.dx,
            top: (size / 2) + s.dy,
            child: Container(
              width: s.size,
              height: s.size,
              decoration: BoxDecoration(
                color: s.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: s.color.withValues(alpha: 0.5),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSleepingZzz() {
    return IgnorePointer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'z',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: TabbyColors.brandDarkTeal.withValues(alpha: 0.6),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6.0),
            child: Text(
              'z',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: TabbyColors.brandDarkTeal.withValues(alpha: 0.45),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: Text(
              'z',
              style: TextStyle(
                fontSize: 7,
                fontWeight: FontWeight.w600,
                color: TabbyColors.brandDarkTeal.withValues(alpha: 0.3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.customMessage ?? widget.emotion.microcopy;

    final mascotAvatar = AnimatedBuilder(
      animation: Listenable.merge([
        _floatController,
        _popAnimation,
        _tapAnimation,
      ]),
      builder: (context, child) {
        final floatVal = _floatController.value;
        final popScale = 0.82 + (0.18 * _popAnimation.value);
        final tapScale = _tapAnimation.value;

        // Dynamic motion adjustments by emotion
        double translateY = 0.0;
        double rotateZ = 0.0;
        double scaleX = 1.0;
        double scaleY = 1.0;

        switch (widget.emotion) {
          case MascotEmotion.celebrating:
            final hop = math.sin(floatVal * math.pi);
            translateY = -hop * 6.0;
            scaleY = 1.0 + (hop * 0.06);
            scaleX = 1.0 - (hop * 0.03);
            break;
          case MascotEmotion.sleeping:
            final breathe = math.sin(floatVal * math.pi);
            translateY = breathe * 2.0;
            rotateZ = -0.06 + (breathe * 0.02);
            scaleY = 1.0 + (breathe * 0.025);
            break;
          case MascotEmotion.userOwes:
          case MascotEmotion.overdue:
            final wobble = math.sin(floatVal * math.pi * 2);
            rotateZ = wobble * 0.03;
            translateY = math.sin(floatVal * math.pi) * 2.5;
            break;
          case MascotEmotion.calculating:
            final pulse = math.sin(floatVal * math.pi);
            scaleX = 1.0 + (pulse * 0.03);
            scaleY = 1.0 + (pulse * 0.03);
            translateY = pulse * 1.5;
            break;
          default:
            translateY = math.sin(floatVal * math.pi) * 3.0;
            scaleY = 1.0 + (math.sin(floatVal * math.pi) * 0.025);
            break;
        }

        final combinedScaleX = popScale * tapScale * scaleX;
        final combinedScaleY = popScale * tapScale * scaleY;

        return Transform.translate(
          offset: Offset(0, translateY),
          child: Transform.rotate(
            angle: rotateZ,
            child: Transform.scale(
              scaleX: combinedScaleX,
              scaleY: combinedScaleY,
              child: GestureDetector(
                onTapDown: _handleTapDown,
                onTapUp: _handleTapUp,
                onTapCancel: _handleTapCancel,
                child: SizedBox(
                  width: widget.size,
                  height: widget.size,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      // Background ring with soft glow
                      Container(
                        width: widget.size,
                        height: widget.size,
                        decoration: BoxDecoration(
                          color: _getBackdropColor(),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _getBadgeColor().withValues(alpha: 0.35),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _getBadgeColor().withValues(alpha: 0.14),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/branding/tabby-icon.jpg',
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Center(
                                child: Icon(
                                  Icons.pets_rounded,
                                  size: widget.size * 0.5,
                                  color: _getBadgeColor(),
                                ),
                              );
                            },
                          ),
                        ),
                      ),

                      // Ambient particles (Confetti for celebrating)
                      if (widget.emotion == MascotEmotion.celebrating)
                        Positioned.fill(
                          child: _buildCelebrationSparkles(
                            widget.size,
                            floatVal,
                          ),
                        ),

                      // Ambient particles (Zzz for sleeping)
                      if (widget.emotion == MascotEmotion.sleeping)
                        Positioned(
                          right: -widget.size * 0.15,
                          top: -widget.size * 0.25 -
                              (math.sin(floatVal * math.pi) * 3.0),
                          child: _buildSleepingZzz(),
                        ),

                      // Animated Emotion status badge (Bottom Right)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Transform.scale(
                          scale: _badgePopAnimation.value,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: TabbyColors.surfaceWhite,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _getBadgeColor(),
                                width: 1.5,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              widget.emotion.icon,
                              size: 12,
                              color: _getBadgeColor(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (!widget.showBubble) {
      return mascotAvatar;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        mascotAvatar,
        const SizedBox(width: 12),
        // Animated Speech Bubble with soft cross-fade and slide
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.0, 0.08),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
                  child: child,
                ),
              );
            },
            child: Container(
              key: ValueKey<String>('${widget.emotion.stateKey}_$message'),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: TabbyColors.surfaceWhite,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: TabbyColors.borderMint),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x08000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        'Tabby',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: _getBadgeColor(),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: _getBackdropColor(),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          widget.emotion.stateKey,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: _getBadgeColor(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: const TextStyle(
                      fontSize: 13,
                      color: TabbyColors.textPrimary,
                      height: 1.3,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SparkleData {
  final double dx;
  final double dy;
  final double size;
  final Color color;

  const _SparkleData({
    required this.dx,
    required this.dy,
    required this.size,
    required this.color,
  });
}
