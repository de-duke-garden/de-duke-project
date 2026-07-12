/// Repository wrapping GET /v1/host/listings (FEAT-017). Screens depend
/// on this, never on Dio directly.
library;

import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import 'host_dashboard_models.dart';

class HostDashboardException implements Exception {
  HostDashboardException(this.message);
  final String message;

  @override
  String toString() => message;
}

class HostDashboardRepository {
  HostDashboardRepository(this._apiClient);

  final ApiClient _apiClient;

  String _errorMessage(DioException e, String fallback) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return 'offline';
    }
    final data = e.response?.data;
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
    return fallback;
  }

  Future<List<HostDashboardListingItem>> getMyListings() async {
    try {
      final response = await _apiClient.dio.get('/v1/host/listings');
      final body = response.data as Map<String, dynamic>;
      return (body['items'] as List)
          .map((e) => HostDashboardListingItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw HostDashboardException(_errorMessage(e, 'Could not load your listings.'));
    }
  }
}
