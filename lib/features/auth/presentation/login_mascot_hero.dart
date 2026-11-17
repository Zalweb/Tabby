import 'package:flutter/material.dart';

import '../../../core/theme/tabby_colors.dart';
import '../../../core/theme/tabby_palette.dart';
import '../../../shared/widgets/tabby_mascot_widget.dart';
import '../../tabs/domain/models.dart';

/// An illustration-sized treatment of the approved character, without the
/// compact status ring used next to financial messages elsewhere in the app.
class LoginMascotHero extends StatelessWidget {
  final bool compact;

  const LoginMascotHero({super.key, required this.compact});

  @override
  Widget build(BuildContext context) {
    final palette = TabbyPalette.of(context);
    final showGreeting = MediaQuery.textScalerOf(context).scale(13) < 20;
    final characterSize = compact ? 168.0 : 264.0;
    final artHeight = compact ? 198.0 : 324.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Tabby',
          style: TextStyle(
            color: palette.text,
            fontSize: compact ? 30 : 34,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Keep tabs. Settle up.',
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.secondaryText, fontSize: 14),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: artHeight,
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final orbSize = compact ? 164.0 : 268.0;
              return Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Positioned(
                    bottom: 8,
                    child: Container(
                      width: orbSize,
                      height: orbSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            palette.mint,
                            TabbyColors.brandAmber.withValues(alpha: 0.15),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 3,
                    child: Container(
                      width: characterSize * 0.62,
                      height: 13,
                      decoration: BoxDecoration(
                        color: palette.text.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: compact ? 108 : 172,
                    left: (constraints.maxWidth - orbSize) / 2 - 18,
                    child: ExcludeSemantics(
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        size: compact ? 19 : 25,
                        color: palette.positiveText.withValues(alpha: 0.65),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: compact ? 48 : 68,
                    right: (constraints.maxWidth - orbSize) / 2 - 8,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: TabbyColors.brandAmber,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Semantics(
                      image: true,
                      label: 'Tabby, your friendly cat companion',
                      child: TabbyMascotWidget(
                        emotion: MascotEmotion.idleNeutral,
                        size: characterSize,
                        showBubble: false,
                        showBackdrop: false,
                        showStatusBadge: false,
                      ),
                    ),
                  ),
                  if (showGreeting)
                    Positioned(
                      top: compact ? 0 : 14,
                      right: compact ? 4 : 22,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(18),
                            topRight: Radius.circular(18),
                            bottomRight: Radius.circular(18),
                            bottomLeft: Radius.circular(4),
                          ),
                          border: Border.all(color: palette.border),
                          boxShadow: [
                            BoxShadow(
                              color: palette.text.withValues(alpha: 0.04),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Text(
                          'Hello, friend.',
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 24),
          Text(
            'Good friends.\nClear tabs.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.text,
              fontSize: 36,
              height: 1.15,
              letterSpacing: -1,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'A little less awkward. A little more together.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.secondaryText,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}
