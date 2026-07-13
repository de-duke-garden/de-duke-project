/// Data access for Saved Searches & Listing Alerts (FEAT-023) -- isolated
/// from UI/state per AGENTS.md ("Data access isolated into its own
/// package/module"). Backend routes: GET/POST /v1/searches/saved,
/// PATCH/DELETE /v1/searches/saved/:id (app/api/v1/saved_searches.py).
library;

import '../../../core/api/api_client.dart';
import 'saved_search_models.dart';
import 'search_models.dart';

class SavedSearchRepository {
  SavedSearchRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<SavedSearch>> list() async {
    final response =
        await _apiClient.dio.get<Map<String, dynamic>>('/v1/searches/saved');
    final results = response.data!['results'] as List;
    return results
        .map((e) => SavedSearch.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Persists the current Search Results filter set (Screen 5's "Save this
  /// search" exit point) or a search authored directly from Screen 20.
  Future<SavedSearch> create({
    required String label,
    required SearchQueryState query,
  }) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/v1/searches/saved',
      data: {
        'label': label,
        // location_query is free text server-side (no geocoding wired up
        // yet -- see saved_search_service.py's module docstring); the
        // search query's own keyword/location text field is the closest
        // available stand-in until a geocoded address is captured here.
        'location_query': query.query?.isNotEmpty == true
            ? query.query
            : 'Current search area',
        'radius_km': query.radiusKm,
        if (query.listingType != null)
          'listing_type': query.listingType!.apiValue,
        if (query.minPrice != null) 'min_price': query.minPrice,
        if (query.maxPrice != null) 'max_price': query.maxPrice,
        'verified_only': query.verifiedOnly,
        'alerts_enabled': true,
      },
    );
    return SavedSearch.fromJson(response.data!);
  }

  Future<SavedSearch> setAlertsEnabled(String id, bool enabled) async {
    final response = await _apiClient.dio.patch<Map<String, dynamic>>(
      '/v1/searches/saved/$id',
      data: {'alerts_enabled': enabled},
    );
    return SavedSearch.fromJson(response.data!);
  }

  Future<void> delete(String id) async {
    await _apiClient.dio.delete<void>('/v1/searches/saved/$id');
  }
}
