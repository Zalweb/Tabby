import 'package:flutter/material.dart';

import 'tabby_colors.dart';

/// One warm semantic palette for welcome, ledger, forms and overlays.
/// Provider logos, QR pixels, receipts and avatars retain their actual colors.
class TabbyPalette {
  const TabbyPalette._({
    required this.canvas,
    required this.surface,
    required this.soft,
    required this.border,
    required this.text,
    required this.secondaryText,
    required this.mutedText,
    required this.accentTint,
    required this.pendingTint,
    required this.link,
    required this.errorText,
    required this.warningText,
    required this.positiveText,
    required this.successTint,
    required this.errorTint,
    required this.dock,
    required this.controlBorder,
  });
  final Color canvas, surface, soft, border, text, secondaryText, mutedText;
  final Color accentTint,
      pendingTint,
      link,
      errorText,
      warningText,
      positiveText;
  final Color successTint, errorTint, dock, controlBorder;
  Color get action => TabbyColors.brandAmber;
  Color get onAction => TabbyColors.brandInk;
  Color get mint => soft;
  Color get blueTint => accentTint;
  static TabbyPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
  static const light = TabbyPalette._(
    canvas: TabbyColors.canvasCream,
    surface: TabbyColors.surfaceWhite,
    soft: TabbyColors.softCream,
    border: TabbyColors.borderWarm,
    text: TabbyColors.brandInk,
    secondaryText: TabbyColors.textSecondary,
    mutedText: TabbyColors.textMuted,
    accentTint: TabbyColors.debtLight,
    pendingTint: TabbyColors.pendingLight,
    link: TabbyColors.accentBurnt,
    errorText: TabbyColors.alertRed,
    warningText: Color(0xFF805000),
    positiveText: TabbyColors.successGreen,
    successTint: TabbyColors.successLight,
    errorTint: Color(0xFFFCEAE7),
    dock: TabbyColors.surfaceWhite,
    controlBorder: Color(0xFF8E7D6D),
  );
  static const dark = TabbyPalette._(
    canvas: Color(0xFF181A19),
    surface: Color(0xFF242625),
    soft: Color(0xFF33302A),
    border: Color(0xFF51493E),
    text: Color(0xFFFFF8ED),
    secondaryText: Color(0xFFC7C1B7),
    mutedText: Color(0xFFB5ADA2),
    accentTint: Color(0xFF49351D),
    pendingTint: Color(0xFF49351D),
    link: Color(0xFFFFC975),
    errorText: Color(0xFFFFB4AB),
    warningText: Color(0xFFFFD787),
    positiveText: Color(0xFF9FD6B6),
    successTint: Color(0xFF233B2D),
    errorTint: Color(0xFF4A2724),
    dock: Color(0xFF242625),
    controlBorder: Color(0xFFB5A38D),
  );
}
