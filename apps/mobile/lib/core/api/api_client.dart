/// Shared HTTP client for the Backend API Service -- every /v1 endpoint call
/// goes through this Dio instance so auth headers, base URL, and error
/// handling stay consistent across all feature modules.
import 'package:dio/dio.dart';

import '../auth/session_store.dart';

class ApiClient {
  ApiClient({required String baseUrl, required SessionStore sessionStore})
      : _sessionStore = sessionStore,
        _dio = Dio(BaseOptions(baseUrl: baseUrl, connectTimeout: const Duration(seconds: 10))) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _sessionStore.readAccessToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;
  final SessionStore _sessionStore;

  Dio get dio => _dio;
}
