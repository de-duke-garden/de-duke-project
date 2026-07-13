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
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/listing_card.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../chat/data/chat_repository.dart';
import '../../reporting/data/report_repository.dart';
import '../../reporting/screens/report_sheet.dart';
// `ListingImage` collides with the widget of the same name from
// listing_card.dart -- this import is only used for `Listing`,
// `CommercialListingDetails`, `ShortletListingDetails`, so hide it here
// rather than prefixing every reference in the file.
import '../../share_summary/data/share_repository.dart';
import '../../share_summary/screens/share_summary_sheet.dart';
import '../data/listing_models.dart' hide ListingImage;
import '../data/listing_repository.dart';

enum _LoadState { loading, loaded, empty, error, offline }

class ListingDetailScreen extends StatefulWidget {
  const ListingDetailScreen({
    super.key,
    required this.listingId,
    required this.repository,
    required this.chatRepository,
    required this.shareRepository,
    required this.reportRepository,
    this.heroTag,
  });

  final String listingId;
  final ListingRepository repository;
  final ChatRepository chatRepository;

  /// FEAT-020 -- backs the AppBar's Share action (screens.md Screen 17).
  final ShareRepository shareRepository;

  /// FEAT-009 -- backs the AppBar's Report action (screens.md Screen 6:
  /// "Report button ... POST /listings/:id/report").
  final ReportRepository reportRepository;

  /// Shared-element `heroTag` passed by the originating Listing Card
  /// (e.g. `'listing-image-<id>'`) so the hero carousel's first image
  /// resolves the `page-transition` shared-element transition from the
  /// card that was tapped. Falls back to a per-listing default so the
  /// screen still renders correctly (just without a matching flight) when
  /// reached via deep link/route restoration rather than a card tap.
  final String? heroTag;

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  _LoadState _state = _LoadState.loading;
  Listing? _listing;
  String? _errorMessage;
  bool _startingConversation = false;

  /// Same `'listing-image-<id>'` pattern used by ListingCard/
  /// FeaturedListingCard on Home Feed and Search Results (branding.md
  /// Mobile Motion & Micro-interactions `shared-element-transition`) --
  /// defaulted here rather than requiring every navigation call site to
  /// pass it explicitly, since the pattern is fully determined by the
  /// listing id.
  String get _heroTag => widget.heroTag ?? 'listing-image-${widget.listingId}';

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

  /// "Share" -- screens.md Screen 6 Edge Cases / FEAT-020: opens Screen 17
  /// as a modal bottom sheet using the already-loaded listing payload, so
  /// no extra fetch is needed to populate the preview.
  void _openShareSheet() {
    final listing = _listing;
    if (listing == null) return;
    showShareSummarySheet(
      context,
      listing: listing,
      repository: widget.shareRepository,
    );
  }

