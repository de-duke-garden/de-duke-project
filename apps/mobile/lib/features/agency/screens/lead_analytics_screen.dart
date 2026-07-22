/// screens.md Screen 16: Lead Analytics View (FEAT-019). Route
/// `/agency/listings/:id/analytics`.
///
/// Modernization Notes: Metric cards adopt Listing Card container styling
/// and enter with `list-stagger` on load; headline metric figures use
/// `stat-display`, secondary metrics use `stat-small`; changing the date
/// range crossfades the metric values (`AnimatedSwitcher` below) rather
/// than a hard swap; initial load uses skeleton cards; empty state uses
/// the illustrated system.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_semantic_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/list_stagger.dart';
import '../data/agency_models.dart' as models;
import '../data/agency_repository.dart';

enum _ScreenState { loading, loaded, empty, error, offline }

class LeadAnalyticsScreen extends StatefulWidget {
  const LeadAnalyticsScreen({
    super.key,
    required this.listingId,
    required this.repository,
    this.listingTitle,
  });

  final String listingId;
  final AgencyRepository repository;
  final String? listingTitle;

  @override
  State<LeadAnalyticsScreen> createState() => _LeadAnalyticsScreenState();
}

class _LeadAnalyticsScreenState extends State<LeadAnalyticsScreen> {
  _ScreenState _state = _ScreenState.loading;
  models.ListingAnalytics? _analytics;
  // screens.md Screen 16 Layout: segmented control default is 30 days.
  int _rangeDays = 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _ScreenState.loading);
    try {
      final analytics = await widget.repository.getListingAnalytics(
        listingId: widget.listingId,
        rangeDays: _rangeDays,
      );
      if (!mounted) return;
      setState(() {
        _analytics = analytics;
        _state = analytics.isEmpty ? _ScreenState.empty : _ScreenState.loaded;
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

  void _onRangeChanged(int rangeDays) {
    if (rangeDays == _rangeDays) return;
    setState(() => _rangeDays = rangeDays);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Performance'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Text(
              widget.listingTitle ?? 'Listing ${widget.listingId}',
              style: AppTypography.bodySmall.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildRangeSelector(),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildRangeSelector() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 7, label: Text('7d')),
          ButtonSegment(value: 30, label: Text('30d')),
          ButtonSegment(value: 90, label: Text('90d')),
        ],
        selected: {_rangeDays},
        onSelectionChanged: (selection) => _onRangeChanged(selection.first),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_state) {
      case _ScreenState.loading:
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: const [
            _SkeletonMetricCard(),
            SizedBox(height: AppSpacing.md),
            _SkeletonMetricCard(),
            SizedBox(height: AppSpacing.md),
            _SkeletonMetricCard(),
          ],
        );
      case _ScreenState.empty:
        return const EmptyStateView(
          title: 'Not enough activity yet to show analytics',
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
                  const Text("You're offline. Showing last known metrics."),
              actions: [
                TextButton(onPressed: _load, child: const Text('Retry'))
              ],
            ),
            if (_analytics != null)
              Expanded(child: _buildMetrics(context, _analytics!)),
          ],
        );
      case _ScreenState.loaded:
        return RefreshIndicator(
            onRefresh: _load, child: _buildMetrics(context, _analytics!));
    }
  }

  Widget _buildMetrics(
      BuildContext context, models.ListingAnalytics analytics) {
    final conversionPct =
        (analytics.inquiryToViewConversionRate * 100).toStringAsFixed(1);
    final cards = <_MetricCardData>[
      _MetricCardData('Views', '${analytics.viewCount}', isPrimary: true),
      _MetricCardData('Inquiries', '${analytics.inquiryCount}',
          isPrimary: true),
      _MetricCardData('Inquiry → View Conversion', '$conversionPct%'),
      _MetricCardData(
        'Avg. Response Time',
        analytics.averageResponseTimeMinutes != null
            ? '${analytics.averageResponseTimeMinutes!.toStringAsFixed(0)} min'
            : 'Not enough data yet',
      ),
      if (analytics.timeToCloseDays != null)
        _MetricCardData(
          'Time to Close',
          '${analytics.timeToCloseDays!.toStringAsFixed(1)} days'
              '${analytics.closedAt != null ? ' (closed ${analytics.closedAt!.toLocal().toString().split(' ').first})' : ''}',
        ),
    ];

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      child: ListView(
        key: ValueKey(_rangeDays),
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          for (var i = 0; i < cards.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child:
                  ListStaggerItem(index: i, child: _MetricCard(data: cards[i])),
            ),
        ],
      ),
    );
  }
}

class _MetricCardData {
  const _MetricCardData(this.label, this.value, {this.isPrimary = false});
  final String label;
  final String value;
  final bool isPrimary;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.data});
  final _MetricCardData data;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final shadows = Theme.of(context).extension<AppSemanticColors>()!;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: colorScheme.outline),
        boxShadow: shadows.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(data.value,
              style: data.isPrimary
                  ? AppTypography.statDisplay
                  : AppTypography.statSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(data.label,
              style: AppTypography.bodySmall
                  .copyWith(color: colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _SkeletonMetricCard extends StatelessWidget {
  const _SkeletonMetricCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 88,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
    );
  }
}
