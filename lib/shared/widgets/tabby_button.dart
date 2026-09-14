import 'package:flutter/material.dart';
import '../../core/theme/tabby_colors.dart';

enum TabbyButtonVariant {
  primary,   // FinWise Emerald #00D09E
  secondary, // FinWise Soft Mint #DFF7E2 or Dark Teal
  outline,   // Outlined border
  danger,    // Alert Red
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
      case TabbyButtonVariant.primary:
        backgroundColor = TabbyColors.brandEmerald;
        foregroundColor = TabbyColors.surfaceWhite;
        break;
      case TabbyButtonVariant.secondary:
        backgroundColor = TabbyColors.brandMintAccent;
        foregroundColor = TabbyColors.brandDarkTeal;
        break;
      case TabbyButtonVariant.outline:
        backgroundColor = TabbyColors.surfaceWhite;
        foregroundColor = TabbyColors.brandEmerald;
        borderSide = const BorderSide(color: TabbyColors.brandEmerald, width: 1.5);
        break;
      case TabbyButtonVariant.danger:
        backgroundColor = TabbyColors.alertRed;
        foregroundColor = TabbyColors.surfaceWhite;
        break;
    }

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
          if (icon != null) ...[
            icon!,
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: foregroundColor,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                fontFamily: 'Inter',
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ],
    );

    return SizedBox(
      height: height,
      width: isFullWidth ? double.infinity : null,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: borderSide,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: buttonContent,
      ),
    );
  }
}
