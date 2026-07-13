/// Baseline press-feedback wrapper -- branding.md `tap-scale` /
/// `tap-scale-emphasis` tokens. Wrap any tappable card, row, or chip in
/// [TapScale] to get the standard 97-98% press-down + spring-back release
/// used everywhere in the app; pass [emphasis]: true for primary CTAs that
/// want the single soft `ease-spring-soft` overshoot on release instead of
/// a plain settle.
library;

import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

class TapScale extends StatefulWidget {
  const TapScale({
    super.key,
    required this.child,
    this.onTap,
    this.emphasis = false,
    this.scale = 0.97,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Use for primary CTAs (Book Now, Publish, Save Search, selection
  /// cards) -- release uses `ease-spring-soft` instead of a plain settle.
  final bool emphasis;
  final double scale;
  final BorderRadius? borderRadius;

  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final duration = _pressed
        ? AppDurations.tapScaleDown
        : (widget.emphasis
            ? AppDurations.tapScaleEmphasisUp
            : AppDurations.tapScaleUp);
    final curve =
        _pressed || !widget.emphasis ? Curves.easeOut : AppCurves.easeSpringSoft;

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1.0,
        duration: duration,
        curve: curve,
        child: widget.child,
      ),
    );
  }
}
