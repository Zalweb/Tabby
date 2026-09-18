import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'tabby_colors.dart';

/// Tabby Material 3 Theme Definition aligned with Figma FinWise Reference (Node 7020:3430)
class TabbyTheme {
  TabbyTheme._();

  // Design Tokens extracted from Figma FinWise App UI Kit
  static const double kpiCardRadius = 20.0;
  static const double iconSquircleRadius = 12.0;
  static const double pillBadgeRadius = 24.0;
  static const double containerRadius = 24.0;
  static const double sheetRadius = 36.0;

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: TabbyColors.bgCanvas,
      fontFamily: 'Inter',
      colorScheme: const ColorScheme.light(
        primary: TabbyColors.brandEmerald,
        secondary: TabbyColors.brandDarkTeal,
        surface: TabbyColors.surfaceWhite,
        error: TabbyColors.alertRed,
        onPrimary: TabbyColors.surfaceWhite,
        onSecondary: TabbyColors.surfaceWhite,
        onSurface: TabbyColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: TabbyColors.brandEmerald,
        foregroundColor: TabbyColors.brandDarkTeal,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          color: TabbyColors.brandDarkTeal,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          fontFamily: 'Inter',
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: const CardThemeData(
        color: TabbyColors.surfaceWhite,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(kpiCardRadius)),
          side: BorderSide(color: TabbyColors.borderMint, width: 1),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: TabbyColors.surfaceWhite,
        modalBackgroundColor: TabbyColors.surfaceWhite,
        constraints: BoxConstraints(maxWidth: 430),
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(sheetRadius)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: TabbyColors.brandEmerald,
          foregroundColor: TabbyColors.surfaceWhite,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(pillBadgeRadius),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            fontFamily: 'Inter',
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: TabbyColors.brandDarkTeal,
          side: const BorderSide(color: TabbyColors.borderMint, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(pillBadgeRadius),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            fontFamily: 'Inter',
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: TabbyColors.brandMintAccent,
        labelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: TabbyColors.brandDarkTeal,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.transparent),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: TabbyColors.brandMintAccent,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide:
              const BorderSide(color: TabbyColors.brandEmerald, width: 1.5),
        ),
        hintStyle: const TextStyle(
          color: TabbyColors.textSecondary,
          fontSize: 14,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFFE8F8EE),
        selectedItemColor: TabbyColors.brandDarkTeal,
        unselectedItemColor: TabbyColors.textSecondary,
        selectedLabelStyle:
            TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        unselectedLabelStyle:
            TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      dividerTheme: const DividerThemeData(
        color: TabbyColors.borderMint,
        thickness: 1,
        space: 1,
      ),
    );
  }

  static ThemeData get darkTheme {
    return lightTheme.copyWith(
      scaffoldBackgroundColor: const Color(0xFF102D2A),
      colorScheme: const ColorScheme.dark(
        primary: TabbyColors.brandEmerald,
        secondary: TabbyColors.brandMintAccent,
        surface: Color(0xFF173B37),
        error: TabbyColors.alertRed,
        onPrimary: TabbyColors.brandDarkTeal,
        onSecondary: TabbyColors.brandDarkTeal,
        onSurface: Colors.white,
      ),
      appBarTheme: lightTheme.appBarTheme.copyWith(
        backgroundColor: const Color(0xFF102D2A),
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      cardTheme: lightTheme.cardTheme.copyWith(
        color: const Color(0xFF173B37),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(kpiCardRadius)),
          side: BorderSide(color: Color(0xFF2B5B54), width: 1),
        ),
      ),
      bottomNavigationBarTheme: lightTheme.bottomNavigationBarTheme.copyWith(
        backgroundColor: const Color(0xFF173B37),
        unselectedItemColor: Colors.white70,
      ),
    );
  }
}
