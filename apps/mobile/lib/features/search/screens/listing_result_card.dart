/// Listing `Card` for the Search Results list -- Screen 5's "Listing card"
/// component, summarizing a listing with distance-from-search-point
/// (FEAT-006 acceptance criterion: "Results display distance from the
/// search point").
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../data/search_models.dart';

// AppSizing lives in app_spacing.dart alongside AppSpacing/AppRadii.

class ListingResultCard extends StatelessWidget {
  const ListingResultCard(
      {super.key, required this.result, required this.onTap});

  final ListingSearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final currencyFormat =
        NumberFormat.currency(locale: 'en_NG', symbol: '₦', decimalDigits: 0);
    return Card(
      margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: result.primaryImageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: result.primaryImageUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) =>
                          const _ImagePlaceholder(),
                    )
                  : const _ImagePlaceholder(),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          result.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                      ),
                      if (result.isVerifiedHost) ...[
                        const SizedBox(width: AppSpacing.xs),
                        const Icon(Icons.verified,
                            size: AppSizing.iconSm, color: AppColors.verified),
                        const SizedBox(width: AppSpacing.xs),
                        const Text('Verified',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.verified)),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${result.locationCity}, ${result.locationState}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        result.displayPrice != null
                            ? '${currencyFormat.format(result.displayPrice)}${result.nightlyPrice != null ? '/night' : ''}'
                            : 'Price unavailable',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary),
                      ),
                      if (result.distanceKm != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on,
                                size: 14, color: AppColors.textSecondary),
                            const SizedBox(width: 2),
                            Text(
                              '${result.distanceKm!.toStringAsFixed(1)} km away',
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceSecondary,
      child: const Center(
          child: Icon(Icons.home_work_outlined,
              color: AppColors.textSecondary, size: 32)),
    );
  }
}
