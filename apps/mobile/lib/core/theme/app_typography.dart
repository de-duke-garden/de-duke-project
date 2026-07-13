/// De-Duke type scale -- branding.md.
/// Fonts: Manrope (display/headings), Inter (body), JetBrains Mono
/// (transaction IDs, receipts). Font assets/packages added when the fonts
/// are vendored -- placeholder family names below until then.
import 'package:flutter/material.dart';

class AppTypography {
  AppTypography._();

  static const String _headingFont = 'Manrope';
  static const String _bodyFont = 'Inter';
  static const String _monoFont = 'JetBrainsMono';

  static const display = TextStyle(
    fontFamily: _headingFont,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );
  static const h1 = TextStyle(
    fontFamily: _headingFont,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );
  static const h2 = TextStyle(
    fontFamily: _headingFont,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );
  static const h3 = TextStyle(
    fontFamily: _headingFont,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );
  static const bodyLarge = TextStyle(
    fontFamily: _bodyFont,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );
  static const body = TextStyle(
    fontFamily: _bodyFont,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );
  static const bodySmall = TextStyle(
    fontFamily: _bodyFont,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );
  static const caption = TextStyle(
    fontFamily: _bodyFont,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );
  static const mono =
      TextStyle(fontFamily: _monoFont, fontSize: 13, height: 1.5);

  /// Listing price on Property Detail / Featured-Hero cards, wallet
  /// balance -- tabular figures, tight tracking, its own visual register
  /// distinct from headings (branding.md Type Scale).
  static const statDisplay = TextStyle(
    fontFamily: _headingFont,
    fontSize: 28,
    fontWeight: FontWeight.w800,
    height: 1.15,
    letterSpacing: -0.28,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Price on standard Listing Cards, secondary stat call-outs.
  static const statSmall = TextStyle(
    fontFamily: _headingFont,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.2,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
