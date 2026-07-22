/// Screen 5: Search Results (screens.md) -- FEAT-006/FEAT-007/FEAT-031.
/// Route: /search (registered additively in core/routing/app_router.dart).
library;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_names.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/badge_pop.dart';
import '../../../core/widgets/branded_refresh_indicator.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/list_stagger.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../data/search_models.dart';
import '../logic/saved_search_providers.dart';
import '../logic/search_providers.dart';
import 'filter_sheet.dart';
import 'listing_result_card.dart';
import 'search_map_view.dart';

class SearchResultsScreen extends ConsumerStatefulWidget {
  const SearchResultsScreen({super.key, this.initialQuery});

  /// Optional keyword the caller (e.g. Home Feed's search entry field)
  /// arrived with -- screens.md Data Flow step 1.
  final String? initialQuery;

  @override
  ConsumerState<SearchResultsScreen> createState() =>
      _SearchResultsScreenState();
}

class _SearchResultsScreenState extends ConsumerState<SearchResultsScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.initialQuery ?? '';
    _scrollController.addListener(_onScroll);
    // Defer initial fetch until first frame so `ref` is safe to use.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = ref.read(searchNotifierProvider.notifier);
      if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
        notifier.updateQuery((q) => q.copyWith(query: widget.initialQuery));
      } else if (ref.read(searchNotifierProvider).status ==
          SearchStatus.initial) {
        notifier.search();
      }
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(searchNotifierProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchNotifierProvider);
    final connectivity = ref.watch(connectivityStreamProvider);
    final isOffline = connectivity.maybeWhen(
      data: (results) => results.every((r) => r == ConnectivityResult.none),
      orElse: () => false,
    );

    ref.listen(connectivityStreamProvider, (previous, next) {
      next.whenData((results) {
        final offline = results.every((r) => r == ConnectivityResult.none);
        if (offline) {
          ref.read(searchNotifierProvider.notifier).search(isOffline: true);
        } else if (state.status == SearchStatus.offline) {
          ref.read(searchNotifierProvider.notifier).search();
        }
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            hintText: 'Search by location or keyword',
            border: InputBorder.none,
          ),
          onSubmitted: (value) {
            ref.read(searchNotifierProvider.notifier).updateQuery(
                  (q) => q.copyWith(query: value, clearQuery: value.isEmpty),
                );
          },
        ),
        actions: [
          IconButton(
            icon: Badge(
              label: Text('${state.query.activeFilterCount}'),
              isLabelVisible: state.query.activeFilterCount > 0,
              child: const Icon(Icons.filter_list),
            ),
            tooltip: 'Filters',
            onPressed: isOffline
                ? null
                : () => showSearchFilterSheet(
                      context: context,
                      current: state.query,
                      onApply: (updated) => ref
                          .read(searchNotifierProvider.notifier)
                          .updateQuery((_) => updated),
                    ),
          ),
          // FEAT-023 exit point: Search Results -> Saved Searches.
          IconButton(
            icon: const Icon(Icons.bookmarks_outlined),
            tooltip: 'Saved Searches',
            onPressed: () => context.pushNamed(RouteNames.savedSearches),
          ),
        ],
      ),
      body: Column(
        children: [
          if (isOffline) const _OfflineBanner(),
          _buildViewToggle(state),
          if (state.query.activeFilterCount > 0) _buildActiveFilterChips(state),
          Expanded(child: _buildBody(state, isOffline)),
        ],
      ),
      floatingActionButton: state.status == SearchStatus.loaded
          ? FloatingActionButton.extended(
              onPressed: () => _saveSearch(context),
              backgroundColor: Theme.of(context).colorScheme.primary,
              icon:
                  const Icon(Icons.bookmark_add_outlined, color: Colors.white),
              label: const Text('Save this search',
                  style: TextStyle(color: Colors.white)),
            )
          : null,
    );
  }

  Widget _buildViewToggle(SearchState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: SegmentedButton<SearchViewMode>(
        segments: const [
          ButtonSegment(
              value: SearchViewMode.list,
              label: Text('List'),
              icon: Icon(Icons.list)),
          ButtonSegment(
              value: SearchViewMode.map,
              label: Text('Map'),
              icon: Icon(Icons.map_outlined)),
        ],
        selected: {state.viewMode},
        onSelectionChanged: (_) =>
            ref.read(searchNotifierProvider.notifier).toggleViewMode(),
      ),
    );
  }

  Widget _buildActiveFilterChips(SearchState state) {
    final chips = <Widget>[];
    final q = state.query;
    final notifier = ref.read(searchNotifierProvider.notifier);

    if (q.listingType != null) {
      // Was `.apiValue` (raw wire value, e.g. 'commercial') -- chip now
      // shows the normalized `.label` ('Commercial') like every other
      // filter chip here.
      chips.add(_chip(q.listingType!.label,
          () =>
              notifier.updateQuery((s) => s.copyWith(clearListingType: true))));
    }
    if (q.dealType != null) {
      chips.add(_chip(q.dealType!.label,
          () => notifier.updateQuery((s) => s.copyWith(clearDealType: true))));
    }
    if (q.verifiedOnly) {
      chips.add(_chip('Verified Host',
          () => notifier.updateQuery((s) => s.copyWith(verifiedOnly: false))));
    }
    if (q.minPrice != null || q.maxPrice != null) {
      chips.add(_chip(
        'Price',
        () => notifier.updateQuery(
            (s) => s.copyWith(clearMinPrice: true, clearMaxPrice: true)),
      ));
    }
    if (q.bathrooms != null) {
      chips.add(_chip('${q.bathrooms}+ bath',
          () => notifier.updateQuery((s) => s.copyWith(clearBathrooms: true))));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Wrap(spacing: AppSpacing.xs, children: chips),
    );
  }

  // `badge-pop` when a filter chip appears (branding.md Modernization
  // Notes for Screen 5) -- keyed by label so a freshly-added chip pops in.
  Widget _chip(String label, VoidCallback onDeleted) {
    return BadgePop(
      triggerKey: label,
      child: Chip(
          label: Text(label),
          onDeleted: onDeleted,
          deleteIconColor: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }

  Widget _buildBody(SearchState state, bool isOffline) {
    // Screen 5 Modernization Notes: map/list toggle crossfades at
    // `duration-fast` rather than an abrupt switch.
    return AnimatedSwitcher(
      duration: AppDurations.fast,
      switchInCurve: AppCurves.easeOutSmooth,
      switchOutCurve: AppCurves.easeOutSmooth,
      child: KeyedSubtree(
        key: ValueKey(_bodyKeyFor(state)),
        child: _buildBodyContent(state, isOffline),
      ),
    );
  }

  String _bodyKeyFor(SearchState state) {
    if (state.status == SearchStatus.loaded ||
        state.status == SearchStatus.loadingMore) {
      return 'loaded-${state.viewMode}';
    }
    return state.status.name;
  }

  Widget _buildBodyContent(SearchState state, bool isOffline) {
    switch (state.status) {
      case SearchStatus.initial:
      case SearchStatus.loading:
        return _buildSkeletonList();
      case SearchStatus.offline:
        return state.results.isEmpty
            ? const _EmptyOfflineNoCache()
            : _buildResultsList(state, showOfflineDisabled: true);
      case SearchStatus.error:
        return _ErrorState(
          message: state.errorMessage ?? 'Something went wrong.',
          onRetry: () => ref.read(searchNotifierProvider.notifier).search(),
        );
      case SearchStatus.empty:
        return _EmptyState(
          hasActiveFilters: state.query.activeFilterCount > 0,
          onClearFilters: () =>
              ref.read(searchNotifierProvider.notifier).clearFilters(),
        );
      case SearchStatus.loaded:
      case SearchStatus.loadingMore:
        return state.viewMode == SearchViewMode.list
            ? _buildResultsList(state, showOfflineDisabled: false)
            : SearchMapView(
                results: state.results,
                onMarkerTap: (id) => context.pushNamed(
                  RouteNames.listingDetail,
                  pathParameters: {'id': id},
                ),
                onSearchThisArea: (lat, lng) => ref
                    .read(searchNotifierProvider.notifier)
                    .setLocation(latitude: lat, longitude: lng),
              );
    }
  }

  Widget _buildResultsList(SearchState state,
      {required bool showOfflineDisabled}) {
    return BrandedRefreshIndicator(
      onRefresh: () => ref.read(searchNotifierProvider.notifier).search(),
      child: ListView.builder(
        controller: _scrollController,
        itemCount: state.results.length +
            (state.status == SearchStatus.loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.results.length) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final result = state.results[index];
          // `list-stagger` on initial fetch/filter change (branding.md
          // Modernization Notes) -- ListStaggerItem self-limits its
          // one-shot entrance animation per mount, so re-using it here on
          // every build is safe (it doesn't replay on scroll/rebuild,
          // only on first mount of that list position).
          return ListStaggerItem(
            index: index,
            child: ListingResultCard(
              result: result,
              onTap: showOfflineDisabled
                  ? () {}
                  : () => context.pushNamed(
                      RouteNames.listingDetail,
                      pathParameters: {'id': result.id},
                    ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSkeletonList() {
    return ListView.builder(
      itemCount: 4,
      itemBuilder: (context, index) => const SkeletonListingCard(),
    );
  }

  Future<void> _saveSearch(BuildContext context) async {
    // Screen 5's "Save this search" exit point -- POST /v1/searches/saved
    // (FEAT-023). Prompts for a label (Screen 20's saved search rows are
    // labeled, e.g. "3-bed shortlets in Lekki"), then persists the
    // current filter/query state.
    final label = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _SaveSearchDialog(
        suggestedLabel: _searchController.text.isNotEmpty
            ? _searchController.text
            : 'My saved search',
      ),
    );
    if (label == null || label.trim().isEmpty || !context.mounted) return;

    final query = ref.read(searchNotifierProvider).query;
    try {
      await ref
          .read(savedSearchRepositoryProvider)
          .create(label: label.trim(), query: query);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Search saved. You\'ll be alerted to new matches.'),
          action: SnackBarAction(
            label: 'View',
            onPressed: () => context.pushNamed(RouteNames.savedSearches),
          ),
        ),
      );
    } on DioException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't save this search. Please try again.")),
      );
    }
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).extension<AppSemanticColors>()!.warning,
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm, horizontal: AppSpacing.md),
      child: const Row(
        children: [
          Icon(Icons.wifi_off, color: Colors.white, size: 18),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              "You're offline. Showing last cached results. Filters disabled until reconnected.",
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyOfflineNoCache extends StatelessWidget {
  const _EmptyOfflineNoCache();

  @override
  Widget build(BuildContext context) {
    return const EmptyStateView(
      isError: true,
      title: "You're offline",
      message: 'There are no cached results to show yet.',
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyStateView(
      isError: true,
      title: 'Something went wrong',
      message: message,
      actionLabel: 'Retry',
      onAction: onRetry,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(
      {required this.hasActiveFilters, required this.onClearFilters});

  final bool hasActiveFilters;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    return EmptyStateView(
      title: 'No listings match your filters',
      message: hasActiveFilters
          ? 'Tip: try toggling off "Verified Host only" or widening your price range.'
          : null,
      actionLabel: hasActiveFilters ? 'Clear filters' : null,
      onAction: hasActiveFilters ? onClearFilters : null,
    );
  }
}

/// Prompts for a label when saving the current search (FEAT-023) --
/// Screen 20's rows are labeled (e.g. "3-bed shortlets in Lekki"), so the
/// save action collects one rather than auto-generating an opaque name.
class _SaveSearchDialog extends StatefulWidget {
  const _SaveSearchDialog({required this.suggestedLabel});

  final String suggestedLabel;

  @override
  State<_SaveSearchDialog> createState() => _SaveSearchDialogState();
}

class _SaveSearchDialogState extends State<_SaveSearchDialog> {
  late final _controller = TextEditingController(text: widget.suggestedLabel);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save this search'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Label'),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
