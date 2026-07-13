/// De-Duke Illustration System -- branding.md. Single-color, logo-derived
/// line-and-shape vector illustrations spanning three tiers: empty/error
/// states (low opacity, 96-120px), onboarding/first-run (larger, full
/// opacity), and celebratory/milestone moments (accent-tone exception).
/// Built from simple CustomPainter geometry (interlocking strokes, pitched
/// roof, four-pane window) rather than shipping raster assets, so the mark
/// stays crisp at any size and themes with `primary`/`primary-light`.
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
      IllustrationTier.celebratory =>
        AppColors.success.withValues(alpha: 0.14),
      _ => AppColors.primaryLight,
    };
    final glyphColor = color ??
        switch (tier) {
          IllustrationTier.empty => AppColors.primary.withValues(alpha: 0.18),
          IllustrationTier.onboarding => AppColors.primary,
          IllustrationTier.celebratory => AppColors.success,
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
