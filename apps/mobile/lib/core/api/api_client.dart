/// Shared HTTP client for the Backend API Service -- every /v1 endpoint call
/// goes through this Dio instance so auth headers, base URL, and error
/// handling stay consistent across all feature modules.
///
/// FEAT-001 AC "User can log in and stay logged in across app restarts":
/// the access token used here is short-lived by design (see
/// app/schemas/auth.py's AuthTokenResponse docstring), so a session that's
/// merely old -- not actually logged out -- would otherwise start failing
/// requests with 401s the moment the access token expires, mid-session,
/// forcing a re-login the docs never call for. This client transparently
/// exchanges the stored refresh token for a new pair via `POST
/// /v1/auth/refresh` and retries the failed request once, so an expiring
/// access token is invisible to both the caller and the user.
import 'package:dio/dio.dart';

import '../auth/session_store.dart';

class ApiClient {
  ApiClient({required String baseUrl, required SessionStore sessionStore})
      : _sessionStore = sessionStore,
        _dio = Dio(BaseOptions(
            baseUrl: baseUrl, connectTimeout: const Duration(seconds: 10))) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _sessionStore.readAccessToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final requestOptions = error.requestOptions;
          final isAuthEndpoint = requestOptions.path.contains('/v1/auth/');
          final alreadyRetried = requestOptions.extra['retriedAfterRefresh'] == true;
          if (error.response?.statusCode != 401 ||
              isAuthEndpoint ||
              alreadyRetried) {
            handler.next(error);
            return;
          }
          final refreshed = await _refreshAccessToken();
          if (!refreshed) {
            handler.next(error);
            return;
          }
          try {
            final retryResponse = await _retry(requestOptions);
            handler.resolve(retryResponse);
          } on DioException catch (retryError) {
            handler.next(retryError);
          }
        },
      ),
    );
  }

  final Dio _dio;
  final SessionStore _sessionStore;

  // Coalesces concurrent 401s (e.g. several in-flight requests all hitting
  // an expired access token at once) into a single refresh call rather than
  // racing multiple `/v1/auth/refresh` requests against the same refresh
  // token.
  Future<bool>? _refreshInFlight;

  Dio get dio => _dio;

  Future<bool> _refreshAccessToken() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<bool> _doRefresh() async {
    final refreshToken = await _sessionStore.readRefreshToken();
    if (refreshToken == null) return false;
    try {
      // Deliberately a bare Dio, not `_dio` -- going through `_dio` would
      // re-enter this same onError interceptor (and re-attach a now-stale
      // Authorization header via onRequest) for what must be an
      // unauthenticated call.
      final response = await Dio(BaseOptions(
        baseUrl: _dio.options.baseUrl,
        connectTimeout: const Duration(seconds: 10),
      )).post('/v1/auth/refresh', data: {'refresh_token': refreshToken});
      final body = response.data as Map<String, dynamic>;
      await _sessionStore.saveAccessToken(body['access_token'] as String);
      await _sessionStore.saveRefreshToken(body['refresh_token'] as String);
      return true;
    } on DioException {
      // Refresh token itself is invalid/expired/revoked -- this is a real
      // logout, not a transient failure, so the stale session is cleared
      // rather than left around to fail every subsequent request the same
      // way.
      await _sessionStore.clear();
      return false;
    }
  }

  Future<Response<dynamic>> _retry(RequestOptions requestOptions) {
    // Rebuilds headers without the stale `Authorization` value so the
    // onRequest interceptor re-attaches the freshly refreshed token instead
    // of silently reusing the one that just got this request 401'd.
    final headers = Map<String, dynamic>.from(requestOptions.headers)
      ..remove('Authorization');
    return _dio.request<dynamic>(
      requestOptions.path,
      data: requestOptions.data,
      queryParameters: requestOptions.queryParameters,
      options: Options(
        method: requestOptions.method,
        headers: headers,
        contentType: requestOptions.contentType,
        extra: {...requestOptions.extra, 'retriedAfterRefresh': true},
        responseType: requestOptions.responseType,
      ),
    );
  }
}
