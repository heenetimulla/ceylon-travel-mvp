import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';

class AppTheme {
  const AppTheme._();
  static ThemeData get lightTheme {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.ocean).copyWith(
      primary: AppColors.ocean,
      onPrimary: AppColors.surface,
      secondary: AppColors.gold,
      onSecondary: AppColors.charcoal,
      surface: AppColors.surface,
      onSurface: AppColors.charcoal,
      onSurfaceVariant: AppColors.secondary,
      error: AppColors.error,
      outline: AppColors.border,
      primaryContainer: AppColors.softBlue,
    );
    final button = FilledButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      shape: shape,
      textStyle: AppTextStyles.button,
      backgroundColor: AppColors.ocean,
      foregroundColor: AppColors.surface,
      disabledBackgroundColor: AppColors.border,
      disabledForegroundColor: AppColors.secondary,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.pageBackground,
      textTheme: const TextTheme(
        displaySmall: AppTextStyles.title,
        headlineMedium: AppTextStyles.title,
        headlineSmall: AppTextStyles.section,
        titleLarge: AppTextStyles.section,
        titleMedium: AppTextStyles.cardTitle,
        titleSmall: AppTextStyles.cardTitle,
        bodyLarge: AppTextStyles.body,
        bodyMedium: AppTextStyles.body,
        bodySmall: AppTextStyles.secondary,
        labelLarge: AppTextStyles.button,
        labelMedium: AppTextStyles.caption,
        labelSmall: AppTextStyles.status,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.ocean,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleSpacing: 20,
        toolbarHeight: 64,
        titleTextStyle: AppTextStyles.section,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        shadowColor: AppColors.cardShadow,
        margin: const EdgeInsets.only(bottom: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(style: button),
      elevatedButtonTheme: ElevatedButtonThemeData(style: button),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: shape,
          foregroundColor: AppColors.ocean,
          side: const BorderSide(color: AppColors.border),
          textStyle: AppTextStyles.button,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: shape,
          textStyle: AppTextStyles.button,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        labelStyle: AppTextStyles.secondary,
        hintStyle: AppTextStyles.secondary,
        helperStyle: AppTextStyles.caption,
        errorMaxLines: 3,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.ocean, width: 1.5),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.pearl,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: AppTextStyles.section,
        contentTextStyle: AppTextStyles.body,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.softBlue,
        selectedColor: AppColors.softBlue,
        labelStyle: AppTextStyles.button,
        side: BorderSide.none,
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        space: 28,
        thickness: 1,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        iconColor: AppColors.ocean,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.charcoal,
      ),
    );
  }
}
