/// De-Duke color tokens -- transcribed directly from branding.md.
/// Never hardcode a hex value in a screen; always reference these tokens
/// (or the equivalent Material ColorScheme mapping in app_theme.dart).
import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // -- Primary --
  static const primary = Color(0xFF0F6E5C);
  static const primaryHover = Color(0xFF0B5647);
  static const primaryLight = Color(0xFFE1F2EE);

  // -- Secondary / Accent --
  static const accent = Color(0xFFD98E04);
  static const accentLight = Color(0xFFFBEBCC);

  // -- Neutral (Light Mode) --
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSecondary = Color(0xFFF4F6F5);
  static const textPrimary = Color(0xFF12201C);
  static const textSecondary = Color(0xFF5F6E68);
  static const border = Color(0xFFE1E6E3);

  // -- Semantic --
  static const success = Color(0xFF1FA35B);
  static const warning = Color(0xFFE2A230);
  static const error = Color(0xFFD9463B);
  static const info = Color(0xFF2E7BC4);
  static const verified = primary; // reuses primary per branding.md

  // -- Dark Mode --
  static const surfaceDark = Color(0xFF101613);
  static const surfaceSecondaryDark = Color(0xFF1A211D);
  static const textPrimaryDark = Color(0xFFF2F5F3);
  static const textSecondaryDark = Color(0xFF9CAAA3);
  static const borderDark = Color(0xFF2B332E);
  static const primaryDark = Color(0xFF2C9C82);
  static const primaryLightDark = Color(0xFF193831);
}
