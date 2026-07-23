/// De-Duke ThemeData -- assembles the branding.md tokens into Flutter's
/// Material 3 theme system, for both light and dark mode.
///
/// Every branding.md token that has a natural Material 3 `ColorScheme` role
/// is mapped onto that role here, not left as a bare `AppColors` constant --
/// screens should read `Theme.of(context).colorScheme.X` /
/// `Theme.of(context).textTheme.X` / `Theme.of(context).cardTheme`, never
/// `AppColors.X` directly followed by a manual
/// `Theme.of(context).brightness == Brightness.dark` branch. That per-widget
/// branching pattern is exactly what this refactor replaces: previously
/// `AppTheme` only set `colorScheme: ColorScheme.fromSeed(...)`, which
/// derives most roles algorithmically from a single seed color rather than
/// branding.md's actual tokens -- so screens reached for `AppColors.surface`/
/// `.border`/`.textSecondary` directly instead, and every one of them had to
/// remember to branch on brightness itself. Several didn't (the dark-mode
/// bug this refactor fixes).
///
/// `ColorScheme` role mapping (light; dark mirrors it with the `*Dark`
/// tokens):
///   primary            -> AppColors.primary       onPrimary   -> white
///   primaryContainer    -> AppColors.primaryLight  onPrimaryContainer -> AppColors.primary
///   tertiary            -> AppColors.accent        onTertiary  -> white
///   tertiaryContainer   -> AppColors.accentLight   onTertiaryContainer -> AppColors.accent
///   error               -> AppColors.error         onError     -> white
///   surface             -> AppColors.surface       onSurface   -> AppColors.textPrimary
///   surfaceContainerHighest -> AppColors.surfaceSecondary  onSurfaceVariant -> AppColors.textSecondary
///   outline             -> AppColors.border (full strength -- dividers/borders)
///   outlineVariant      -> AppColors.border at reduced opacity (the
///                          "hairline at 60%" treatment branding.md calls for
///                          on every card)
///
/// Only tokens with no `ColorScheme` equivalent (success/warning/info/
/// verified, and the two-layer shadow system) live on the `AppSemanticColors`
/// `ThemeExtension` instead (app_semantic_colors.dart) -- registered below
/// via `ThemeData.extensions`.
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_semantic_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.primaryLight,
      onPrimaryContainer: AppColors.primary,
      secondary: AppColors.primary,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.primaryLight,
      onSecondaryContainer: AppColors.primary,
      tertiary: AppColors.accent,
      onTertiary: Colors.white,
      tertiaryContainer: AppColors.accentLight,
      onTertiaryContainer: AppColors.accent,
      error: AppColors.error,
      onError: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.surfaceSecondary,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.border,
      outlineVariant: AppColors.border,
      shadow: Colors.black,
      // Bug fix: left unspecified, so Flutter's `ColorScheme` constructor
      // filled these with its own fixed defaults instead of anything
      // derived from this theme's actual dark palette -- Material 3's
      // default `SnackBar` reads `inverseSurface`/`onInverseSurface`
      // specifically, so every SnackBar in the app rendered with those
      // un-themed defaults regardless of light/dark mode. Light theme's
      // "inverse" surface is simply this app's own dark palette (and vice
      // versa in dark() below) -- not a separate token set.
      inverseSurface: AppColors.surfaceDark,
      onInverseSurface: AppColors.textPrimaryDark,
      inversePrimary: AppColors.primaryDark,
      surfaceTint: Colors.transparent,
    );

    return _buildTheme(
      colorScheme: colorScheme,
      semanticColors: AppSemanticColors.light,
      textColor: AppColors.textPrimary,
      inputFill: AppColors.surfaceSecondary,
    );
  }

  static ThemeData dark() {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.primaryDark,
      onPrimary: Colors.white,
      primaryContainer: AppColors.primaryLightDark,
      onPrimaryContainer: AppColors.primaryDark,
      secondary: AppColors.primaryDark,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.primaryLightDark,
      onSecondaryContainer: AppColors.primaryDark,
      tertiary: AppColors.accent,
      onTertiary: Colors.white,
      tertiaryContainer: AppColors.accentLight,
      onTertiaryContainer: AppColors.accent,
      error: AppColors.error,
      onError: Colors.white,
      surface: AppColors.surfaceDark,
      onSurface: AppColors.textPrimaryDark,
      surfaceContainerHighest: AppColors.surfaceSecondaryDark,
      onSurfaceVariant: AppColors.textSecondaryDark,
      outline: AppColors.borderDark,
      outlineVariant: AppColors.borderDark,
      shadow: Colors.black,
      // See light()'s matching comment -- dark theme's "inverse" is this
      // app's own light palette.
      inverseSurface: AppColors.surface,
      onInverseSurface: AppColors.textPrimary,
      inversePrimary: AppColors.primary,
      surfaceTint: Colors.transparent,
    );

    return _buildTheme(
      colorScheme: colorScheme,
      semanticColors: AppSemanticColors.dark,
      textColor: AppColors.textPrimaryDark,
      inputFill: AppColors.surfaceSecondaryDark,
    );
  }

  /// Shared theme assembly -- everything below derives from `colorScheme`
  /// (never a bare `AppColors.X`), so light/dark truly are just two
  /// different `ColorScheme`s feeding one shape, rather than two
  /// hand-duplicated theme trees that can drift apart.
  static ThemeData _buildTheme({
    required ColorScheme colorScheme,
    required AppSemanticColors semanticColors,
    required Color textColor,
    required Color inputFill,
  }) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      textTheme: _textTheme(textColor),
      extensions: [semanticColors],
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.6)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: const Size.fromHeight(AppSizing.buttonHeight),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md)),
        ),
      ),
      // Shares the elevated button's height/radius exactly, but keeps the
      // outline button's lighter, "secondary action" feel via a faint
      // primary-tinted fill instead of a solid one, plus a visible border.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: colorScheme.primary.withValues(alpha: 0.08),
          foregroundColor: colorScheme.primary,
          disabledForegroundColor:
              colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          minimumSize: const Size.fromHeight(AppSizing.buttonHeight),
          side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
      ),
      // Explicit rather than left to Material 3's default (which reads
      // colorScheme.inverseSurface/onInverseSurface itself) -- stated here
      // for clarity now that those two roles are themed correctly above,
      // and so this stays correct even if a future ColorScheme role
      // default ever changes upstream.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle:
            AppTypography.body.copyWith(color: colorScheme.onInverseSurface),
        actionTextColor: colorScheme.inversePrimary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md)),
      ),
    );
  }

  static TextTheme _textTheme(Color color) {
    return TextTheme(
      displayLarge: AppTypography.display.copyWith(color: color),
      headlineLarge: AppTypography.h1.copyWith(color: color),
      headlineMedium: AppTypography.h2.copyWith(color: color),
      headlineSmall: AppTypography.h3.copyWith(color: color),
      bodyLarge: AppTypography.bodyLarge.copyWith(color: color),
      bodyMedium: AppTypography.body.copyWith(color: color),
      bodySmall: AppTypography.bodySmall.copyWith(color: color),
      labelSmall: AppTypography.caption.copyWith(color: color),
    );
  }
}
