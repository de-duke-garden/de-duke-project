/// screens.md Screen 13: Agency Dashboard (FEAT-012/FEAT-019 area).
/// Bottom-nav tab root for agency accounts (see app_shell.dart's
/// `_showsDashboardTab` equivalent for the agency role).
///
/// Modernization Notes (screens.md Screen 13): Summary metric cards adopt
/// the Listing Card container spec with dashboard figures set in
/// `stat-display` (primary) / `stat-small` (secondary), entering with
/// `list-stagger` on first load; initial load uses skeleton cards; empty
/// state uses the illustrated system.
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

class AgencyDashboardScreen extends StatefulWidget {
  const AgencyDashboardScreen({super.key, required this.repository});

  final AgencyRepository repository;

  @override
  State<AgencyDashboardScreen> createState() => _AgencyDashboardScreenState();
}

class _AgencyDashboardScreenState extends State<AgencyDashboardScreen> {
  _ScreenState _state = _ScreenState.loading;
  AgencySummary? _summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _ScreenState.loading);
    try {
      final summary = await widget.repository.getSummary();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        // "Set up your agency portfolio" empty state -- a brand-new agency
        // account with no listings and no team yet (screens.md Screen 13
        // Empty condition).
        _state = summary.totalActiveListings == 0 && !summary.hasTeam
            ? _ScreenState.empty
            : _ScreenState.loaded;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agency Overview'),
        automaticallyImplyLeading: false, // tab root
        actions: [
          IconButton(
            icon: const Icon(Icons.group_outlined),
            tooltip: 'Manage team',
            onPressed: () => context.pushNamed(RouteNames.agencyTeam),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_state) {
      case _ScreenState.loading:
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: const [
            SkeletonBox(height: 96, borderRadius: AppRadii.lg),
            SizedBox(height: AppSpacing.md),
            SkeletonBox(height: 96, borderRadius: AppRadii.lg),
            SizedBox(height: AppSpacing.md),
            SkeletonBox(height: 96, borderRadius: AppRadii.lg),
          ],
        );
      case _ScreenState.empty:
        return EmptyStateView(
          title: 'Set up your agency portfolio',
          actionLabel: 'View Portfolio',
          onAction: () => context.pushNamed(RouteNames.agencyPortfolio),
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
              content:
                  const Text("You're offline. Showing last known summary."),
              actions: [
                TextButton(onPressed: _load, child: const Text('Retry'))
              ],
            ),
            if (_summary != null)
              Expanded(child: _buildSummary(context, _summary!)),
          ],
        );
      case _ScreenState.loaded:
        return RefreshIndicator(
          onRefresh: _load,
          child: _buildSummary(context, _summary!),
        );
    }
  }

  Widget _buildSummary(BuildContext context, AgencySummary summary) {
    final cards = <_MetricCardData>[
      _MetricCardData(
          'Active Listings', summary.totalActiveListings.toString()),
      _MetricCardData(
          'Unassigned Leads', summary.unassignedLeadsCount.toString()),
      _MetricCardData(
          'Deals Closed This Month', summary.dealsClosedThisMonth.toString()),
    ];

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        for (var i = 0; i < cards.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child:
                ListStaggerItem(index: i, child: _MetricCard(data: cards[i])),
          ),
        const SizedBox(height: AppSpacing.sm),
        ListStaggerItem(
          index: cards.length,
          child: _ShortcutRow(
            icon: Icons.apartment_outlined,
            label: 'Portfolio',
            onTap: () => context.pushNamed(RouteNames.agencyPortfolio),
          ),
        ),
        ListStaggerItem(
          index: cards.length + 1,
          child: _ShortcutRow(
            icon: Icons.mark_email_unread_outlined,
            label: 'New Leads',
            onTap: () => context.pushNamed(RouteNames.agencyLeads),
          ),
        ),
      ],
    );
  }
}

class _MetricCardData {
  const _MetricCardData(this.label, this.value);
  final String label;
  final String value;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.data});
  final _MetricCardData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(data.value, style: AppTypography.statDisplay),
          const SizedBox(height: AppSpacing.xs),
          Text(data.label,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.border),
        ),
        child: ListTile(
          leading: Icon(icon),
          title: Text(label, style: AppTypography.h3),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}
