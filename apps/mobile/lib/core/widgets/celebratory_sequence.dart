/// `celebratory-sequence` motion token -- branding.md: 900ms sequenced
/// reveal for Payment Confirmation, Listing Live Confirmation, and
/// Verification Approved. The checkmark/badge draws in (~350ms) -> soft
/// scale-spring settle (~200ms) -> supporting content fades/staggers in
/// (~350ms). One clearly-earned expressive moment per major success.
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';

class CelebratorySequence extends StatefulWidget {
  const CelebratorySequence({
    super.key,
    required this.supportingContent,
    this.icon = Icons.check_circle,
    this.iconSize = 96,
    this.accentColor,
  });

  /// Content revealed after the checkmark settles (summary card, buttons).
  final Widget supportingContent;
  final IconData icon;
  final double iconSize;
  final Color? accentColor;

  @override
  State<CelebratorySequence> createState() => _CelebratorySequenceState();
}

class _CelebratorySequenceState extends State<CelebratorySequence>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.celebratorySequence,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.accentColor ?? AppColors.success;
    // Checkmark draw-in + spring settle: 0 -> ~0.61 of total (550ms/900ms).
    final drawIn = CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.39, curve: AppCurves.easeOutSmooth));
    final springSettle = CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.28, 0.61, curve: AppCurves.easeSpringSoft));
    // Supporting content fade/stagger: final ~350ms.
    final supportingFade = CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.61, 1.0, curve: AppCurves.easeOutSmooth));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final scale = drawIn.value < 1
                ? drawIn.value
                : springSettle.value.clamp(0.0, 1.2);
            return Opacity(
              opacity: drawIn.value.clamp(0.0, 1.0),
              child: Transform.scale(scale: scale, child: child),
            );
          },
          child: Icon(widget.icon, size: widget.iconSize, color: color),
        ),
        const SizedBox(height: 24),
        AnimatedBuilder(
          animation: supportingFade,
          builder: (context, child) => Opacity(
            opacity: supportingFade.value.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, 12 * (1 - supportingFade.value)),
              child: child,
            ),
          ),
          child: widget.supportingContent,
        ),
      ],
    );
  }
}
