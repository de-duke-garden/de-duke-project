/// Resolves a `listingId` to its listing title wherever a screen only has
/// the id on hand (chat conversations, transactions -- both models only
/// carry `listingId`, not a denormalized title). Several screens used to
/// show the raw id directly (`'Listing <id>'`) instead of something a user
/// can actually recognize; this widget centralizes the fetch-and-fallback
/// so every call site behaves the same way.
library;

import 'package:flutter/material.dart';

import '../../features/listings/data/listing_repository.dart';

class ListingTitleText extends StatelessWidget {
  const ListingTitleText({
    super.key,
    required this.listingId,
    required this.listingRepository,
    this.style,
    this.maxLines = 1,
  });

  final String listingId;
  final ListingRepository listingRepository;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: listingRepository.getListing(listingId),
      builder: (context, snapshot) {
        // Falls back to the raw id while loading and if the fetch fails
        // (e.g. the listing was since deleted) -- better than a stuck
        // loading state or a blank title.
        final title = snapshot.data?.title;
        return Text(
          title ?? 'Listing $listingId',
          style: style,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}
