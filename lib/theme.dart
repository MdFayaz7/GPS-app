import 'package:flutter/material.dart';

/// Practo-inspired palette: bright cyan actions, deep navy text, soft grey canvas.
class AppColors {
  AppColors._();
  static const primary = Color(0xFF14BEF0);
  static const navy = Color(0xFF28328C);
  static const bg = Color(0xFFF0F0F5);
  static const text = Color(0xFF414146);
  static const muted = Color(0xFF787887);
  static const border = Color(0xFFE3E3EA);
  static const green = Color(0xFF1AAA55);
  static const cardOverlay = Color(0xE628328C); // navy @ 90%
}

ThemeData buildTheme() {
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(6));
  OutlineInputBorder border(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: c),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.navy,
      surface: Colors.white,
    ),
    scaffoldBackgroundColor: AppColors.bg,
    textTheme: Typography.blackMountainView
        .apply(bodyColor: AppColors.text, displayColor: AppColors.navy),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.navy,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
          color: AppColors.navy, fontSize: 18, fontWeight: FontWeight.w700),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        shape: shape,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.navy,
        side: const BorderSide(color: AppColors.border),
        minimumSize: const Size(0, 48),
        shape: shape,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.primary),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: border(AppColors.border),
      enabledBorder: border(AppColors.border),
      focusedBorder: border(AppColors.primary),
      labelStyle: const TextStyle(color: AppColors.muted),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : null),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.primary : null),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.navy,
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
  );
}
