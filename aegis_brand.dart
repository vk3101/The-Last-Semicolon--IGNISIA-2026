import 'package:flutter/material.dart';

class AegisBrand {
  static const String appName = 'AEGIS AI';
  static const String appSubtitle = 'Clinical Intelligence Command Center';

  static const Color midnight = Color(0xFFF7FBFF);
  static const Color midnightSoft = Color(0xFFEAF3FF);
  static const Color panel = Color(0xFFFFFFFF);
  static const Color panelElevated = Color(0xFFF1F7FF);
  static const Color stroke = Color(0xFFA9C2DC);
  static const Color primary = Color(0xFF2D71CF);
  static const Color secondary = Color(0xFF6D9FE3);
  static const Color tertiary = Color(0xFF9ABAE8);
  static const Color danger = Color(0xFFE36B72);
  static const Color textPrimary = Color(0xFF193653);
  static const Color textSecondary = Color(0xFF5B7793);
  static const Color textMuted = Color(0xFF8196AB);

  static const Color cardInk = Color(0xFF153657);
  static const Color cardInkElevated = Color(0xFF1B446B);
  static const Color cardStroke = Color(0xFF356692);

  static ThemeData theme() {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.light);
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: Brightness.light,
        ).copyWith(
          primary: primary,
          secondary: secondary,
          tertiary: tertiary,
          error: danger,
          surface: panel,
          onSurface: textPrimary,
          outline: stroke,
          surfaceContainerHighest: panelElevated,
        );

    final textTheme = base.textTheme
        .apply(
          fontFamily: 'Avenir Next',
          bodyColor: textPrimary,
          displayColor: textPrimary,
        )
        .copyWith(
          displayLarge: base.textTheme.displayLarge?.copyWith(
            fontFamily: 'Avenir Next',
            fontWeight: FontWeight.w700,
            letterSpacing: -1.5,
            height: 0.96,
            color: textPrimary,
          ),
          displayMedium: base.textTheme.displayMedium?.copyWith(
            fontFamily: 'Avenir Next',
            fontWeight: FontWeight.w700,
            letterSpacing: -1.2,
            height: 0.98,
            color: textPrimary,
          ),
          headlineLarge: base.textTheme.headlineLarge?.copyWith(
            fontFamily: 'Avenir Next',
            fontWeight: FontWeight.w700,
            letterSpacing: -0.9,
            color: textPrimary,
          ),
          headlineMedium: base.textTheme.headlineMedium?.copyWith(
            fontFamily: 'Avenir Next',
            fontWeight: FontWeight.w700,
            letterSpacing: -0.7,
            color: textPrimary,
          ),
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontFamily: 'Avenir Next',
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: textPrimary,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontFamily: 'Avenir Next',
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: textPrimary,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontFamily: 'Avenir Next',
            fontWeight: FontWeight.w600,
            color: textSecondary,
          ),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(
            fontFamily: 'Avenir Next',
            height: 1.55,
            color: textSecondary,
          ),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(
            fontFamily: 'Avenir Next',
            height: 1.5,
            color: textSecondary,
          ),
          labelLarge: base.textTheme.labelLarge?.copyWith(
            fontFamily: 'Avenir Next',
            fontWeight: FontWeight.w700,
            letterSpacing: 0.25,
          ),
        );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: midnight,
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide.none,
        backgroundColor: panelElevated,
        selectedColor: primary.withValues(alpha: 0.18),
        labelStyle: const TextStyle(
          fontFamily: 'Avenir Next',
          color: textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: tertiary.withValues(alpha: 0.32),
          disabledForegroundColor: textMuted,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Avenir Next',
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: primary,
          disabledBackgroundColor: panelElevated,
          disabledForegroundColor: textMuted,
          side: BorderSide(color: primary.withValues(alpha: 0.40)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Avenir Next',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          disabledForegroundColor: textMuted,
          textStyle: const TextStyle(
            fontFamily: 'Avenir Next',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        labelStyle: const TextStyle(
          fontFamily: 'Avenir Next',
          color: textSecondary,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: const TextStyle(fontFamily: 'Avenir Next', color: textMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: stroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: primary, width: 1.4),
        ),
      ),
      dividerColor: stroke,
      snackBarTheme: SnackBarThemeData(
        backgroundColor: cardInk,
        contentTextStyle: const TextStyle(
          fontFamily: 'Avenir Next',
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}
