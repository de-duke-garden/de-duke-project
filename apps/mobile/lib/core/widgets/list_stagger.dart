/// `list-stagger` motion token -- branding.md: first paint of any card/row
/// list fades + slides up 12px in a quick cascading stagger (240ms per
/// item, 30ms offset, `ease-out-expo`) rather than popping in
/// simultaneously. Skipped on pull-to-refresh -- only wrap first-load /
/// filter-change item builders in this, not repeat-view rebuilds.
library;

import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

class ListStaggerItem extends StatefulWidget {
  const ListStaggerItem({
    super.key,
    required this.index,
    required this.child,
  });

  final int index;
  final Widget child;

  @override
  State<ListStaggerItem> createState() => _ListStaggerItemState();
}

class _ListStaggerItemState extends State<ListStaggerItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.listStaggerItem,
  );

  @override
  void initState() {
    super.initState();
    final delay = AppDurations.listStaggerOffset * widget.index;
    Future.delayed(delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved =
        CurvedAnimation(parent: _controller, curve: AppCurves.easeOutExpo);
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) {
        return Opacity(
          opacity: curved.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - curved.value)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
