import 'package:flutter/material.dart';
import '../../core/theme/tabby_colors.dart';
import '../../features/tabs/domain/models.dart';

/// Tabby Mascot Companion Widget displaying the 9 emotional states
/// styled in the FinWise design language with clean Material icons (no emojis).
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
    switch (emotion) {
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

  @override
  Widget build(BuildContext context) {
    final message = customMessage ?? emotion.microcopy;

    final mascotAvatar = GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Background ring
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: _getBackdropColor(),
              shape: BoxShape.circle,
              border: Border.all(
                color: _getBadgeColor().withValues(alpha: 0.35),
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
                    child: Icon(
                      Icons.pets_rounded,
                      size: size * 0.5,
                      color: _getBadgeColor(),
                    ),
                  );
                },
              ),
            ),
          ),

          // Emotion status badge (Bottom Right) with clean Material icon (NO emojis)
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
              child: Icon(
                emotion.icon,
                size: 12,
                color: _getBadgeColor(),
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
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: _getBackdropColor(),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        emotion.stateKey,
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
      ],
    );
  }
}
