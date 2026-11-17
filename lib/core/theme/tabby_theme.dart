import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tabby_colors.dart';
import 'tabby_palette.dart';

/// Shared warm Material theme, including all native controls and overlays.
class TabbyTheme {
  TabbyTheme._();
  static const kpiCardRadius = 20.0;
  static const iconSquircleRadius = 12.0;
  static const pillBadgeRadius = 16.0;
  static const containerRadius = 24.0;
  static const sheetRadius = 28.0;
  static ThemeData get lightTheme => _build(Brightness.light);
  static ThemeData get darkTheme => _build(Brightness.dark);
  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final p = dark ? TabbyPalette.dark : TabbyPalette.light;
    const amber = TabbyColors.brandAmber;
    const ink = TabbyColors.brandInk;
    final scheme =
        ColorScheme.fromSeed(seedColor: amber, brightness: brightness).copyWith(
          primary: amber,
          onPrimary: ink,
          secondary: p.link,
          onSecondary: dark ? ink : Colors.white,
          primaryContainer: p.soft,
          onPrimaryContainer: p.text,
          secondaryContainer: p.accentTint,
          onSecondaryContainer: p.text,
          tertiary: p.warningText,
          onTertiary: dark ? ink : Colors.white,
          tertiaryContainer: p.pendingTint,
          onTertiaryContainer: p.warningText,
          surface: p.surface,
          onSurface: p.text,
          onSurfaceVariant: p.secondaryText,
          surfaceContainerLowest: p.canvas,
          surfaceContainerLow: p.canvas,
          surfaceContainer: p.surface,
          surfaceContainerHigh: p.soft,
          surfaceContainerHighest: p.soft,
          outline: p.controlBorder,
          outlineVariant: p.border,
          error: p.errorText,
          onError: dark ? const Color(0xFF601410) : Colors.white,
          errorContainer: p.errorTint,
          onErrorContainer: p.errorText,
          inverseSurface: p.text,
          onInverseSurface: p.canvas,
          inversePrimary: dark ? TabbyColors.accentBurnt : amber,
          surfaceTint: Colors.transparent,
        );
    final rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: color, width: width),
        );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: 'Inter',
    );
    return base.copyWith(
      scaffoldBackgroundColor: p.canvas,
      canvasColor: p.surface,
      cardColor: p.surface,
      dividerColor: p.border,
      hintColor: p.secondaryText,
      textTheme: base.textTheme.apply(bodyColor: p.text, displayColor: p.text),
      primaryTextTheme: base.primaryTextTheme.apply(
        bodyColor: ink,
        displayColor: ink,
      ),
      iconTheme: IconThemeData(color: p.text),
      listTileTheme: ListTileThemeData(
        textColor: p.text,
        iconColor: p.secondaryText,
        selectedColor: p.link,
        selectedTileColor: p.soft,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.canvas,
        foregroundColor: p.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          color: p.text,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          fontFamily: 'Inter',
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(containerRadius),
          side: BorderSide(color: p.border),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        modalBackgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: p.controlBorder,
        constraints: const BoxConstraints(minWidth: double.infinity),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(sheetRadius),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          color: p.text,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: TextStyle(
          fontFamily: 'Inter',
          color: p.secondaryText,
          fontSize: 16,
          height: 1.5,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(containerRadius),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(fontFamily: 'Inter', color: p.text),
        shape: rounded,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: amber,
          foregroundColor: ink,
          elevation: 0,
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: rounded,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            fontFamily: 'Inter',
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: amber,
          foregroundColor: ink,
          minimumSize: const Size(48, 52),
          shape: rounded,
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.text,
          side: BorderSide(color: p.controlBorder),
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: rounded,
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.link,
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.soft,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: inputBorder(p.controlBorder),
        enabledBorder: inputBorder(p.controlBorder),
        focusedBorder: inputBorder(p.link, 2),
        errorBorder: inputBorder(p.errorText),
        focusedErrorBorder: inputBorder(p.errorText, 2),
        hintStyle: TextStyle(
          fontFamily: 'Inter',
          color: p.mutedText,
          fontSize: 14,
        ),
        labelStyle: TextStyle(fontFamily: 'Inter', color: p.secondaryText),
        floatingLabelStyle: TextStyle(fontFamily: 'Inter', color: p.link),
        prefixIconColor: p.secondaryText,
        suffixIconColor: p.secondaryText,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.soft,
        selectedColor: amber,
        checkmarkColor: ink,
        side: BorderSide(color: p.controlBorder),
        shape: rounded,
        labelStyle: WidgetStateTextStyle.resolveWith(
          (s) => TextStyle(
            fontFamily: 'Inter',
            color: s.contains(WidgetState.selected) ? ink : p.text,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      checkboxTheme: CheckboxThemeData(
        checkColor: const WidgetStatePropertyAll(ink),
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? amber : Colors.transparent,
        ),
        side: BorderSide(color: p.controlBorder, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      radioTheme: RadioThemeData(fillColor: WidgetStatePropertyAll(p.link)),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? ink : p.controlBorder,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? amber : p.soft,
        ),
        trackOutlineColor: WidgetStatePropertyAll(p.controlBorder),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.link,
        thumbColor: p.link,
        inactiveTrackColor: p.border,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.link,
        linearTrackColor: p.soft,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.text,
        unselectedLabelColor: p.secondaryText,
        indicatorColor: p.link,
        dividerColor: p.border,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: p.dock,
        selectedItemColor: p.link,
        unselectedItemColor: p.secondaryText,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.dock,
        indicatorColor: amber,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? ink : p.secondaryText,
          ),
        ),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontFamily: 'Inter',
            color: p.text,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: p.canvas,
        indicatorColor: amber,
        selectedIconTheme: const IconThemeData(color: ink),
        unselectedIconTheme: IconThemeData(color: p.secondaryText),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: amber,
        foregroundColor: ink,
        elevation: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.text,
        contentTextStyle: TextStyle(fontFamily: 'Inter', color: p.canvas),
        actionTextColor: dark ? TabbyColors.accentBurnt : amber,
        behavior: SnackBarBehavior.fixed,
        shape: rounded,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.link,
        selectionColor: amber.withValues(alpha: 0.35),
        selectionHandleColor: p.link,
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: p.soft,
        headerForegroundColor: p.text,
        todayForegroundColor: WidgetStatePropertyAll(p.link),
        todayBorder: BorderSide(color: p.controlBorder),
        yearForegroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? ink : p.text,
        ),
        dayForegroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? ink : null,
        ),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: p.surface,
        dialBackgroundColor: p.soft,
        dialHandColor: amber,
        hourMinuteColor: p.soft,
        hourMinuteTextColor: p.text,
      ),
    );
  }
}
