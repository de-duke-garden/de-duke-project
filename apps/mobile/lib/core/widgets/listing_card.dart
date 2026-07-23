/// Listing Card / Featured-Hero Card -- branding.md Component Tokens. The
/// shared visual container used by Home Feed, Search Results, Host/Agency
/// dashboards, Portfolio, and Leads wherever a listing/lead/metric is
/// summarized in card form.
///
/// Every color here comes from `Theme.of(context)` (`colorScheme` for
/// surfaces/borders/text/primary, `AppSemanticColors` for shadows) -- never
/// a bare `AppColors.X` constant and never a manual
/// `Theme.of(context).brightness == Brightness.dark` branch to pick between
/// a light/dark pair. `ColorScheme`/`AppSemanticColors` are already
/// resolved for the active theme (see app_theme.dart's own docstring), so
/// picking colors by hand here is exactly the bug class that left this
/// card and its skeleton loader rendering light-mode colors in dark mode.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_semantic_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'tap_scale.dart';

/// Bottom-to-top scrim gradient over image-topped cards so overlaid
/// text/badges stay legible without a separate opaque chip (branding.md
/// Shadows & Elevation, "Image-topped cards"). Deliberately a fixed
/// black-based scrim (not theme-derived) -- it sits over a photo, not a
/// themed surface, so it must stay dark in both light and dark mode for
/// the overlaid white text to remain legible.
class ListingImageScrim extends StatelessWidget {
  const ListingImageScrim({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0x7312201C), Color(0x0012201C)],
        ),
      ),
    );
  }
}

/// House-silhouette no-photo placeholder, per branding.md Imagery & Photo
/// Treatment -- never a generic gray box.
class ListingImagePlaceholder extends StatelessWidget {
  const ListingImagePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: FractionallySizedBox(
        widthFactor: 0.4,
        heightFactor: 0.4,
        child: Icon(Icons.home_work_outlined,
            color: colorScheme.primaryContainer),
      ),
    );
  }
}

/// Blur-up loading listing image: low-res/placeholder crossfades to the
/// full image over `duration-fast`.
class ListingImage extends StatelessWidget {
  const ListingImage({super.key, this.imageUrl, this.heroTag});

  final String? imageUrl;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final image = imageUrl == null
        ? const ListingImagePlaceholder()
        : CachedNetworkImage(
            imageUrl: imageUrl!,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 200),
            placeholder: (context, url) => const ListingImagePlaceholder(),
            errorWidget: (context, url, error) =>
                const ListingImagePlaceholder(),
          );
    return heroTag == null ? image : Hero(tag: heroTag!, child: image);
  }
}

/// Standard Listing Card -- 16:9 image, `stat-small` price, verified
/// badge, `shadow-sm`, hairline border, `tap-scale` press feedback.
class ListingCard extends StatelessWidget {
  const ListingCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.subtitle,
    required this.priceLabel,
    this.isVerified = false,
    this.trailingBadge,
    this.onTap,
    this.heroTag,
  });

  final String? imageUrl;
  final String title;
  final String subtitle;
  final String priceLabel;
  final bool isVerified;
  final Widget? trailingBadge;
  final VoidCallback? onTap;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<AppSemanticColors>()!;
    return TapScale(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
          boxShadow: semantic.shadowSm,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ListingImage(imageUrl: imageUrl, heroTag: heroTag),
                  const ListingImageScrim(),
                  if (isVerified)
                    const Positioned(
                        top: AppSpacing.sm,
                        left: AppSpacing.sm,
                        child: _VerifiedBadge()),
                  if (trailingBadge != null)
                    Positioned(
                        bottom: AppSpacing.sm,
                        right: AppSpacing.sm,
                        child: trailingBadge!),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.h3
                          .copyWith(color: colorScheme.onSurface)),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Icon(Icons.location_on,
                          size: AppSizing.iconSm,
                          color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodySmall.copyWith(
                                color: colorScheme.onSurfaceVariant)),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(priceLabel,
                      style: AppTypography.statSmall
                          .copyWith(color: colorScheme.primary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Featured/Hero Card variant -- the one card per screen allowed to feel
/// more premium. Larger image, `stat-display` price, subtle primary-light
/// gradient overlay, `shadow-md` at rest -> `shadow-xl` on press.
///
/// Bug fix: previously built its `BoxDecoration` from bare `AppColors.surface`/
/// `.primaryLight`/`.border` constants with no brightness handling at all
/// (unlike `ListingCard` above), so this specific card -- the "Near You"
/// hero card on Home Feed -- rendered with a light background/gradient
/// even in dark mode. Now sourced from `Theme.of(context)` like every
/// other widget in this file.
class FeaturedListingCard extends StatefulWidget {
  const FeaturedListingCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.subtitle,
    required this.priceLabel,
    this.isVerified = false,
    this.onTap,
    this.heroTag,
  });

  final String? imageUrl;
  final String title;
  final String subtitle;
  final String priceLabel;
  final bool isVerified;
  final VoidCallback? onTap;
  final String? heroTag;

  @override
  State<FeaturedListingCard> createState() => _FeaturedListingCardState();
}

class _FeaturedListingCardState extends State<FeaturedListingCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<AppSemanticColors>()!;
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colorScheme.surface, colorScheme.primaryContainer],
            stops: const [0.7, 1.0],
          ),
          boxShadow: _pressed ? semantic.shadowXl : semantic.shadowMd,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ListingImage(imageUrl: widget.imageUrl, heroTag: widget.heroTag),
                  const ListingImageScrim(),
                  Positioned(
                    left: AppSpacing.sm,
                    bottom: AppSpacing.sm,
                    child: Row(
                      children: [
                        const _FeaturedBadge(),
                        if (widget.isVerified) ...[
                          const SizedBox(width: AppSpacing.xs),
                          const _VerifiedBadge(),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          AppTypography.h2.copyWith(color: colorScheme.onSurface)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(widget.subtitle,
                      style: AppTypography.bodySmall
                          .copyWith(color: colorScheme.onSurfaceVariant)),
                  const SizedBox(height: AppSpacing.sm),
                  Text(widget.priceLabel,
                      style: AppTypography.statDisplay
                          .copyWith(color: colorScheme.primary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified,
              size: AppSizing.iconSm, color: colorScheme.onPrimaryContainer),
          const SizedBox(width: AppSpacing.xs),
          Text('VERIFIED HOST',
              style: AppTypography.caption
                  .copyWith(color: colorScheme.onPrimaryContainer)),
        ],
      ),
    );
  }
}

class _FeaturedBadge extends StatelessWidget {
  const _FeaturedBadge();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: Text('FEATURED',
          style: AppTypography.caption
              .copyWith(color: colorScheme.onTertiaryContainer)),
    );
  }
}
