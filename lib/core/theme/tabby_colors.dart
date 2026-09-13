import 'package:flutter/material.dart';

/// Tabby Brand Design Tokens from AGENTS.md Section 4
class TabbyColors {
  TabbyColors._();

  // Brand Canvas
  static const Color primaryCharcoal = Color(0xFF1F1F1F);
  static const Color accentAmber      = Color(0xFFFFB74D);
  static const Color accentAmberDark  = Color(0xFFF59E0B);
  static const Color backgroundLight  = Color(0xFFF8F8F8);
  static const Color secondaryMuted   = Color(0xFF9CA3AF);
  static const Color surfaceWhite     = Color(0xFFFFFFFF);
  static const Color borderGray       = Color(0xFFE5E7EB);
  static const Color textMuted        = Color(0xFF6B7280);

  // Status & Financial Indicators
  static const Color successGreen     = Color(0xFF10B981); // Confirmed settled ("Bayad na!")
  static const Color successLight     = Color(0xFFD1FAE5); // Soft success background
  static const Color debtRed          = Color(0xFFEF4444); // Active debt owed / alerts
  static const Color debtLight        = Color(0xFFFEE2E2); // Soft debt background
  static const Color pendingAmber     = Color(0xFFF59E0B); // Awaiting acknowledgment
  static const Color pendingLight     = Color(0xFFFEF3C7); // Soft pending background
  static const Color chipBackground   = Color(0xFFF3F4F6); // Neutral chip container
}
