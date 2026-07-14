/// screens.md Screen 14: Portfolio List View.
///
/// FEAT-018 (Agency Portfolio Management): status + assigned-agent filters,
/// the Bulk Action Bar (multi-select -> relist/archive), and each listing's
/// assigned-agent/owner-client tags are all implemented here now. Bulk
/// relist/archive maps onto the same host-settable active/unpublished pair
/// PATCH /v1/listings/:id already enforces one listing at a time (see
/// app/api/v1/listings.py's update_listing_endpoint) -- applied to many
/// listings at once via POST /v1/agency/listings/bulk-action.
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
  List<TeamMember> _team = [];
  String? _statusFilter;
  String? _agentFilter;

  // Bulk Action Bar (FEAT-018 AC "perform bulk actions ... on multiple
  // listings at once") -- entered via long-press on a card, exited by
  // clearing the selection entirely rather than a separate "Cancel" mode
  // toggle, since an empty selection has nothing left to bulk-act on.
  final Set<String> _selectedIds = {};
  bool _bulkActionInFlight = false;

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
      final listingsFuture = widget.repository.getListings(
        status: _statusFilter,
        assignedAgentId: _agentFilter,
      );
      // Team roster backs the agent-filter menu -- fetched alongside
      // listings rather than once at screen construction, since a newly
      // invited agent should show up in the filter without leaving/
      // re-entering this screen.
      final teamFuture = widget.repository.getTeam();
      final listings = await listingsFuture;
      final team = await teamFuture;
      if (!mounted) return;
      setState(() {
        _listings = listings;
        _team = team;
        _selectedIds.removeWhere(
            (id) => !listings.any((listing) => listing.id == id));
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

  void _onAgentFilterSelected(String? agentId) {
    setState(() => _agentFilter = agentId);
    _load();
  }

  void _toggleSelection(String listingId) {
    setState(() {
      if (_selectedIds.contains(listingId)) {
        _selectedIds.remove(listingId);
      } else {
        _selectedIds.add(listingId);
      }
    });
  }

  Future<void> _runBulkAction(String action) async {
    if (_selectedIds.isEmpty || _bulkActionInFlight) return;
    setState(() => _bulkActionInFlight = true);
    try {
      final results = await widget.repository.bulkUpdateListingStatus(
        listingIds: _selectedIds.toList(),
        action: action,
      );
      final failures = results.where((r) => !r.success).length;
      if (!mounted) return;
      setState(() => _selectedIds.clear());
      await _load();
      if (!mounted) return;
      final actionLabel = action == 'relist' ? 'Relisted' : 'Archived';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failures == 0
                ? '$actionLabel ${results.length} listing${results.length == 1 ? '' : 's'}.'
                : '$actionLabel ${results.length - failures} of ${results.length} listings -- $failures could not be updated.',
          ),
        ),
      );
    } on AgencyException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _bulkActionInFlight = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedIds.isEmpty
            ? 'Portfolio'
            : '${_selectedIds.length} selected'),
        leading: _selectedIds.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Clear selection',
                onPressed: () => setState(_selectedIds.clear),
              ),
        actions: [
          if (_selectedIds.isEmpty && _team.isNotEmpty)
            PopupMenuButton<String?>(
              tooltip: 'Filter by agent',
              icon: const Icon(Icons.person_search_outlined),
              onSelected: _onAgentFilterSelected,
              itemBuilder: (context) => [
                const PopupMenuItem(value: null, child: Text('All agents')),
                for (final member in _team)
                  PopupMenuItem(
                      value: member.userId, child: Text(member.fullName)),
              ],
            ),
        ],
      ),
      floatingActionButton: _selectedIds.isEmpty
          ? FloatingActionButton.extended(
              onPressed: () => context.pushNamed(RouteNames.listingNew),
              icon: const Icon(Icons.add),
              label: const Text('New Listing'),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            if (_selectedIds.isEmpty) _buildFilterChips(),
            if (_agentFilter != null && _selectedIds.isEmpty)
              _buildAgentFilterBanner(),
            Expanded(child: _buildBody(context)),
            if (_selectedIds.isNotEmpty) _BulkActionBar(
              selectedCount: _selectedIds.length,
              busy: _bulkActionInFlight,
              onRelist: () => _runBulkAction('relist'),
              onArchive: () => _runBulkAction('archive'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgentFilterBanner() {
    String? name;
    for (final member in _team) {
      if (member.userId == _agentFilter) {
        name = member.fullName;
        break;
      }
    }
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text('Agent: ${name ?? 'Unknown'}',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => _onAgentFilterSelected(null),
            child: const Text('Clear'),
          ),
        ],
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
          onAction: () {
            setState(() => _agentFilter = null);
            _onFilterSelected(null);
          },
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
        final selectionMode = _selectedIds.isNotEmpty;
        final isSelected = _selectedIds.contains(listing.id);
        return ListStaggerItem(
          index: index,
          child: TapScale(
            onTap: selectionMode
                ? () => _toggleSelection(listing.id)
                : () => context.pushNamed(
                      RouteNames.listingDetail,
                      pathParameters: {'id': listing.id},
                    ),
            // Long-press starts a bulk selection from any card, not just
            // ones already showing a checkbox -- the standard multi-select
            // entry gesture (mirrors mobile Photos/Files apps) rather than
            // requiring a separate "Select" mode toggle in the AppBar.
            onLongPress: () => _toggleSelection(listing.id),
            child: Container(
              margin: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadii.lg),
                border: Border.all(
                    color:
                        isSelected ? AppColors.primary : AppColors.border,
                    width: isSelected ? 2 : 1),
                boxShadow: AppShadows.sm,
              ),
              child: Row(
                children: [
                  if (selectionMode) ...[
                    Icon(
                      isSelected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
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
                        if (listing.ownerClientName != null &&
                            listing.ownerClientName!.isNotEmpty)
                          Text(
                            'Owner/Client: ${listing.ownerClientName}',
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
                  if (!selectionMode)
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

/// Screen 14's Bulk Action Bar -- pinned above the bottom safe area once at
/// least one listing is selected. Relist/Archive map onto the
/// active/unpublished pair every other host/agency-facing status control
/// in this app already uses (see edit_listing_screen.dart's Published
/// switch) rather than introducing a third listing state just for this bar.
class _BulkActionBar extends StatelessWidget {
  const _BulkActionBar({
    required this.selectedCount,
    required this.busy,
    required this.onRelist,
    required this.onArchive,
  });

  final int selectedCount;
  final bool busy;
  final VoidCallback onRelist;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(top: BorderSide(color: AppColors.border)),
        boxShadow: AppShadows.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: busy ? null : onArchive,
              icon: const Icon(Icons.archive_outlined),
              label: const Text('Archive'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: busy ? null : onRelist,
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: const Text('Relist'),
            ),
          ),
        ],
      ),
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
