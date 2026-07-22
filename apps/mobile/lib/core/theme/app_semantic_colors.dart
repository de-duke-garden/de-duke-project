/// Tokens from branding.md that have no natural home on Flutter's Material 3
/// `ColorScheme` (success/warning/info/verified semantics, and the app's
/// two-layer shadow system) -- everything that DOES map onto a standard
/// `ColorScheme` role (surface, border/outline, primary, text-on-surface,
/// etc.) belongs in `AppTheme`'s `ColorScheme.light()`/`.dark()` instead, per
/// AGENTS.md: `Theme.of(context)` is the single source of truth for
/// brightness-resolved values, this extension only covers the genuine gaps.
///
/// Registered on both `AppTheme.light()`/`.dark()` via `ThemeData.extensions`
/// -- already resolved for the current brightness, so callers never branch
/// on `Theme.of(context).brightness` themselves:
///   `final semantic = Theme.of(context).extension<AppSemanticColors>()!;`
library;

import 'package:flutter/material.dart';

import 'app_colors.dart';

@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.warning,
    required this.info,
    required this.verified,
    required this.shadowXs,
    required this.shadowSm,
    required this.shadowMd,
    required this.shadowLg,
    required this.shadowXl,
  });

  final Color success;
  final Color warning;
  final Color info;
  final Color verified;

  // branding.md's two-layer elevation system -- already the correct
  // light/dark list for this ThemeData, so screens never call
  // AppShadows.of(...) + Theme.of(context).brightness themselves.
  final List<BoxShadow> shadowXs;
  final List<BoxShadow> shadowSm;
  final List<BoxShadow> shadowMd;
  final List<BoxShadow> shadowLg;
  final List<BoxShadow> shadowXl;

  static const light = AppSemanticColors(
    success: AppColors.success,
    warning: AppColors.warning,
    info: AppColors.info,
    verified: AppColors.verified,
    shadowXs: AppShadowValues.xs,
    shadowSm: AppShadowValues.sm,
    shadowMd: AppShadowValues.md,
    shadowLg: AppShadowValues.lg,
    shadowXl: AppShadowValues.xl,
  );

  // Semantic (success/warning/info) colors are deliberately NOT re-tuned
  // per branding.md -- only shadows and neutrals get dark-mode variants
  // there; `verified` reuses `primaryDark` so the badge still reads as
  // on-brand against a dark surface (mirrors branding.md's `verified`
  // reusing `primary` in light mode).
  static const dark = AppSemanticColors(
    success: AppColors.success,
    warning: AppColors.warning,
    info: AppColors.info,
    verified: AppColors.primaryDark,
    shadowXs: AppShadowValues.xsDark,
    shadowSm: AppShadowValues.smDark,
    shadowMd: AppShadowValues.mdDark,
    shadowLg: AppShadowValues.lgDark,
    shadowXl: AppShadowValues.xlDark,
  );

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? warning,
    Color? info,
    Color? verified,
    List<BoxShadow>? shadowXs,
    List<BoxShadow>? shadowSm,
    List<BoxShadow>? shadowMd,
    List<BoxShadow>? shadowLg,
    List<BoxShadow>? shadowXl,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      info: info ?? this.info,
      verified: verified ?? this.verified,
      shadowXs: shadowXs ?? this.shadowXs,
      shadowSm: shadowSm ?? this.shadowSm,
      shadowMd: shadowMd ?? this.shadowMd,
      shadowLg: shadowLg ?? this.shadowLg,
      shadowXl: shadowXl ?? this.shadowXl,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    // Never actually animated between (light/dark is a hard MaterialApp
    // theme swap, not an interpolated transition) -- snaps at the midpoint
    // like Flutter's own ColorScheme.lerp does for its non-interpolable
    // fields, rather than attempting to lerp BoxShadow lists of unequal
    // shape.
    if (other is! AppSemanticColors) return this;
    return t < 0.5 ? this : other;
  }
}

/// Raw shadow value lists -- moved here (from the old `AppShadows` static
/// class) so `AppSemanticColors.light`/`.dark` above can be `const`. The
/// values themselves are unchanged from branding.md; `AppShadows` (see
/// app_shadows.dart) now just re-exports these for any remaining call site
/// during migration, plus the deprecated `.of()` helper this refactor
/// replaces with the theme extension above.
class AppShadowValues {
  AppShadowValues._();

  static const List<BoxShadow> none = [];

  static const List<BoxShadow> xs = [
    BoxShadow(color: Color(0x0D12201C), offset: Offset(0, 1), blurRadius: 1),
    BoxShadow(color: Color(0x0A12201C), offset: Offset(0, 1), blurRadius: 2),
  ];

  static const List<BoxShadow> sm = [
    BoxShadow(color: Color(0x1212201C), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x0D12201C), offset: Offset(0, 4), blurRadius: 10),
  ];

  static const List<BoxShadow> md = [
    BoxShadow(color: Color(0x1412201C), offset: Offset(0, 2), blurRadius: 4),
    BoxShadow(color: Color(0x1412201C), offset: Offset(0, 8), blurRadius: 20),
  ];

  static const List<BoxShadow> lg = [
    BoxShadow(color: Color(0x1A12201C), offset: Offset(0, 4), blurRadius: 8),
    BoxShadow(
        color: Color(0x2412201C), offset: Offset(0, 16), blurRadius: 36),
  ];

  static const List<BoxShadow> xl = [
    BoxShadow(color: Color(0x1F12201C), offset: Offset(0, 8), blurRadius: 16),
    BoxShadow(
        color: Color(0x2912201C), offset: Offset(0, 24), blurRadius: 48),
  ];

  static const List<BoxShadow> xsDark = [
    BoxShadow(color: Color(0x59000000), offset: Offset(0, 1), blurRadius: 1),
    BoxShadow(color: Color(0x40000000), offset: Offset(0, 1), blurRadius: 2),
  ];

  static const List<BoxShadow> smDark = [
    BoxShadow(color: Color(0x73000000), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x4D000000), offset: Offset(0, 4), blurRadius: 10),
  ];

  static const List<BoxShadow> mdDark = [
    BoxShadow(color: Color(0x80000000), offset: Offset(0, 2), blurRadius: 4),
    BoxShadow(color: Color(0x66000000), offset: Offset(0, 8), blurRadius: 20),
  ];

  static const List<BoxShadow> lgDark = [
    BoxShadow(color: Color(0x8C000000), offset: Offset(0, 4), blurRadius: 8),
    BoxShadow(
        color: Color(0x8C000000), offset: Offset(0, 16), blurRadius: 36),
  ];

  static const List<BoxShadow> xlDark = [
    BoxShadow(color: Color(0x99000000), offset: Offset(0, 8), blurRadius: 16),
    BoxShadow(
        color: Color(0x99000000), offset: Offset(0, 24), blurRadius: 48),
  ];
}
