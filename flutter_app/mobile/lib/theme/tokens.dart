import 'package:flutter/material.dart';

class AppColors {
  // Brand
  // Darkened to meet WCAG contrast requirements with white
  static const Color primaryBrand =
      Color(0xFF1565C0); // Strong Blue (accessible)
  static const Color primaryAction =
      Color(0xFF2E7D32); // Green 700 (accessible)
  static const Color secondaryAccent = Color(0xFF1F3C61); // Trust Navy
  static const Color warning = Color(0xFFFB8C00); // Orange - warnings

  // Backgrounds
  static const Color background = Color(0xFFFFFFFF);
  static const Color secondaryBackground = Color(0xFFF4F7FA);

  // Text
  static const Color textBody = Color(0xFF33475B); // Slate Gray
}

class AppTypography {
  static const String fontFamily = 'Roboto';

  static TextTheme textTheme = const TextTheme(
    bodyMedium: TextStyle(fontSize: 14.0, color: AppColors.textBody),
    titleLarge: TextStyle(
        fontSize: 18.0,
        fontWeight: FontWeight.bold,
        color: AppColors.secondaryAccent),
    titleMedium: TextStyle(
        fontSize: 16.0,
        fontWeight: FontWeight.w600,
        color: AppColors.secondaryAccent),
  );
}

ThemeData buildLightTheme() {
  final base = ThemeData.light();
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.primaryBrand,
      secondary: AppColors.secondaryAccent,
      background: AppColors.background,
      surface: AppColors.secondaryBackground,
      onPrimary: Colors.white,
      onBackground: AppColors.textBody,
      onSurface: Colors.black, // Text field text color
    ),
    scaffoldBackgroundColor: AppColors.background,
    textTheme: AppTypography.textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primaryBrand,
      foregroundColor: Colors.white,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryAction,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}
