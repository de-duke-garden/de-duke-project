/// De-Duke two-layer elevation/shadow system -- branding.md "Shadows &
/// Elevation". Every non-flat surface uses a tight contact shadow plus a
/// soft ambient shadow (two `BoxShadow`s), never a single flat shadow --
/// this is what separates "designed" elevation from default Material.
///
/// The raw values now live on `AppShadowValues` (app_semantic_colors.dart),
/// so `AppSemanticColors.light`/`.dark` can be `const` -- this class
/// re-exports them under their original names for any call site not yet
/// migrated to `Theme.of(context).extension<AppSemanticColors>()!.shadowSm`
/// (the preferred, already-brightness-resolved way to reach these; see
/// AGENTS.md's theming rule). New code should reach for the theme
/// extension, not this class, and not branch on `Brightness` itself.
library;

import 'package:flutter/material.dart';

import 'app_semantic_colors.dart';

class AppShadows {
  AppShadows._();

  static const List<BoxShadow> none = AppShadowValues.none;
  static const List<BoxShadow> xs = AppShadowValues.xs;
  static const List<BoxShadow> sm = AppShadowValues.sm;
  static const List<BoxShadow> md = AppShadowValues.md;
  static const List<BoxShadow> lg = AppShadowValues.lg;
  static const List<BoxShadow> xl = AppShadowValues.xl;
  static const List<BoxShadow> xsDark = AppShadowValues.xsDark;
  static const List<BoxShadow> smDark = AppShadowValues.smDark;
  static const List<BoxShadow> mdDark = AppShadowValues.mdDark;
  static const List<BoxShadow> lgDark = AppShadowValues.lgDark;
  static const List<BoxShadow> xlDark = AppShadowValues.xlDark;

  /// Deprecated -- prefer
  /// `Theme.of(context).extension<AppSemanticColors>()!.shadowSm` (etc.),
  /// which is already resolved for the current theme and doesn't require
  /// the caller to separately compute `isDark` itself. Kept only so any
  /// remaining unmigrated call site keeps compiling during the theme
  /// refactor.
  static List<BoxShadow> of(
          List<BoxShadow> light, List<BoxShadow> dark, bool isDark) =>
      isDark ? dark : light;
}
