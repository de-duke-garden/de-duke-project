/// De-Duke Illustration System -- branding.md. Spans three tiers:
///   - `empty` (empty/error states): the SHIPPED APP LOGO MARK itself
///     (`assets/images/de-duke.png`) at ~65% opacity, 96-120px, centered on
///     a `primary-light`/`surface-secondary` circular backdrop. Updated per
///     branding.md's "Illustration style (updated)" note -- this tier no
///     longer uses a custom-drawn glyph; a static mark reads more clearly
///     "on-brand" for a low-key utility moment. Scoped to this tier ONLY
///     (branding.md is explicit: "implementors should not extend the
///     logo-mark treatment beyond empty/error states without a separate
///     design decision") -- onboarding and celebratory below are
///     deliberately untouched.
///   - `onboarding`/`celebratory`: unchanged, single-color line-and-shape
///     vector illustrations built from the logo's geometric language
///     (interlocking strokes, pitched roof, four-pane window), via
///     CustomPainter so they stay crisp at any size and theme with
///     `primary`/`success`. A static mark would undersell the app's
///     "hello" moment (onboarding) and can't support the multi-stage
///     `celebratory-sequence` motion token (celebratory).
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum IllustrationTier { empty, onboarding, celebratory }

class DeDukeIllustration extends StatelessWidget {
  const DeDukeIllustration({
    super.key,
    this.tier = IllustrationTier.empty,
    this.size,
    this.color,
  });

  final IllustrationTier tier;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedSize = size ??
        switch (tier) {
          IllustrationTier.empty => 108.0,
          IllustrationTier.onboarding => 180.0,
          IllustrationTier.celebratory => 96.0,
        };
    final backdropColor = switch (tier) {
      IllustrationTier.celebratory => AppColors.success.withValues(alpha: 0.14),
      _ => AppColors.primaryLight,
    };

    if (tier == IllustrationTier.empty) {
      return SizedBox(
        width: resolvedSize,
        height: resolvedSize,
        child: DecoratedBox(
          decoration:
              BoxDecoration(color: backdropColor, shape: BoxShape.circle),
          child: Padding(
            padding: EdgeInsets.all(resolvedSize * 0.24),
            child: Opacity(
              opacity: 0.65,
              child: Image.asset(
                'assets/images/de-duke.png',
                fit: BoxFit.contain,
                semanticLabel: 'De-Duke',
              ),
            ),
          ),
        ),
      );
    }

    final glyphColor = color ??
        switch (tier) {
          IllustrationTier.onboarding => AppColors.primary,
          IllustrationTier.celebratory => AppColors.success,
          IllustrationTier.empty => AppColors.primary, // unreachable
        };

    return SizedBox(
      width: resolvedSize,
      height: resolvedSize,
      child: DecoratedBox(
        decoration: BoxDecoration(color: backdropColor, shape: BoxShape.circle),
        child: Padding(
          padding: EdgeInsets.all(resolvedSize * 0.2),
          child: CustomPaint(painter: _HouseGlyphPainter(color: glyphColor)),
        ),
      ),
    );
  }
}

/// Interlocking-"D" house-and-window glyph, derived from the logo's
/// architectural monogram (roofline + four-pane window motif).
class _HouseGlyphPainter extends CustomPainter {
  const _HouseGlyphPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.07
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    // Pitched roofline.
    final roof = Path()
      ..moveTo(0, h * 0.42)
      ..lineTo(w * 0.5, 0)
      ..lineTo(w, h * 0.42);
    canvas.drawPath(roof, paint);

    // Walls.
    canvas.drawLine(Offset(w * 0.12, h * 0.42), Offset(w * 0.12, h), paint);
    canvas.drawLine(Offset(w * 0.88, h * 0.42), Offset(w * 0.88, h), paint);
    canvas.drawLine(Offset(w * 0.12, h), Offset(w * 0.88, h), paint);

    // Four-pane window, centered.
    final windowRect = Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.68), width: w * 0.34, height: h * 0.28);
    canvas.drawRect(windowRect, paint);
    canvas.drawLine(windowRect.topCenter, windowRect.bottomCenter, paint);
    canvas.drawLine(windowRect.centerLeft, windowRect.centerRight, paint);
  }

  @override
  bool shouldRepaint(covariant _HouseGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}
