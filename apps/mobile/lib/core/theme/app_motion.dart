/// De-Duke Mobile Motion & Micro-interactions tokens -- branding.md.
/// Durations and curves for every interaction/entrance/celebratory moment
/// in the mobile app. Screens compose these rather than hand-rolling
/// one-off animation values.
import 'package:flutter/animation.dart';

class AppDurations {
  AppDurations._();

  static const instant = Duration(milliseconds: 100);
  static const fast = Duration(milliseconds: 200);
  static const normal = Duration(milliseconds: 300);
  static const slow = Duration(milliseconds: 450);

  // Interaction-specific tokens.
  static const tapScaleDown = Duration(milliseconds: 100);
  static const tapScaleUp = Duration(milliseconds: 150);
  static const tapScaleEmphasisUp = Duration(milliseconds: 200);
  static const listStaggerItem = Duration(milliseconds: 240);
  static const listStaggerOffset = Duration(milliseconds: 30);
  static const badgePop = Duration(milliseconds: 300);
  static const pageTransition = Duration(milliseconds: 280);
  static const sharedElementTransition = Duration(milliseconds: 320);
  static const pullToRefresh = Duration(milliseconds: 400);
  static const celebratorySequence = Duration(milliseconds: 900);
  static const skeletonShimmer = Duration(milliseconds: 1400);
}

class AppCurves {
  AppCurves._();

  static const easeOutSmooth = Cubic(0.16, 1, 0.3, 1);
  static const easeInOutSmooth = Cubic(0.65, 0, 0.35, 1);
  static const easeOutExpo = Cubic(0.19, 1, 0.22, 1);

  /// A single, gentle 4-6% overshoot -- reserved for moments that should
  /// feel alive (success checkmarks, badge reveals, FAB press, toggles).
  /// Used sparingly, never chained.
  static const easeSpringSoft = Cubic(0.34, 1.56, 0.64, 1);
}
