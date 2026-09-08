import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFFF7F8FA);
  static const primary = Color(0xFF0F766E);
  static const primaryDark = Color(0xFF115E59);
  static const primaryContainer = Color(0xFFCCFBF1);
  static const danger = Color(0xFFDC2626);
  static const dangerLight = Color(0xFFFEE2E2);
  static const success = Color(0xFF16A34A);
  static const successLight = Color(0xFFDCFCE7);
  static const info = Color(0xFF2563EB);
  static const infoLight = Color(0xFFDBEAFE);
  static const warning = Color(0xFFB45309);
  static const warningLight = Color(0xFFFEF3C7);
  static const gold = warning;
  static const textPrimary = Color(0xFF1F2937);
  static const textSecondary = Color(0xFF6B7280);
  static const border = Color(0xFFE5E7EB);
  static const cardShadow = Color(0x14000000);
}

/// مقاييس المسافات الموحّدة.
class AppSpacing {
  static const lg = 16.0;
  static const xl = 24.0;
}

/// أنصاف أقطار الانحناء الموحّدة.
class AppRadius {
  static const md = 14.0;
}

/// أنماط النصوص الموحّدة (دور النص، وليس جهازاً بصرياً).
class AppTextStyles {
  static const screenTitle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );
  static const listTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static const body = TextStyle(fontSize: 13, color: AppColors.textPrimary);
  static const bodyMedium = TextStyle(
    fontSize: 13,
    color: AppColors.textSecondary,
  );
  static const small = TextStyle(fontSize: 12, color: AppColors.textSecondary);
  static const caption = TextStyle(
    fontSize: 11,
    color: AppColors.textSecondary,
  );
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: AppColors.background,
      fontFamilyFallback: const [
        'Noto Naskh Arabic',
        'Cairo',
        'Tajawal',
        'Segoe UI',
      ],
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        foregroundColor: AppColors.textPrimary,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
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
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textPrimary,
      ),
    );
  }
}

class CardShadow {
  static List<BoxShadow> soft() => [
    BoxShadow(
      color: AppColors.cardShadow,
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
}
