/// Data access for Search & Discovery -- isolated from UI/state per
/// AGENTS.md ("Data access isolated into its own package/module").
library;

import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import 'search_models.dart';

class SearchRepository {
  SearchRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  /// Calls GET /v1/search/listings. Throws [DioException] on network/HTTP
  /// failure -- callers (SearchNotifier) translate that into the screen's
  /// Error/Offline states rather than swallowing it here.
  Future<SearchResultsPage> search(
    SearchQueryState filters, {
    String? cursor,
    int pageSize = 20,
  }) async {
    final params = filters.toQueryParameters();
    if (cursor != null) params['cursor'] = cursor;
    params['page_size'] = pageSize;

    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/v1/search/listings',
      queryParameters: params,
    );
    return SearchResultsPage.fromJson(response.data!);
  }
}
