import '../../../shared/widgets/tabby_mascot_widget.dart';

import 'package:flutter/material.dart';

import '../../../core/theme/tabby_colors.dart';
import '../../../core/theme/tabby_palette.dart';

class WelcomeColors {
  static Color canvas(BuildContext context) => TabbyPalette.of(context).canvas;
  static Color ink(BuildContext context) => TabbyPalette.of(context).text;
  static Color muted(BuildContext context) =>
      TabbyPalette.of(context).secondaryText;
  static const amber = TabbyColors.brandAmber;
}

class WelcomeBackdrop extends StatelessWidget {
  const WelcomeBackdrop({super.key, required this.child, this.vibrant = false});
  final Widget child;
  final bool vibrant;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0, 0.55, 1],
        colors: [
          WelcomeColors.canvas(context),
          WelcomeColors.canvas(context),
          WelcomeColors.amber.withValues(alpha: vibrant ? 0.65 : 0.12),
        ],
      ),
    ),
    child: child,
  );
}

/// Generated art stays separate from all native text and buttons.
class WelcomeMascot extends StatelessWidget {
  const WelcomeMascot({
    super.key,
    this.asset = 'assets/branding/tabby-welcome-v3.png',
    this.size = 280,
    this.pose,
  });
  final String asset;
  final double size;
  final TabbyMascotPose? pose;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: TabbyMascotWidget.art(
      pose:
          pose ??
          (asset.contains('notebook')
              ? TabbyMascotPose.notebook
              : TabbyMascotPose.welcome),
      size: size,
    ),
  );
}
