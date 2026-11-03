/// Design tokens: the one place colours, type and spacing are decided.
///
/// Charcoal and muted gold, like a real regimental visitors book - not a
/// generic dark theme. Nothing outside this file should hardcode a colour.
library;

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const background = Color(0xFF14120F);
  static const surface = Color(0xFF201C18);
  static const gold = Color(0xFFC8A35C);
  static const paper = Color(0xFFF4ECD8);
  static const ink = Color(0xFF201D19);
  static const textPrimary = Color(0xFFEDE7DD);
  static const textMuted = Color(0xFFA69E92);
  static const error = Color(0xFFCF6679);
}

/// 8/16/24/32 - every gap and padding in the app comes from this scale.
class AppSpacing {
  AppSpacing._();

  static const xs = 8.0;
  static const sm = 16.0;
  static const md = 24.0;
  static const lg = 32.0;
}

class AppRadii {
  AppRadii._();

  static const pad = 12.0;
  static const card = 12.0;
}

/// Small-caps-style field labels: muted, spaced out, never shouting.
TextStyle labelStyle(BuildContext context) => Theme.of(context)
    .textTheme
    .labelMedium!
    .copyWith(
      color: AppColors.textMuted,
      letterSpacing: 1.5,
      fontWeight: FontWeight.w600,
    );

ThemeData buildAppTheme() {
  final base = ThemeData(
    colorScheme: const ColorScheme.dark(
      primary: AppColors.gold,
      onPrimary: AppColors.ink,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.error,
    ),
    scaffoldBackgroundColor: AppColors.background,
    useMaterial3: true,
    fontFamily: 'PlayfairDisplay',
  );

  return base.copyWith(
    textTheme: base.textTheme
        .apply(
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        )
        .copyWith(
          // headings: serif, the book's voice
          headlineMedium: base.textTheme.headlineMedium?.copyWith(
            fontFamily: 'PlayfairDisplay',
            color: AppColors.gold,
            letterSpacing: 1,
          ),
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontFamily: 'PlayfairDisplay',
            color: AppColors.textPrimary,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontFamily: 'PlayfairDisplay',
            color: AppColors.textPrimary,
          ),
          // body and labels: clean sans, stays out of the way
          bodyMedium: base.textTheme.bodyMedium?.copyWith(
            fontFamily: 'Roboto',
            color: AppColors.textPrimary,
          ),
          bodySmall: base.textTheme.bodySmall?.copyWith(
            fontFamily: 'Roboto',
            color: AppColors.textMuted,
          ),
          labelMedium: base.textTheme.labelMedium?.copyWith(
            fontFamily: 'Roboto',
            color: AppColors.textMuted,
          ),
          labelLarge: base.textTheme.labelLarge?.copyWith(
            fontFamily: 'Roboto',
            color: AppColors.textMuted,
            letterSpacing: 1.5,
          ),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      foregroundColor: AppColors.textPrimary,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadii.card)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.ink,
        disabledBackgroundColor: AppColors.gold.withValues(alpha: 0.3),
        disabledForegroundColor: AppColors.ink.withValues(alpha: 0.6),
        textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
    ),
    iconTheme: const IconThemeData(color: AppColors.textMuted),
    dividerTheme: const DividerThemeData(color: Color(0xFF332D26)),
  );
}
