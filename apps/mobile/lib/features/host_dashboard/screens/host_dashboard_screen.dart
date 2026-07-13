/// screens.md Screen 12: Host Dashboard (FEAT-017). Fetches listings and
/// verification status in parallel per that screen's Data Flow step 1.
///
/// Modernization Notes (screens.md Screen 12): Listing status cards adopt
/// Listing Card container/press styling with `tap-scale` and enter with
/// `list-stagger` on first load; status and stale-activity flags use
/// semantic-color badges (icon+text, never color alone) that animate in
/// with `badge-pop` when a status changes; view/inquiry counts use the
/// `stat-small` type token; initial load uses skeleton cards, not a
/// spinner; the empty state uses the illustrated system.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/badge_pop.dart';
import '../../../core/widgets/de_duke_logo.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/list_stagger.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/tap_scale.dart';
import '../../become_host/data/host_account_models.dart';
import '../../become_host/data/host_account_repository.dart';
import '../data/host_dashboard_models.dart';
import '../data/host_dashboard_repository.dart';

enum _ScreenState { loading, unverified, loaded, empty, error, offline }

class HostDashboardScreen extends StatefulWidget {
  const HostDashboardScreen({
    super.key,
    required this.dashboardRepository,
    required this.hostAccountRepository,
  });

  final HostDashboardRepository dashboardRepository;
  final HostAccountRepository hostAccountRepository;

  @override
  State<HostDashboardScreen> createState() => _HostDashboardScreenState();
}

class _HostDashboardScreenState extends State<HostDashboardScreen> {
  _ScreenState _state = _ScreenState.loading;
  List<HostDashboardListingItem> _listings = [];
  HostAccountStatus? _verification;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _ScreenState.loading);
    try {
      final verificationFuture = widget.hostAccountRepository.getMySubmission();
      final listingsFuture = widget.dashboardRepository.getMyListings();
      final verification = await verificationFuture;
      final listings = await listingsFuture;

      if (!mounted) return;
      setState(() {
        _verification = verification;
        _listings = listings;
        if (verification == null || verification.status != 'verified') {
          _state = _ScreenState.unverified;
        } else if (listings.isEmpty) {
          _state = _ScreenState.empty;
        } else {
          _state = _ScreenState.loaded;
        }
      });
    } on HostDashboardException catch (e) {
      if (!mounted) return;
      setState(() => _state = e.message == 'offline' ? _ScreenState.offline : _ScreenState.error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _ScreenState.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Consistent tab-root AppBar treatment (mark + label) across Home,
        // Chat, Dashboard, Profile -- see TabAppBarTitle.
        title: const TabAppBarTitle('My Listings'),
        automaticallyImplyLeading: false, // tab root (core/routing/app_shell.dart)
        actions: [
          if (_verification != null)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: Center(
                child: BadgePop(
                  triggerKey: _verification!.status,
                  child: TextButton(
                    onPressed: () => context.pushNamed(RouteNames.verification),
                    child: Text(_verification!.status == 'verified' ? 'Verified Host' : 'Verify'),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _state == _ScreenState.unverified
            ? () => context.pushNamed(RouteNames.verification)
            : () => context.pushNamed(RouteNames.listingNew),
        icon: const Icon(Icons.add),
        label: const Text('New Listing'),
      ),
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_state) {
      case _ScreenState.loading:
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          itemCount: 4,
          itemBuilder: (_, __) => const SkeletonListingCard(),
        );
      case _ScreenState.unverified:
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: _DashboardCard(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Verify your identity to start listing',
                    style: AppTypography.h3,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ElevatedButton(
                    onPressed: () => context.pushNamed(RouteNames.verification),
                    child: const Text('Become a Host'),
                  ),
                ],
              ),
            ),
          ),
        );
      case _ScreenState.empty:
        return EmptyStateView(
          title: "You haven't listed anything yet",
          actionLabel: 'Create your first listing',
          onAction: () => context.pushNamed(RouteNames.listingNew),
        );
      case _ScreenState.error:
        return EmptyStateView(
          title: 'Something went wrong',
          isError: true,
          actionLabel: 'Retry',
          onAction: _load,
        );
      case _ScreenState.offline:
        return Column(
          children: [
            MaterialBanner(
              content: const Text("You're offline."),
              actions: [TextButton(onPressed: _load, child: const Text('Retry'))],
            ),
            if (_listings.isNotEmpty) Expanded(child: _buildListingList(context)),
          ],
        );
      case _ScreenState.loaded:
        return RefreshIndicator(onRefresh: _load, child: _buildListingList(context));
    }
  }

  Widget _buildListingList(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: _listings.length,
      itemBuilder: (context, index) => ListStaggerItem(
        index: index,
        child: _ListingStatusCard(
          listing: _listings[index],
          onTap: () => context.pushNamed(
            RouteNames.listingDetail,
            pathParameters: {'id': _listings[index].id},
          ),
        ),
      ),
    );
  }
}

/// Lightweight Listing Card container spec (radius-lg / shadow-sm /
/// hairline border) for non-photo metric/status cards -- branding.md
/// Listing Card component tokens, reused here per host_dashboard_screen
/// modernization scope since [ListingCard] itself is photo-specific.
class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.sm,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// Semantic-color status badge -- icon + text, never color alone
/// (branding.md Accessibility rule).
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  ({Color color, IconData icon, String label}) _spec() {
    return switch (status) {
      'active' => (color: AppColors.success, icon: Icons.check_circle, label: 'Active'),
      'banned' => (color: AppColors.error, icon: Icons.block, label: 'Banned'),
      'under_review' => (color: AppColors.warning, icon: Icons.hourglass_top, label: 'Under Review'),
      'unpublished' => (color: AppColors.warning, icon: Icons.visibility_off, label: 'Unpublished'),
      'closed' => (color: AppColors.warning, icon: Icons.lock_outline, label: 'Closed'),
      _ => (color: AppColors.warning, icon: Icons.info_outline, label: status),
    };
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec();
    return BadgePop(
      triggerKey: status,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
        decoration: BoxDecoration(
          color: spec.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadii.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(spec.icon, size: 14, color: spec.color),
            const SizedBox(width: 4),
            Text(
              spec.label,
              style: AppTypography.caption.copyWith(color: spec.color),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListingStatusCard extends StatelessWidget {
  const _ListingStatusCard({required this.listing, required this.onTap});

  final HostDashboardListingItem listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: TapScale(
        onTap: onTap,
        child: _DashboardCard(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(listing.title, style: AppTypography.h3),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          _StatusBadge(status: listing.status),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            '${listing.viewCount} views · ${listing.inquiryCount} inquiries',
                            style: AppTypography.statSmall.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      if (listing.status == 'banned' && listing.statusReason != null)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: Text(
                            listing.statusReason!,
                            style: AppTypography.bodySmall.copyWith(color: AppColors.error),
                          ),
                        ),
                      if (listing.isStale)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: BadgePop(
                            triggerKey: 'stale-${listing.id}',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.warning),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'No activity yet — consider updating photos or price',
                                    style: AppTypography.bodySmall.copyWith(color: AppColors.warning),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline),
                  tooltip: 'Chat threads',
                  onPressed: () => context.pushNamed(RouteNames.chat),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
