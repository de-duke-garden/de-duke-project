/// Screen 5: Search Results (screens.md) -- FEAT-006/FEAT-007/FEAT-031.
/// Route: /search (registered additively in core/routing/app_router.dart).
library;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../data/search_models.dart';
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
              backgroundColor: AppColors.primary,
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
      chips.add(_chip(
          q.listingType!.apiValue,
          () =>
              notifier.updateQuery((s) => s.copyWith(clearListingType: true))));
    }
    if (q.dealType != null) {
      chips.add(_chip(q.dealType!.apiValue,
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

  Widget _chip(String label, VoidCallback onDeleted) {
    return Chip(
        label: Text(label),
        onDeleted: onDeleted,
        deleteIconColor: AppColors.textSecondary);
  }

  Widget _buildBody(SearchState state, bool isOffline) {
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
                onMarkerTap: (id) => context.push('/listing/$id'),
                onSearchThisArea: (lat, lng) => ref
                    .read(searchNotifierProvider.notifier)
                    .setLocation(latitude: lat, longitude: lng),
              );
    }
  }

  Widget _buildResultsList(SearchState state,
      {required bool showOfflineDisabled}) {
    return RefreshIndicator(
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
          return ListingResultCard(
            result: result,
            onTap: showOfflineDisabled
                ? () {}
                : () => context.push('/listing/${result.id}'),
          );
        },
      ),
    );
  }

  Widget _buildSkeletonList() {
    return ListView.builder(
      itemCount: 4,
      itemBuilder: (context, index) => Container(
        margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        height: 220,
        decoration: BoxDecoration(
          color: AppColors.surfaceSecondary,
          borderRadius: BorderRadius.circular(AppSpacing.sm),
        ),
      ),
    );
  }

  void _saveSearch(BuildContext context) {
    // POST /v1/searches/saved -- FEAT-023 (Saved Searches), out of this
    // feature's owned scope (see features.md FEAT-023, owned elsewhere);
    // wiring the button here since Screen 5 specifies it, but the endpoint
    // itself is not part of FEAT-006/007/031.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text(
              'Saved search (FEAT-023) -- not yet wired to a backend endpoint.')),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.warning,
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
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off, size: 48, color: AppColors.textSecondary),
            SizedBox(height: AppSpacing.md),
            Text(
              "You're offline and there are no cached results to show yet.",
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off,
                size: 48, color: AppColors.textSecondary),
            const SizedBox(height: AppSpacing.md),
            const Text('No listings match your filters',
                textAlign: TextAlign.center),
            if (hasActiveFilters) ...[
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Tip: try toggling off "Verified Host only" or widening your price range.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: AppSpacing.md),
              TextButton(
                  onPressed: onClearFilters,
                  child: const Text('Clear filters')),
            ],
          ],
        ),
      ),
    );
  }
}
