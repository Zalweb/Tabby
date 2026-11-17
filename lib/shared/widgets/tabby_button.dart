import 'package:flutter/material.dart';

import '../../core/theme/tabby_colors.dart';
import '../../core/theme/tabby_palette.dart';

enum TabbyButtonVariant {
  neutral,
  primary, // Amber fill with charcoal text
  secondary, // Warm theme-aware highlight
  outline, // Outlined border
  danger, // Alert Red
}

class TabbyButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final TabbyButtonVariant variant;
  final Widget? icon;
  final bool isLoading;
  final bool isFullWidth;
  final double height;

  const TabbyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = TabbyButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.isFullWidth = true,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color foregroundColor;
    BorderSide borderSide = BorderSide.none;

    switch (variant) {
      case TabbyButtonVariant.neutral:
        backgroundColor = TabbyPalette.of(context).surface;
        foregroundColor = TabbyPalette.of(context).text;
        borderSide = BorderSide(color: TabbyPalette.of(context).border);
        break;
      case TabbyButtonVariant.primary:
        backgroundColor = TabbyColors.brandAmber;
        foregroundColor = TabbyColors.brandInk;
        break;
      case TabbyButtonVariant.secondary:
        backgroundColor = TabbyPalette.of(context).soft;
        foregroundColor = TabbyPalette.of(context).text;
        break;
      case TabbyButtonVariant.outline:
        backgroundColor = TabbyPalette.of(context).surface;
        foregroundColor = TabbyPalette.of(context).link;
        borderSide = BorderSide(
          color: TabbyPalette.of(context).controlBorder,
          width: 1.5,
        );
        break;
      case TabbyButtonVariant.danger:
        backgroundColor = const Color(0xFFB3261E);
        foregroundColor = TabbyColors.surfaceWhite;
        break;
    }

    final suppliedIcon = icon;
    final effectiveIcon = suppliedIcon is Icon
        ? Icon(
            suppliedIcon.icon,
            size: suppliedIcon.size,
            color: foregroundColor,
            semanticLabel: suppliedIcon.semanticLabel,
            textDirection: suppliedIcon.textDirection,
            applyTextScaling: suppliedIcon.applyTextScaling,
            shadows: suppliedIcon.shadows,
            fill: suppliedIcon.fill,
            weight: suppliedIcon.weight,
            grade: suppliedIcon.grade,
            opticalSize: suppliedIcon.opticalSize,
          )
        : suppliedIcon;
    final buttonContent = Row(
      mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
            ),
          )
        else ...[
          if (icon != null) ...[effectiveIcon!, const SizedBox(width: 8)],
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: foregroundColor,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                fontFamily: 'Inter',
              ),
              textAlign: TextAlign.center,
              softWrap: true,
            ),
          ),
        ],
      ],
    );

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: SizedBox(
        width: isFullWidth ? double.infinity : null,
        child: ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: borderSide,
            ),
            minimumSize: Size(0, height),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          child: buttonContent,
        ),
      ),
    );
  }
}
