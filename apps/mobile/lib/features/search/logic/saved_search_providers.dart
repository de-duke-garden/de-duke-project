/// Riverpod providers wiring Screen 20 (Saved Searches, FEAT-023) together.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/saved_search_models.dart';
import '../data/saved_search_repository.dart';
import 'search_providers.dart' show apiClientProvider;

final savedSearchRepositoryProvider = Provider<SavedSearchRepository>((ref) {
  return SavedSearchRepository(apiClient: ref.watch(apiClientProvider));
});

enum SavedSearchStatus { loading, loaded, empty, error }

class SavedSearchState {
  const SavedSearchState({
    this.status = SavedSearchStatus.loading,
    this.searches = const [],
    this.errorMessage,
    // IDs currently mid-toggle/mid-delete -- Screen 20's per-row inline
    // feedback (optimistic toggle, optimistic swipe-to-delete) needs to
    // know which specific row is in flight, not a single screen-wide flag.
    this.pendingIds = const {},
  });

  final SavedSearchStatus status;
  final List<SavedSearch> searches;
  final String? errorMessage;
  final Set<String> pendingIds;

  SavedSearchState copyWith({
    SavedSearchStatus? status,
    List<SavedSearch>? searches,
    String? errorMessage,
    bool clearError = false,
    Set<String>? pendingIds,
  }) {
    return SavedSearchState(
      status: status ?? this.status,
      searches: searches ?? this.searches,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      pendingIds: pendingIds ?? this.pendingIds,
    );
  }
}

class SavedSearchNotifier extends StateNotifier<SavedSearchState> {
  SavedSearchNotifier(this._repository) : super(const SavedSearchState());

  final SavedSearchRepository _repository;

  Future<void> load() async {
    state = state.copyWith(status: SavedSearchStatus.loading, clearError: true);
    try {
      final searches = await _repository.list();
      state = state.copyWith(
        status: searches.isEmpty
            ? SavedSearchStatus.empty
            : SavedSearchStatus.loaded,
        searches: searches,
      );
    } on DioException catch (e) {
      state = state.copyWith(
        status: SavedSearchStatus.error,
        errorMessage: e.message ?? 'Could not load your saved searches.',
      );
    }
  }

  /// Screen 20's alert `Switch` -- optimistic toggle, rolled back with an
  /// error toast on failure (screens.md Data Flow step 2).
  Future<bool> toggleAlerts(String id, bool enabled) async {
    final previous = state.searches;
    state = state.copyWith(
      searches: [
        for (final s in previous)
          if (s.id == id) s.copyWith(alertsEnabled: enabled) else s,
      ],
      pendingIds: {...state.pendingIds, id},
    );
    try {
      await _repository.setAlertsEnabled(id, enabled);
      state = state.copyWith(
        pendingIds: state.pendingIds.difference({id}),
      );
      return true;
    } on DioException {
      // Roll back to the pre-toggle list -- AGENTS.md Screen 20 Modernization
      // Notes: toggle failures must not silently stick.
      state = state.copyWith(
        searches: previous,
        pendingIds: state.pendingIds.difference({id}),
      );
      return false;
    }
  }

  /// Screen 20's swipe-to-delete -- optimistic removal, rolled back on
  /// failure per the "Deleting" state's own spec.
  Future<bool> delete(String id) async {
    final previous = state.searches;
    final remaining = previous.where((s) => s.id != id).toList();
    state = state.copyWith(
      searches: remaining,
      status: remaining.isEmpty ? SavedSearchStatus.empty : state.status,
      pendingIds: {...state.pendingIds, id},
    );
    try {
      await _repository.delete(id);
      state = state.copyWith(pendingIds: state.pendingIds.difference({id}));
      return true;
    } on DioException {
      state = state.copyWith(
        searches: previous,
        status: SavedSearchStatus.loaded,
        pendingIds: state.pendingIds.difference({id}),
      );
      return false;
    }
  }
}

final savedSearchNotifierProvider =
    StateNotifierProvider<SavedSearchNotifier, SavedSearchState>((ref) {
  return SavedSearchNotifier(ref.watch(savedSearchRepositoryProvider));
});