  /// "Report" -- screens.md Screen 6's Report IconButton, accessible via
  /// PopupMenuButton in the AppBar, per spec. On success shows the
  /// "Report Submitted" confirmation toast (Screen 6 States table).
  Future<void> _openReportSheet() async {
    final submitted = await showReportSheet(
      context,
      repository: widget.reportRepository,
      kind: ReportTargetKind.listing,
      targetId: widget.listingId,
    );
    if (submitted == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Thanks, we'll review this.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Listing'),
        actions: [
          if (_state == _LoadState.loaded)
            IconButton(
              onPressed: _openShareSheet,
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share',
            ),
          // screens.md Screen 6: "Secondary action IconButtons for Share and
          // Report, accessible via a PopupMenuButton in the AppBar." Owner
          // viewing their own listing hides Report (Edge Cases) -- deferred
          // here since ownership resolution isn't available on this screen
          // yet (see this file's header docstring's known simplification).
          if (_state == _LoadState.loaded)
            PopupMenuButton<void>(
              tooltip: 'More options',
              itemBuilder: (context) => [
                PopupMenuItem<void>(
                  onTap: _openReportSheet,
                  child: const Row(
                    children: [
                      Icon(Icons.flag_outlined, size: 20),
                      SizedBox(width: AppSpacing.sm),
                      Text('Report listing'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: switch (_state) {
        // branding.md Loading States: skeleton photo block + text lines
        // matching the real hero image/price header shape, not a spinner.
        _LoadState.loading => const _DetailSkeleton(),
        _LoadState.offline => EmptyStateView(
            isError: true,
            title: "You're offline",
            message: 'Check your connection and try again.',
            actionLabel: 'Retry',
            onAction: _load,
          ),
        _LoadState.error => EmptyStateView(
            isError: true,
            title: 'Something went wrong',
            message: _errorMessage ?? 'Could not load this listing.',
            actionLabel: 'Retry',
            onAction: _load,
          ),
        _LoadState.empty => EmptyStateView(
            title: 'This listing is no longer available',
            actionLabel: 'Back to Search',
            onAction: () => context.canPop()
                ? context.pop()
                : context.pushNamed(RouteNames.search),
          ),
        _LoadState.loaded =>
          _ListingBody(listing: _listing!, heroTag: _heroTag),
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

/// branding.md Loading States: skeleton photo block + placeholder text
/// lines matching the shape/radius of the real hero image and price header.
class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        const AspectRatio(
          aspectRatio: 16 / 9,
          child: SkeletonBox(borderRadius: AppRadii.md, height: double.infinity),
        ),
        const SizedBox(height: AppSpacing.md),
        const SkeletonBox(width: 220, height: 22),
        const SizedBox(height: AppSpacing.sm),
        const SkeletonBox(width: 160, height: 14),
        const SizedBox(height: AppSpacing.md),
        const SkeletonBox(width: 140, height: 28),
        const SizedBox(height: AppSpacing.lg),
        const SkeletonBox(height: 14),
        const SizedBox(height: AppSpacing.sm),
        const SkeletonBox(height: 14),
        const SizedBox(height: AppSpacing.sm),
        SkeletonBox(width: MediaQuery.of(context).size.width * 0.6, height: 14),
      ],
    );
  }
}

class _ListingBody extends StatefulWidget {
  const _ListingBody({required this.listing, required this.heroTag});

  final Listing listing;
  final String heroTag;

  @override
  State<_ListingBody> createState() => _ListingBodyState();
}

class _ListingBodyState extends State<_ListingBody> {
  // Screen 6 Modernization Notes: "the sticky bottom action bar and body
  // content fade/slide in just after the hero image settles, in a brief
  // two-step sequence rather than everything appearing simultaneously."
  bool _bodyVisible = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(AppDurations.sharedElementTransition, () {
      if (mounted) setState(() => _bodyVisible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final commercial = listing.commercial;
    final shortlet = listing.shortlet;
    final priceLabel = commercial != null
        ? '₦${commercial.price.toStringAsFixed(0)}${commercial.dealType == 'lease' ? ' / lease' : ''}'
        : shortlet != null
            ? '₦${shortlet.nightlyPrice.toStringAsFixed(0)} / night'
            : '';
    final primaryImageUrl =
        listing.images.isNotEmpty ? listing.images.first.imageUrl : null;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            // Same `'listing-image-<id>'` heroTag as the originating
            // Listing/Featured card -- the shared-element transition
            // (branding.md `shared-element-transition`) flies the tapped
            // card's image into this carousel's first frame.
            child: ListingImage(imageUrl: primaryImageUrl, heroTag: widget.heroTag),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AnimatedOpacity(
          opacity: _bodyVisible ? 1 : 0,
          duration: AppDurations.normal,
          curve: AppCurves.easeOutSmooth,
          child: AnimatedSlide(
            offset: _bodyVisible ? Offset.zero : const Offset(0, 0.03),
            duration: AppDurations.normal,
            curve: AppCurves.easeOutSmooth,
            child: _buildDetails(context, priceLabel, commercial, shortlet),
          ),
        ),
      ],
    );
  }

  Widget _buildDetails(BuildContext context, String priceLabel,
      CommercialListingDetails? commercial, ShortletListingDetails? shortlet) {
    final listing = widget.listing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        // Fixed price -- `stat-display` type token, no offer/negotiation
        // controls, by design (AGENTS.md fixed-price rule).
        Text(priceLabel,
            style: AppTypography.statDisplay.copyWith(color: AppColors.primary)),
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
