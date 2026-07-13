/// screens.md Screen 14: Portfolio List View.
///
/// Bulk multi-select/archive/relist actions (screens.md's Bulk Action Bar)
/// are NOT implemented here -- no backend endpoint exists for them in this
/// feature slice's scope (app/api/v1/agency.py only wires read/team/lead
/// endpoints per the implementation brief); this screen implements the
/// read-only list + filter chips + all documented read-path states
/// (Loading/Loaded/Empty/Error/Offline), and links into Lead Analytics per
/// listing (Screen 16).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/list_stagger.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/tap_scale.dart';
import '../data/agency_models.dart';
import '../data/agency_repository.dart';

enum _ScreenState { loading, loaded, empty, error, offline }

class PortfolioListScreen extends StatefulWidget {
  const PortfolioListScreen({super.key, required this.repository});

  final AgencyRepository repository;

  @override
  State<PortfolioListScreen> createState() => _PortfolioListScreenState();
}

class _PortfolioListScreenState extends State<PortfolioListScreen> {
  _ScreenState _state = _ScreenState.loading;
  List<AgencyListingItem> _listings = [];
  String? _statusFilter;

  static const _statusFilters = <String?>[
    null,
    'active',
    'under_review',
    'banned',
    'closed'
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _ScreenState.loading);
    try {
      final listings =
          await widget.repository.getListings(status: _statusFilter);
      if (!mounted) return;
      setState(() {
        _listings = listings;
        _state = listings.isEmpty ? _ScreenState.empty : _ScreenState.loaded;
      });
    } on AgencyException catch (e) {
      if (!mounted) return;
      setState(() =>
          _state = e.isOffline ? _ScreenState.offline : _ScreenState.error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _ScreenState.error);
    }
  }

  void _onFilterSelected(String? status) {
    setState(() => _statusFilter = status);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Portfolio')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.pushNamed(RouteNames.listingNew),
        icon: const Icon(Icons.add),
        label: const Text('New Listing'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildFilterChips(),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          for (final status in _statusFilters)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: ChoiceChip(
                label:
                    Text(status == null ? 'All' : status.replaceAll('_', ' ')),
                selected: _statusFilter == status,
                onSelected: (_) => _onFilterSelected(status),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_state) {
      case _ScreenState.loading:
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          itemCount: 5,
          itemBuilder: (_, __) => const SkeletonRow(),
        );
      case _ScreenState.empty:
        return EmptyStateView(
          title: 'No listings match these filters',
          actionLabel: 'Clear filters',
          onAction: () => _onFilterSelected(null),
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
              actions: [
                TextButton(onPressed: _load, child: const Text('Retry'))
              ],
            ),
            if (_listings.isNotEmpty) Expanded(child: _buildList(context)),
          ],
        );
      case _ScreenState.loaded:
        return RefreshIndicator(onRefresh: _load, child: _buildList(context));
    }
  }

  Widget _buildList(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: _listings.length,
      itemBuilder: (context, index) {
        final listing = _listings[index];
        return ListStaggerItem(
          index: index,
          child: TapScale(
            onTap: () => context.pushNamed(
              RouteNames.listingDetail,
              pathParameters: {'id': listing.id},
            ),
            child: Container(
              margin: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadii.lg),
                border: Border.all(color: AppColors.border),
                boxShadow: AppShadows.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(listing.title, style: AppTypography.h3),
                        const SizedBox(height: AppSpacing.xs),
                        _StatusBadge(status: listing.status),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          listing.assignedAgentName == null
                              ? 'Unassigned'
                              : 'Agent: ${listing.assignedAgentName}',
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.textSecondary),
                        ),
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
                  ),
                  IconButton(
                    icon: const Icon(Icons.insights_outlined),
                    tooltip: 'View analytics',
                    onPressed: () => context.pushNamed(
                      RouteNames.agencyListingAnalytics,
                      pathParameters: {'id': listing.id},
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Semantic-color status badge -- icon + text, never color alone
/// (branding.md Accessibility rule). Mirrors host_dashboard_screen.dart's
/// own `_StatusBadge`.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  ({Color color, IconData icon, String label}) _spec() {
    return switch (status) {
      'active' => (
          color: AppColors.success,
          icon: Icons.check_circle,
          label: 'Active'
        ),
      'banned' => (color: AppColors.error, icon: Icons.block, label: 'Banned'),
      'under_review' => (
          color: AppColors.warning,
          icon: Icons.hourglass_top,
          label: 'Under Review'
        ),
      'unpublished' => (
          color: AppColors.warning,
          icon: Icons.visibility_off,
          label: 'Unpublished'
        ),
      'closed' => (
          color: AppColors.warning,
          icon: Icons.lock_outline,
          label: 'Closed'
        ),
      _ => (color: AppColors.warning, icon: Icons.info_outline, label: status),
    };
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(spec.icon, size: 14, color: spec.color),
        const SizedBox(width: 4),
        Text(spec.label,
            style: AppTypography.caption.copyWith(color: spec.color)),
      ],
    );
  }
}
