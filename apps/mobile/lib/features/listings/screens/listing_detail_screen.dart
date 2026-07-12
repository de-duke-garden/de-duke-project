/// screens.md Screen 6: Listing Detail.
/// Fixed price display -- no negotiation/offer UI (AGENTS.md Behavior
/// Rules: De-Duke lists at a fixed price, it does not broker negotiation).
/// Shows an embedded map preview and a verified-host badge.
///
/// Exit Points (screens.md): Chat Thread ("Message Property Management"),
/// Confirm Booking Details ("Book Now"/"Reserve"). Both were previously
/// missing entirely -- this screen only rendered the loading/error/detail
/// states, with no sticky action bar -- confirmed gap, fixed here.
/// "Manage Listing" (owner viewing their own listing, per screens.md's
/// Edge Cases) is NOT implemented -- that requires resolving whether the
/// viewer's own HostAccount owns this listing, a separate fetch this
/// screen doesn't make today; left as a known simplification rather than
/// silently faked.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../chat/data/chat_repository.dart';
import '../data/listing_models.dart';
import '../data/listing_repository.dart';

enum _LoadState { loading, loaded, empty, error, offline }

class ListingDetailScreen extends StatefulWidget {
  const ListingDetailScreen({
    super.key,
    required this.listingId,
    required this.repository,
    required this.chatRepository,
  });

  final String listingId;
  final ListingRepository repository;
  final ChatRepository chatRepository;

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  _LoadState _state = _LoadState.loading;
  Listing? _listing;
  String? _errorMessage;
  bool _startingConversation = false;

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
        _state = message.contains('SocketException') ||
                message.contains('connection')
            ? _LoadState.offline
            : _LoadState.error;
      });
    }
  }

  /// "Message Property Management" -- screens.md Screen 6's Components
  /// table: "Navigates to Chat Thread". Firestore sign-in + conversation
  /// creation happen here (not eagerly on screen mount) since starting a
  /// conversation is a deliberate user action, not something to do on
  /// every listing view.
  Future<void> _messagePropertyManagement() async {
    setState(() => _startingConversation = true);
    try {
      await widget.chatRepository.ensureSignedIn();
      final conversationId =
          await widget.chatRepository.startConversation(listingId: widget.listingId);
      if (!mounted) return;
      context.pushNamed(
        RouteNames.chatThread,
        pathParameters: {'id': conversationId},
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't start a conversation. Try again.")),
      );
    } finally {
      if (mounted) setState(() => _startingConversation = false);
    }
  }

  /// "Book Now" / "Reserve" -- screens.md Screen 6's Components table:
  /// "Navigates to Confirm Booking Details" (Screen 6b, `/listing/:id/confirm-booking`).
  void _bookNow() => context.pushNamed(
        RouteNames.listingConfirmBooking,
        pathParameters: {'id': widget.listingId},
      );

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
            message:
                _errorMessage ?? 'Something went wrong loading this listing.',
            onRetry: _load,
          ),
        _LoadState.empty => const _MessageState(
            icon: Icons.search_off,
            message: 'This listing is no longer available.',
          ),
        _LoadState.loaded => _ListingBody(listing: _listing!),
      },
      bottomNavigationBar: _state == _LoadState.loaded
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _startingConversation ? null : _messagePropertyManagement,
                        child: _startingConversation
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Message Property Management'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _bookNow,
                        child: const Text('Book Now'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState(
      {required this.icon, required this.message, this.onRetry});

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
              child: Text(listing.title,
                  style: Theme.of(context).textTheme.headlineSmall),
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
          Text('Property details',
              style: Theme.of(context).textTheme.titleMedium),
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
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified, size: 16, color: AppColors.verified),
          SizedBox(width: 4),
          Text('Verified',
              style: TextStyle(color: AppColors.verified, fontSize: 12)),
        ],
      ),
    );
  }
}
