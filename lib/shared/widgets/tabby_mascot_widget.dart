import '../../core/theme/motion_preferences.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/tabby_colors.dart';
import '../../core/theme/tabby_palette.dart';
import '../../features/tabs/domain/models.dart';
import 'tabby_mascot_art.dart';
export 'tabby_mascot_art.dart' show TabbyMascotPose;

TabbyMascotPose mascotPoseForEmotion(MascotEmotion emotion) =>
    switch (emotion) {
      MascotEmotion.idleNeutral => TabbyMascotPose.neutral,
      MascotEmotion.userOwes ||
      MascotEmotion.userIsOwed => TabbyMascotPose.notebook,
      MascotEmotion.calculating => TabbyMascotPose.thinking,
      MascotEmotion.gentleNudge ||
      MascotEmotion.overdue => TabbyMascotPose.reminder,
      MascotEmotion.paymentSubmitted => TabbyMascotPose.waiting,
      MascotEmotion.celebrating => TabbyMascotPose.celebrating,
      MascotEmotion.sleeping => TabbyMascotPose.sleeping,
    };

/// Tabby Mascot Companion Widget displaying the 9 emotional states
/// with a native Flutter physics animation engine (breathing float,
/// interactive squash-and-stretch tap reaction, spring emotion transition,
/// and ambient emotion micro-particles) following Tabby design language
/// and strict zero-emoji conventions.
class TabbyMascotWidget extends StatefulWidget {
  final MascotEmotion emotion;
  final double size;
  final bool showBubble;
  final bool showBackdrop;
  final bool showStatusBadge;
  final String? customMessage;
  final VoidCallback? onTap;
  final TabbyMascotPose? pose;

  /// Allows tests to exercise the production ambient controller.
  final bool? animateAmbient;

  const TabbyMascotWidget({
    super.key,
    required this.emotion,
    this.size = 64,
    this.showBubble = true,
    this.showBackdrop = true,
    this.showStatusBadge = true,
    this.customMessage,
    this.onTap,
    this.animateAmbient,
    this.pose,
  });

  const TabbyMascotWidget.art({
    super.key,
    required TabbyMascotPose this.pose,
    this.size = 120,
    this.animateAmbient,
    this.onTap,
  }) : emotion = MascotEmotion.idleNeutral,
       showBubble = false,
       showBackdrop = false,
       showStatusBadge = false,
       customMessage = null;

  @override
  State<TabbyMascotWidget> createState() => _TabbyMascotWidgetState();
}

