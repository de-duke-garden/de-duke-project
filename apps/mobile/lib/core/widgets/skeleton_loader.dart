/// Skeleton loading system -- branding.md "Empty & Loading States". Content
/// lists and detail screens load with shimmering placeholders shaped like
/// the real content, instead of a bare `CircularProgressIndicator`.
///
/// Every color here comes from `Theme.of(context).colorScheme` -- never a
/// bare `AppColors.X` constant. Bug fix: this file previously read
/// `AppColors.surfaceSecondary`/`.border` directly with no brightness
/// handling at all, so every skeleton (the loading animation shown while
/// listings/rows/chat load) rendered light-mode colors even in dark mode.
library;

import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';

/// A single shimmering skeleton block. Compose several into screen-specific
/// skeleton layouts (see [SkeletonListingCard], [SkeletonRow]).
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius = AppRadii.sm,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.skeletonShimmer,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final base = colorScheme.surfaceContainerHighest;
    final highlight = colorScheme.outlineVariant.withValues(alpha: 0.5);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = CurvedAnimation(
                parent: _controller, curve: AppCurves.easeInOutSmooth)
            .value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(-1 + 2 * t, 0),
              end: Alignment(1 + 2 * t, 0),
              colors: [base, highlight, base],
              stops: const [0.35, 0.5, 0.65],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton placeholder matching the shape/radius/spacing of a standard
/// Listing Card (see [ListingCard]).
class SkeletonListingCard extends StatelessWidget {
  const SkeletonListingCard({super.key, this.featured = false});

  final bool featured;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: featured ? 4 / 3 : 16 / 9,
            child: const SkeletonBox(borderRadius: 0, height: double.infinity),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: featured ? 200 : 140, height: 16),
                const SizedBox(height: AppSpacing.sm),
                const SkeletonBox(width: 100, height: 12),
                const SizedBox(height: AppSpacing.sm),
                SkeletonBox(width: featured ? 120 : 80, height: featured ? 28 : 18),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton placeholder for a single list row (chat inbox, transaction
/// history, saved searches, settings) -- matches row height/spacing.
class SkeletonRow extends StatelessWidget {
  const SkeletonRow({super.key, this.height = 64});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          SkeletonBox(width: height, height: height, borderRadius: AppRadii.md),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonBox(width: 160, height: 14),
                const SizedBox(height: AppSpacing.sm),
                SkeletonBox(width: 220, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton placeholder for a chat bubble, aligned per sender side.
class SkeletonChatBubble extends StatelessWidget {
  const SkeletonChatBubble({super.key, this.outgoing = false});

  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        child: SkeletonBox(
          width: 180,
          height: 36,
          borderRadius: AppRadii.md,
        ),
      ),
    );
  }
}

/// A vertical list of [count] skeleton rows/cards -- convenience for
/// screens' `Loading` state.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.count = 5,
    this.builder,
  });

  final int count;
  final Widget Function(BuildContext, int)? builder;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: count,
      itemBuilder: builder ?? (context, index) => const SkeletonRow(),
    );
  }
}
