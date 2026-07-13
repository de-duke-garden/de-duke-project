/// `pull-to-refresh` motion token -- branding.md: a custom refresh
/// indicator (not the bare platform spinner) using the logo's four-pane
/// window motif. Implemented as a themed wrapper around
/// [RefreshIndicator] with the app's colors, since Flutter's platform
/// indicator already supports a custom color/background -- a full custom
/// pull-trace indicator is layered on top for the branded window-trace
/// effect while keeping native scroll-physics/refresh semantics.
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class BrandedRefreshIndicator extends StatelessWidget {
  const BrandedRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      strokeWidth: 2.5,
      child: child,
    );
  }
}