class _TabbyMascotWidgetState extends State<TabbyMascotWidget>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _floatController;
  late AnimationController _popController;
  late AnimationController _tapController;

  late Animation<double> _popAnimation;
  late Animation<double> _badgePopAnimation;
  late Animation<double> _tapAnimation;

  bool _motionEnabled = false;
  bool _foreground = true;
  bool _reducedMotion = true;
  bool _hasEntered = false;
  bool _celebrationPlayed = false;
  TabbyMascotPose get _pose =>
      widget.pose ?? mascotPoseForEmotion(widget.emotion);
  bool get _ambient => widget.animateAmbient ?? !_isTestEnvironment;

  bool get _isTestEnvironment {
    final binding = WidgetsBinding.instance;
    return binding.runtimeType.toString().contains('Test');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;

    // Floating and breathing cycle
    _floatController = AnimationController(
      vsync: this,
      duration: _getFloatDuration(_pose),
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
    _tapAnimation = Tween<double>(
      begin: 1.0,
      end: 0.90,
    ).animate(CurvedAnimation(parent: _tapController, curve: Curves.easeInOut));
  }

  Duration _getFloatDuration(TabbyMascotPose pose) => Duration(
    milliseconds: switch (pose) {
      TabbyMascotPose.sleeping => 3400,
      TabbyMascotPose.celebrating => 1200,
      TabbyMascotPose.thinking => 2200,
      TabbyMascotPose.reminder => 2600,
      _ => 3000,
    },
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncMotion();
  }

  void _syncMotion({bool restart = false}) {
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    final allowed =
        !_reducedMotion &&
        _foreground &&
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    final changed = allowed != _motionEnabled;
    _motionEnabled = allowed;
    if (!allowed) {
      _floatController.stop();
      _popController.stop();
      _tapController.stop();
      if (_reducedMotion) {
        _floatController.value = 0;
        _popController.value = 1;
        _tapController.value = 0;
        if (_pose == TabbyMascotPose.celebrating) _celebrationPlayed = true;
      } else if (_pose == TabbyMascotPose.celebrating && _celebrationPlayed) {
        _floatController.value = 1;
      }
      return;
    }
    if (restart || !_hasEntered) {
      _hasEntered = true;
      _popController.forward(from: 0);
    } else if (changed) {
      _popController.value = 1;
    }
    if (!_ambient) {
      _floatController.stop();
    } else if (_pose == TabbyMascotPose.celebrating) {
      if (!_celebrationPlayed) {
        _celebrationPlayed = true;
        _floatController.forward(from: 0);
      }
    } else if (!_floatController.isAnimating || restart) {
      _floatController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(TabbyMascotWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPose = oldWidget.pose ?? mascotPoseForEmotion(oldWidget.emotion);
    if (oldPose != _pose) {
      _floatController.stop();
      _floatController.value = 0;
      _floatController.duration = _getFloatDuration(_pose);
      _celebrationPlayed = false;
      _syncMotion(restart: true);
    } else if (oldWidget.animateAmbient != widget.animateAmbient) {
      _syncMotion();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _floatController.dispose();
    _popController.dispose();
    _tapController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (_motionEnabled) _tapController.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    if (_motionEnabled) _tapController.reverse();
    widget.onTap?.call();
  }

  void _handleTapCancel() {
    _tapController.reverse();
  }

  Color _getBadgeColor() {
    switch (widget.emotion) {
      case MascotEmotion.userOwes:
      case MascotEmotion.overdue:
        return TabbyPalette.of(context).link;
      case MascotEmotion.userIsOwed:
      case MascotEmotion.celebrating:
        return TabbyPalette.of(context).link;
      case MascotEmotion.calculating:
      case MascotEmotion.gentleNudge:
        return TabbyPalette.of(context).link;
      case MascotEmotion.paymentSubmitted:
        return TabbyPalette.of(context).link;
      case MascotEmotion.sleeping:
      case MascotEmotion.idleNeutral:
        return TabbyPalette.of(context).link;
    }
  }

  Color _getBackdropColor() {
    switch (widget.emotion) {
      case MascotEmotion.userOwes:
      case MascotEmotion.overdue:
        return TabbyPalette.of(context).accentTint;
      case MascotEmotion.userIsOwed:
      case MascotEmotion.celebrating:
        return TabbyPalette.of(context).soft;
      case MascotEmotion.calculating:
      case MascotEmotion.gentleNudge:
        return TabbyPalette.of(context).soft;
      case MascotEmotion.paymentSubmitted:
        return TabbyPalette.of(context).pendingTint;
      case MascotEmotion.sleeping:
      case MascotEmotion.idleNeutral:
        return TabbyPalette.of(context).soft;
    }
  }

  Widget _buildCelebrationSparkles(double size, double progress) {
    final sparkles = [
      _SparkleData(
        dx: -size * 0.36,
        dy: -size * 0.36 + (math.sin(progress * math.pi * 2) * 3),
        size: 5,
        color: TabbyColors.brandAmber,
      ),
      _SparkleData(
        dx: size * 0.38,
        dy: -size * 0.32 + (math.cos(progress * math.pi * 2) * 4),
        size: 4,
        color: TabbyColors.brandAmber,
      ),
      _SparkleData(
        dx: -size * 0.42,
        dy: size * 0.12 - (math.sin(progress * math.pi * 2) * 3),
        size: 3.5,
        color: TabbyColors.accentBurnt,
      ),
      _SparkleData(
        dx: size * 0.40,
        dy: size * 0.08 + (math.sin(progress * math.pi * 2) * 2),
        size: 4.5,
        color: TabbyColors.brandAmber,
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
              color: TabbyPalette.of(context).text.withValues(alpha: 0.6),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6.0),
            child: Text(
              'z',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: TabbyPalette.of(context).text.withValues(alpha: 0.45),
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
                color: TabbyPalette.of(context).text.withValues(alpha: 0.3),
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
        final popScale = _reducedMotion
            ? 1.0
            : 0.92 + (0.08 * _popAnimation.value);
        final tapScale = _reducedMotion ? 1.0 : _tapAnimation.value;

        // Dynamic motion adjustments by emotion
        double translateY = 0.0;
        double rotateZ = 0.0;
        double scaleX = 1.0;
        double scaleY = 1.0;

        if (!_reducedMotion) {
          final wave = math.sin(floatVal * math.pi);
          switch (_pose) {
            case TabbyMascotPose.celebrating:
              final hop =
                  math.sin(floatVal * math.pi * 3).abs() * (1 - floatVal);
              translateY = -hop * widget.size * 0.07;
              scaleY = 1 + hop * 0.04;
              scaleX = 1 - hop * 0.02;
              break;
            case TabbyMascotPose.thinking:
              rotateZ = math.sin(floatVal * math.pi * 2) * 0.018;
              translateY = -wave * widget.size * 0.012;
              break;
            case TabbyMascotPose.waiting:
            case TabbyMascotPose.helpful:
              rotateZ = math.sin(floatVal * math.pi * 2) * 0.012;
              scaleY = 1 + wave * 0.012;
              translateY = -wave * widget.size * 0.008;
              break;
            case TabbyMascotPose.reminder:
              rotateZ = math.sin(floatVal * math.pi * 2) * 0.022;
              translateY = -wave * widget.size * 0.012;
              break;
            case TabbyMascotPose.sleeping:
              scaleY = 1 + wave * 0.02;
              break;
            default:
              translateY = -wave * widget.size * 0.015;
              scaleY = 1 + wave * 0.012;
          }
        }

        final combinedScaleX = popScale * tapScale * scaleX;
        final combinedScaleY = popScale * tapScale * scaleY;

        return Transform.translate(
          key: const ValueKey('mascot-motion'),
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
                        decoration: widget.showBackdrop
                            ? BoxDecoration(
                                color: _getBackdropColor(),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _getBadgeColor().withValues(
                                    alpha: 0.35,
                                  ),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _getBadgeColor().withValues(
                                      alpha: 0.14,
                                    ),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              )
                            : null,
                        child: Padding(
                          padding: EdgeInsets.all(widget.size * 0.04),
                          child: AnimatedSwitcher(
                            duration: TabbyMotion.duration(
                              context,
                              const Duration(milliseconds: 180),
                            ),
                            child: TabbyMascotArt(
                              key: ValueKey(_pose),
                              pose: _pose,
                              size: widget.size,
                              animate: _motionEnabled && _ambient,
                            ),
                          ),
                        ),
                      ),

                      // Ambient particles (Confetti for celebrating)
                      if (_pose == TabbyMascotPose.celebrating &&
                          _motionEnabled &&
                          _ambient &&
                          _floatController.value < 1)
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
                          top:
                              -widget.size * 0.25 -
                              (math.sin(floatVal * math.pi) * 3.0),
                          child: _buildSleepingZzz(),
                        ),

                      // Animated Emotion status badge (Bottom Right)
                      if (widget.showStatusBadge)
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Transform.scale(
                            scale: _badgePopAnimation.value,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: TabbyPalette.of(context).surface,
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
            duration: TabbyMotion.duration(
              context,
              _motionEnabled
                  ? const Duration(milliseconds: 280)
                  : Duration.zero,
            ),
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position:
                      Tween<Offset>(
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
                color: TabbyPalette.of(context).surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: TabbyPalette.of(context).border),
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
                          widget.emotion.label,
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
                    style: TextStyle(
                      fontSize: 13,
                      color: TabbyPalette.of(context).text,
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
