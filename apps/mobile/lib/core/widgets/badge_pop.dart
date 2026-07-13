/// `badge-pop` motion token -- branding.md: 300ms `ease-spring-soft` pop/
/// settle for verification badges appearing, unread-count increments, and
/// new-status pills -- draws the eye to state changes without a
/// full-screen moment. Rebuild with a new [triggerKey] whenever the state
/// change should re-trigger the pop (e.g. status text or count changes).
library;

import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

class BadgePop extends StatelessWidget {
  const BadgePop({super.key, required this.triggerKey, required this.child});

  final Object triggerKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(triggerKey),
      tween: Tween(begin: 0.6, end: 1.0),
      duration: AppDurations.badgePop,
      curve: AppCurves.easeSpringSoft,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: child,
    );
  }
}
