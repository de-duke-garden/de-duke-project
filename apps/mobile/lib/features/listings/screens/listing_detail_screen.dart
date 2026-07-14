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
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/routing/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/enum_display.dart';
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
      final conversationId = await widget.chatRepository
          .startConversation(listingId: widget.listingId);
      if (!mounted) return;
      context.pushNamed(
        RouteNames.chatThread,
        pathParameters: {'id': conversationId},
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Couldn't start a conversation. Try again.")),
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
                        onPressed: _startingConversation
                            ? null
                            : _messagePropertyManagement,
                        // Full "Message Property Management" label wrapped/
                        // clipped the button on narrow screens -- shortened
                        // to "Message Host" with an icon (still communicates
                        // the same "Chat Thread" exit point from screens.md)
                        // and forced to a single line so it can never push
                        // the sibling "Book Now" button off-balance.
                        child: _startingConversation
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.chat_bubble_outline,
                                      size: AppSizing.iconSm),
                                  SizedBox(width: AppSpacing.xs),
                                  Flexible(
                                    child: Text(
                                      'Message Host',
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
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
          child:
              SkeletonBox(borderRadius: AppRadii.md, height: double.infinity),
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
            child: ListingImage(
                imageUrl: primaryImageUrl, heroTag: widget.heroTag),
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
            style:
                AppTypography.statDisplay.copyWith(color: AppColors.primary)),
        const SizedBox(height: AppSpacing.md),
        Text(listing.description),
        // schema.md base Listing.amenities -- shared by both listing
        // types (mirrors Create Listing's own shared placement, above the
        // type-specific sections). Was collected by Create Listing but
        // never displayed anywhere on this screen.
        if (listing.amenities.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('Amenities', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: listing.amenities
                .map((amenity) => _TagChip(label: humanizeEnumValue(amenity)))
                .toList(),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Text('Location', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        // Embedded map preview -- a small, non-interactive GoogleMap
        // centered on the listing (zoom/rotate/tilt/scroll gestures
        // disabled: this is a preview, not the pan/zoom search map
        // SearchMapView already implements). Tapping it opens full
        // turn-by-turn navigation in the device's own maps app instead of
        // building a second in-app interactive map for the same listing.
        _ListingLocationPreview(
          latitude: listing.latitude,
          longitude: listing.longitude,
        ),
        if (commercial != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('Property details',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          // Was a single run-on `•`-joined Text -- replaced with a card of
          // icon-labelled stats (matches the visual weight of the price/
          // location sections above it) so the section reads as scannable
          // facts rather than a plain sentence.
          _DetailStatsCard(
            stats: [
              _DetailStat(Icons.category_outlined,
                  humanizeEnumValue(commercial.propertySubtype)),
              _DetailStat(Icons.square_foot,
                  '${commercial.sizeSquareMeters.toStringAsFixed(0)} sqm'),
              _DetailStat(Icons.bathtub_outlined,
                  '${commercial.bathrooms} bath${commercial.bathrooms == 1 ? '' : 's'}'),
            ],
          ),
          if (commercial.rooms.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            ...commercial.rooms.map(
              (r) => _RoomRow(
                label: r.level,
                dimensions: '${r.widthMeters}m x ${r.lengthMeters}m',
              ),
            ),
          ],
          // schema.md's CommercialListing.legalDocuments -- "Shown to
          // seekers as a trust signal, particularly for Sale listings."
          // Was collected by Create Listing but never displayed anywhere.
          if (commercial.legalDocuments.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text('Legal documents available',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: commercial.legalDocuments
                  .map((doc) => _TagChip(label: humanizeEnumValue(doc)))
                  .toList(),
            ),
          ],
        ],
        if (shortlet != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('Stay details', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          // Same run-on-sentence problem as Property details above --
          // now a stat card of icon + value pairs.
          _DetailStatsCard(
            stats: [
              _DetailStat(
                  Icons.villa_outlined, humanizeEnumValue(shortlet.subtype)),
              _DetailStat(Icons.bed_outlined,
                  '${shortlet.bedrooms} bedroom${shortlet.bedrooms == 1 ? '' : 's'}'),
              _DetailStat(Icons.bathtub_outlined,
                  '${shortlet.bathrooms} bath${shortlet.bathrooms == 1 ? '' : 's'}'),
              _DetailStat(Icons.nights_stay_outlined,
                  'Min ${shortlet.minimumStayNights} night${shortlet.minimumStayNights == 1 ? '' : 's'}'),
            ],
          ),
          if (shortlet.houseRules.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: shortlet.houseRules
                  .map((rule) => _TagChip(label: rule))
                  .toList(),
            ),
          ],
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

/// One icon + value fact rendered inside a [_DetailStatsCard], e.g. the
/// bedroom count or minimum stay length.
class _DetailStat {
  const _DetailStat(this.icon, this.label);

  final IconData icon;
  final String label;
}

/// Replaces the old plain `'a • b • c'` sentence in the Property/Stay
/// details sections with a bordered card of icon-labelled facts, laid out
/// in a wrap so it reflows cleanly on narrow screens instead of truncating.
class _DetailStatsCard extends StatelessWidget {
  const _DetailStatsCard({required this.stats});

  final List<_DetailStat> stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Wrap(
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.sm,
        children: stats
            .map(
              (stat) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(stat.icon,
                      size: AppSizing.iconSm, color: AppColors.primary),
                  const SizedBox(width: AppSpacing.xs),
                  Text(stat.label,
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}

/// A single commercial room's level and dimensions, e.g. "Ground floor:
/// 4m x 5m" -- given its own icon/row treatment instead of a bare Text so
/// a listing with several rooms doesn't read as a wall of plain sentences.
class _RoomRow extends StatelessWidget {
  const _RoomRow({required this.label, required this.dimensions});

  final String label;
  final String dimensions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.meeting_room_outlined,
              size: AppSizing.iconSm, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
              child:
                  Text(label, style: Theme.of(context).textTheme.bodyMedium)),
          Text(dimensions,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

/// A single confirmed-present tag -- a house rule ("No smoking"), an
/// amenity ("Parking"), or a confirmed-available legal document
/// ("Certificate of Occupancy") -- rendered as a pill chip instead of a
/// bare "• value" text line. Shared across all three sections rather than
/// duplicated per-section since they're visually and semantically the same
/// "here's a confirmed fact about this listing" chip.
class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppRadii.full),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline,
              size: AppSizing.iconSm, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.xs),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Small, non-interactive map preview for Screen 6's "Location" section.
/// Real GoogleMap widget (not a placeholder) -- gestures are disabled since
/// this is a preview, not SearchMapView's pan/zoom search map, and it opens
/// external turn-by-turn navigation on tap rather than duplicating that
/// interactive-map experience in a second place.
class _ListingLocationPreview extends StatelessWidget {
  const _ListingLocationPreview({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;

  Future<void> _openInMapsApp() async {
    // Universal Google Maps URL -- opens the installed Google/Apple Maps
    // app on both platforms via url_launcher's external-application mode,
    // rather than requiring a native platform-specific deep link scheme.
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final position = LatLng(latitude, longitude);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: SizedBox(
        height: 160,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(target: position, zoom: 15),
              markers: {
                Marker(
                    markerId: const MarkerId('listing-location'),
                    position: position),
              },
              // Preview only -- SearchMapView (Screen 5) already owns the
              // pan/zoom interactive map experience; this widget just shows
              // "roughly here" and hands off to a real maps app on tap.
              zoomControlsEnabled: false,
              zoomGesturesEnabled: false,
              scrollGesturesEnabled: false,
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
              myLocationButtonEnabled: false,
              liteModeEnabled: true,
            ),
            // Full-bounds tap target -- GoogleMap swallows taps for its own
            // gesture recognizers even with gestures disabled above, so a
            // transparent Material+InkWell on top is what actually makes
            // "tap to open in Maps" reliably tappable (48x48 minimum target
            // satisfied trivially since it spans the whole 160px-tall preview).
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _openInMapsApp,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            Positioned(
              right: AppSpacing.sm,
              bottom: AppSpacing.sm,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.open_in_new,
                        size: 14, color: AppColors.textSecondary),
                    SizedBox(width: 4),
                    Text('Open in Maps',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
