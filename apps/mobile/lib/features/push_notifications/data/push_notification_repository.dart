/// Repository wrapping the Backend API Service's /v1/notifications
/// endpoints (FEAT-022). Screens/services depend on this, never on Dio
/// directly.
library;

import 'dart:io' show Platform;

import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';

class PushNotificationException implements Exception {
  PushNotificationException(this.message);
  final String message;

  @override
  String toString() => message;
}

class PushNotificationRepository {
  PushNotificationRepository(this._apiClient);

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

  /// POST /v1/notifications/push-token. `platform` matches
  /// app/models/push_token.py's ios|android values -- web isn't a target
  /// platform for this app, so no third branch.
  Future<void> registerToken(String token) async {
    try {
      await _apiClient.dio.post(
        '/v1/notifications/push-token',
        data: {
          'token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
        },
      );
    } on DioException catch (e) {
      throw PushNotificationException(_errorMessage(e, 'Could not register for push notifications.'));
    }
  }

  Future<Map<String, bool>> getPreferences() async {
    try {
      final response = await _apiClient.dio.get('/v1/notifications/preferences');
      final body = response.data as Map<String, dynamic>;
      return Map<String, bool>.from(body['push_notification_preferences'] as Map);
    } on DioException catch (e) {
      throw PushNotificationException(_errorMessage(e, 'Could not load notification preferences.'));
    }
  }

  /// Partial update -- only the categories present in `updates` are
  /// changed, mirroring the backend's own partial-update contract
  /// (UpdatePushNotificationPreferencesRequest).
  Future<Map<String, bool>> updatePreferences(Map<String, bool> updates) async {
    try {
      final response =
          await _apiClient.dio.patch('/v1/notifications/preferences', data: updates);
      final body = response.data as Map<String, dynamic>;
      return Map<String, bool>.from(body['push_notification_preferences'] as Map);
    } on DioException catch (e) {
      throw PushNotificationException(_errorMessage(e, 'Could not update notification preferences.'));
    }
  }
}
