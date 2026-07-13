/// Listing `Card` for the Search Results list -- Screen 5's "Listing card"
/// component, summarizing a listing with distance-from-search-point
/// (FEAT-006 acceptance criterion: "Results display distance from the
/// search point"). Built on the shared `ListingCard` (branding.md Component
/// Tokens) rather than a bespoke `Card`, so Search Results matches Home
/// Feed's visual spec exactly; distance is folded into the subtitle line
/// since `ListingCard` doesn't have a dedicated distance slot.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/listing_card.dart';
import '../data/search_models.dart';

class ListingResultCard extends StatelessWidget {
  const ListingResultCard(
      {super.key, required this.result, required this.onTap, this.index});

  final ListingSearchResult result;
  final VoidCallback onTap;

  /// When set, used to build a per-listing `heroTag` for the
  /// shared-element transition into Listing Detail. Left null when the
  /// same listing might be rendered more than once in the current tree
  /// (Hero tags must be unique per route).
  final int? index;

  @override
  Widget build(BuildContext context) {
    final currencyFormat =
        NumberFormat.currency(locale: 'en_NG', symbol: '₦', decimalDigits: 0);
    final priceLabel = result.displayPrice != null
        ? '${currencyFormat.format(result.displayPrice)}${result.nightlyPrice != null ? '/night' : ''}'
        : 'Price unavailable';
    final subtitle = result.distanceKm != null
        ? '${result.locationCity}, ${result.locationState} · ${result.distanceKm!.toStringAsFixed(1)} km away'
        : '${result.locationCity}, ${result.locationState}';

    return ListingCard(
      imageUrl: result.primaryImageUrl,
      title: result.title,
      subtitle: subtitle,
      priceLabel: priceLabel,
      isVerified: result.isVerifiedHost,
      heroTag: 'listing-image-${result.id}',
      onTap: onTap,
    );
  }
}
