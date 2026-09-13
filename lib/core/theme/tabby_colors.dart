import 'package:flutter/material.dart';

/// Tabby Brand Design Tokens derived from Figma FinWise Reference (Node 7020:3430)
class TabbyColors {
  TabbyColors._();

  // FinWise Primary Emerald & Forest Teal Palette
  static const Color brandEmerald     = Color(0xFF00D09E); // FinWise Primary Vibrant Emerald Green
  static const Color brandDarkTeal    = Color(0xFF093030); // FinWise Deep Dark Teal / Charcoal
  static const Color brandDeepForest  = Color(0xFF052224); // FinWise Deep Forest Accent
  static const Color brandMintAccent  = Color(0xFFDFF7E2); // FinWise Soft Mint Card / Input Fill
  static const Color bgCanvas         = Color(0xFFF1FFF3); // FinWise Light Mint App Canvas Background
  static const Color surfaceWhite     = Color(0xFFFFFFFF); // Pure Card & Modal Surface
  static const Color borderMint       = Color(0xFFD6EFE0); // FinWise Subtle Mint Border
  static const Color borderGray       = Color(0xFFE2E8F0); // Neutral Subtle Border

  // Secondary Accents & Indicators
  static const Color accentBlue       = Color(0xFF0068FF); // FinWise Expense Blue / Primary KPI Blue
  static const Color accentLightBlue  = Color(0xFF3299FF); // FinWise Icon Squircle / Secondary Blue
  static const Color iconBgBlue       = Color(0xFFE9F6FE); // Soft Blue Icon Circle Fill
  static const Color iconBgMint       = Color(0xFFDFF7E2); // Soft Mint Icon Circle Fill
  static const Color darkProgressPill = Color(0xFF093030); // FinWise Dark Capsule Progress Indicator

  // Text Hierarchy
  static const Color textPrimary      = Color(0xFF093030); // High Contrast Dark Teal Text
  static const Color textSecondary    = Color(0xFF4B6969); // Muted Teal Subtitles & Captions
  static const Color textMuted        = Color(0xFF6C757D); // Placeholder & Tertiary Text
  static const Color textLight        = Color(0xFFFFFFFF); // White On Emerald

  // Status & Financial Indicators
  static const Color successGreen     = Color(0xFF00D09E); // Confirmed settled / positive
  static const Color successLight     = Color(0xFFDFF7E2); // Soft success background
  static const Color debtRed          = Color(0xFF0068FF); // Primary expense blue (or red for critical)
  static const Color alertRed         = Color(0xFFEF4444); // Critical alerts / Overdue commitment
  static const Color debtLight        = Color(0xFFE9F6FE); // Soft expense highlight background
  static const Color pendingAmber     = Color(0xFFF59E0B); // Awaiting acknowledgment
  static const Color pendingLight     = Color(0xFFFEF3C7); // Soft pending background
  static const Color chipBackground   = Color(0xFFDFF7E2); // FinWise Mint Chip Container

  // Backward-Compatible Aliases for Existing Widget References
  static const Color primaryCharcoal = brandDarkTeal;
  static const Color accentAmber      = brandEmerald;
  static const Color accentAmberDark  = Color(0xFF00A87E);
  static const Color backgroundLight  = bgCanvas;
  static const Color secondaryMuted   = textSecondary;
}
