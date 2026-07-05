/// Riverpod providers wiring the Search feature together. Kept as plain
/// (non-autoDispose) providers so [SearchNotifier]'s query/filter state
/// survives pushing to Listing Detail and popping back (FEAT-007: "Filter
/// state persists when navigating back from a listing detail screen").
library;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/session_store.dart';
import '../../../core/config/env.dart';
import '../data/search_models.dart';
import '../data/search_repository.dart';

/// TODO(shared core): replace with the app-wide ApiClient/base-URL provider
/// once one exists in core/ -- duplicated minimally here so this feature
/// slice is runnable standalone without editing shared files. Uses the
/// same AppConfig.apiBaseUrl as the rest of the app so the search feature
/// never silently points at a different backend host.
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    baseUrl: AppConfig.apiBaseUrl,
    sessionStore: SessionStore(),
  );
});

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return SearchRepository(apiClient: ref.watch(apiClientProvider));
});

final connectivityStreamProvider = StreamProvider<List<ConnectivityResult>>((ref) {
  return Connectivity().onConnectivityChanged;
});

enum SearchViewMode { list, map }

enum SearchStatus { initial, loading, loaded, empty, error, offline, loadingMore }

class SearchState {
  const SearchState({
    required this.query,
    this.status = SearchStatus.initial,
    this.results = const [],
    this.nextCursor,
    this.hasMore = false,
    this.errorMessage,
    this.viewMode = SearchViewMode.list,
  });

  final SearchQueryState query;
  final SearchStatus status;
  final List<ListingSearchResult> results;
  final String? nextCursor;
  final bool hasMore;
  final String? errorMessage;
  final SearchViewMode viewMode;

  SearchState copyWith({
    SearchQueryState? query,
    SearchStatus? status,
    List<ListingSearchResult>? results,
    String? nextCursor,
    bool clearCursor = false,
    bool? hasMore,
    String? errorMessage,
    bool clearError = false,
    SearchViewMode? viewMode,
  }) {
    return SearchState(
      query: query ?? this.query,
      status: status ?? this.status,
      results: results ?? this.results,
      nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
      hasMore: hasMore ?? this.hasMore,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      viewMode: viewMode ?? this.viewMode,
    );
  }
}

class SearchNotifier extends StateNotifier<SearchState> {
  SearchNotifier(this._repository) : super(const SearchState(query: SearchQueryState()));

  final SearchRepository _repository;

  Future<void> search({bool isOffline = false}) async {
    if (isOffline) {
      state = state.copyWith(status: SearchStatus.offline);
      return;
    }
    state = state.copyWith(status: SearchStatus.loading, clearError: true);
    try {
      final page = await _repository.search(state.query);
      state = state.copyWith(
        status: page.results.isEmpty ? SearchStatus.empty : SearchStatus.loaded,
        results: page.results,
        nextCursor: page.nextCursor,
        clearCursor: page.nextCursor == null,
        hasMore: page.hasMore,
      );
    } on DioException catch (e) {
      state = state.copyWith(
        status: SearchStatus.error,
        errorMessage: e.message ?? 'Something went wrong loading search results.',
      );
    }
  }

  Future<void> loadMore() async {
    if (!state.hasMore || state.status == SearchStatus.loadingMore) return;
    state = state.copyWith(status: SearchStatus.loadingMore);
    try {
      final page = await _repository.search(state.query, cursor: state.nextCursor);
      state = state.copyWith(
        status: SearchStatus.loaded,
        results: [...state.results, ...page.results],
        nextCursor: page.nextCursor,
        clearCursor: page.nextCursor == null,
        hasMore: page.hasMore,
      );
    } on DioException catch (e) {
      // Loading-more failures don't blow away already-loaded results --
      // surface as a transient state but keep the existing list visible.
      state = state.copyWith(status: SearchStatus.loaded, errorMessage: e.message);
    }
  }

  void updateQuery(SearchQueryState Function(SearchQueryState) update) {
    state = state.copyWith(query: update(state.query));
    search();
  }

  void setLocation({required double latitude, required double longitude}) {
    state = state.copyWith(query: state.query.copyWith(latitude: latitude, longitude: longitude));
    search();
  }

  void clearFilters() {
    state = state.copyWith(query: state.query.clearAllFilters());
    search();
  }

  void toggleViewMode() {
    state = state.copyWith(
      viewMode: state.viewMode == SearchViewMode.list ? SearchViewMode.map : SearchViewMode.list,
    );
  }
}

final searchNotifierProvider = StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  return SearchNotifier(ref.watch(searchRepositoryProvider));
});
