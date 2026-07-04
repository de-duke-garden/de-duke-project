/// Screen 8 (implied by screens.md Screen 7 create flow): Listing Detail.
/// Fixed price display -- no negotiation/offer UI (AGENTS.md Behavior
/// Rules: De-Duke lists at a fixed price, it does not broker negotiation).
/// Shows an embedded map preview and a verified-host badge.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../data/listing_models.dart';
import '../data/listing_repository.dart';

enum _LoadState { loading, loaded, empty, error, offline }

class ListingDetailScreen extends StatefulWidget {
  const ListingDetailScreen({
    super.key,
    required this.listingId,
    required this.repository,
  });

  final String listingId;
  final ListingRepository repository;

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  _LoadState _state = _LoadState.loading;
  Listing? _listing;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final listing = await widget.repository.getListing(widget.listingId);
      setState(() {
        _listing = listing;
        _state = _LoadState.loaded;
      });
    } on Exception catch (e) {
      final message = e.toString();
      setState(() {
        _errorMessage = message;
        // DioException with no response type usually means offline/timeout.
        _state = message.contains('SocketException') || message.contains('connection')
            ? _LoadState.offline
            : _LoadState.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Listing')),
      body: switch (_state) {
        _LoadState.loading => const Center(child: CircularProgressIndicator()),
        _LoadState.offline => _MessageState(
            icon: Icons.wifi_off,
            message: "You're offline. Check your connection and try again.",
            onRetry: _load,
          ),
        _LoadState.error => _MessageState(
            icon: Icons.error_outline,
            message: _errorMessage ?? 'Something went wrong loading this listing.',
            onRetry: _load,
          ),
        _LoadState.empty => const _MessageState(
            icon: Icons.search_off,
            message: 'This listing is no longer available.',
          ),
        _LoadState.loaded => _ListingBody(listing: _listing!),
      },
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.icon, required this.message, this.onRetry});

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppSizing.iconLg, color: AppColors.textSecondary),
            const SizedBox(height: AppSpacing.md),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.md),
              ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

class _ListingBody extends StatelessWidget {
  const _ListingBody({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final commercial = listing.commercial;
    final shortlet = listing.shortlet;
    final priceLabel = commercial != null
        ? '₦${commercial.price.toStringAsFixed(0)}${commercial.dealType == 'lease' ? ' / lease' : ''}'
        : shortlet != null
            ? '₦${shortlet.nightlyPrice.toStringAsFixed(0)} / night'
            : '';

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (listing.images.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                color: AppColors.surfaceSecondary,
                child: const Center(child: Icon(Icons.image, size: 40)),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: Text(listing.title, style: Theme.of(context).textTheme.headlineSmall),
            ),
            if (listing.isVerifiedActive) const _VerifiedBadge(),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${listing.addressLine}, ${listing.city}, ${listing.state}',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        // Fixed price -- no offer/negotiation controls, by design.
        Text(
          priceLabel,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(listing.description),
        const SizedBox(height: AppSpacing.lg),
        Text('Location', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        // Embedded map preview. TODO: wire to Google Maps SDK with
        // GOOGLE_MAPS_API_KEY once available (never hardcode the key).
        Container(
          height: 160,
          decoration: BoxDecoration(
            color: AppColors.surfaceSecondary,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Center(
            child: Text(
              'Map preview (${listing.latitude.toStringAsFixed(4)}, '
              '${listing.longitude.toStringAsFixed(4)})',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
        if (commercial != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('Property details', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${commercial.propertySubtype} • ${commercial.sizeSquareMeters} sqm • ${commercial.bathrooms} bath',
          ),
          if (commercial.rooms.isNotEmpty)
            ...commercial.rooms.map(
              (r) => Text('${r.level}: ${r.widthMeters}m x ${r.lengthMeters}m'),
            ),
        ],
        if (shortlet != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('Stay details', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${shortlet.subtype} • ${shortlet.bedrooms} bedroom(s) • ${shortlet.bathrooms} bath • min ${shortlet.minimumStayNights} night(s)',
          ),
          if (shortlet.houseRules.isNotEmpty)
            ...shortlet.houseRules.map((rule) => Text('• $rule')),
        ],
      ],
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified, size: 16, color: AppColors.verified),
          SizedBox(width: 4),
          Text('Verified', style: TextStyle(color: AppColors.verified, fontSize: 12)),
        ],
      ),
    );
  }
}
