import 'package:flutter/material.dart';
import '../../core/theme/tabby_colors.dart';
import '../../features/tabs/domain/models.dart';

/// Tabby Mascot Companion Widget displaying the 9 emotional states
/// defined in AGENTS.md Section 4.
class TabbyMascotWidget extends StatelessWidget {
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

  Color _getBadgeColor() {
    switch (emotion) {
      case MascotEmotion.userOwes:
      case MascotEmotion.overdue:
        return TabbyColors.debtRed;
      case MascotEmotion.userIsOwed:
      case MascotEmotion.celebrating:
        return TabbyColors.successGreen;
      case MascotEmotion.calculating:
      case MascotEmotion.gentleNudge:
        return TabbyColors.accentAmber;
      case MascotEmotion.paymentSubmitted:
        return TabbyColors.pendingAmber;
      case MascotEmotion.sleeping:
      case MascotEmotion.idleNeutral:
        return TabbyColors.primaryCharcoal;
    }
  }

  Color _getBackdropColor() {
    switch (emotion) {
      case MascotEmotion.userOwes:
      case MascotEmotion.overdue:
        return TabbyColors.debtLight;
      case MascotEmotion.userIsOwed:
      case MascotEmotion.celebrating:
        return TabbyColors.successLight;
      case MascotEmotion.calculating:
      case MascotEmotion.gentleNudge:
        return TabbyColors.pendingLight;
      case MascotEmotion.paymentSubmitted:
        return const Color(0xFFFEF3C7);
      case MascotEmotion.sleeping:
      case MascotEmotion.idleNeutral:
        return const Color(0xFFF3F4F6);
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = customMessage ?? emotion.microcopy;

    final mascotAvatar = GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Background glow
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: _getBackdropColor(),
              shape: BoxShape.circle,
              border: Border.all(
                color: _getBadgeColor().withValues(alpha: 0.3),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: _getBadgeColor().withValues(alpha: 0.12),
                  blurRadius: 10,
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
                    child: Text(
                      emotion.emoji,
                      style: TextStyle(fontSize: size * 0.45),
                    ),
                  );
                },
              ),
            ),
          ),

          // Emotion status badge (Bottom Right)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: TabbyColors.surfaceWhite,
                shape: BoxShape.circle,
                border: Border.all(color: _getBadgeColor(), width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                emotion.emoji,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );

    if (!showBubble) {
      return mascotAvatar;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        mascotAvatar,
        const SizedBox(width: 12),
        // Speech Bubble
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: TabbyColors.surfaceWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: TabbyColors.borderGray),
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
                        fontWeight: FontWeight.w700,
                        color: _getBadgeColor(),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: _getBackdropColor(),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        emotion.stateKey,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
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
                    color: TabbyColors.primaryCharcoal,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
