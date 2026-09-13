import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'tabby_colors.dart';

/// Tabby Material 3 Theme Definition
class TabbyTheme {
  TabbyTheme._();

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: TabbyColors.backgroundLight,
      fontFamily: 'Inter',
      colorScheme: const ColorScheme.light(
        primary: TabbyColors.primaryCharcoal,
        secondary: TabbyColors.accentAmber,
        surface: TabbyColors.surfaceWhite,
        error: TabbyColors.debtRed,
        onPrimary: TabbyColors.surfaceWhite,
        onSecondary: TabbyColors.primaryCharcoal,
        onSurface: TabbyColors.primaryCharcoal,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: TabbyColors.surfaceWhite,
        foregroundColor: TabbyColors.primaryCharcoal,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          color: TabbyColors.primaryCharcoal,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          fontFamily: 'Inter',
        ),
      ),
      cardTheme: const CardTheme(
        color: TabbyColors.surfaceWhite,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: TabbyColors.borderGray, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: TabbyColors.primaryCharcoal,
          foregroundColor: TabbyColors.surfaceWhite,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: TabbyColors.primaryCharcoal,
          side: const BorderSide(color: TabbyColors.borderGray, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: TabbyColors.chipBackground,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: TabbyColors.primaryCharcoal,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.transparent),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: TabbyColors.surfaceWhite,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: TabbyColors.borderGray),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: TabbyColors.borderGray),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: TabbyColors.primaryCharcoal, width: 1.5),
        ),
        hintStyle: const TextStyle(
          color: TabbyColors.secondaryMuted,
          fontSize: 14,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: TabbyColors.surfaceWhite,
        selectedItemColor: TabbyColors.primaryCharcoal,
        unselectedItemColor: TabbyColors.secondaryMuted,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      dividerTheme: const DividerThemeData(
        color: TabbyColors.borderGray,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
