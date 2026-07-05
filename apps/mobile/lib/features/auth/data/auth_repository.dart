/// Repository wrapping the Backend API Service's /v1/auth endpoints
/// (FEAT-001). Screens depend on this, never on Dio/ApiClient directly.
library;

import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/session_store.dart';

class AuthResult {
  const AuthResult({
    required this.userId,
    required this.role,
    required this.isVerifiedHost,
  });

  final String userId;
  final String role;
  final bool isVerifiedHost;
}

/// Thrown for any auth failure the UI needs to react to with a specific,
/// user-facing message (FEAT-001 AC: "Invalid credentials show a clear,
/// specific error message") -- never a generic "something went wrong".
class AuthException implements Exception {
  AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AuthRepository {
  AuthRepository(this._apiClient, this._sessionStore);

  final ApiClient _apiClient;
  final SessionStore _sessionStore;

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

  Future<void> _persistSession(Map<String, dynamic> body) async {
    await _sessionStore.saveAccessToken(body['access_token'] as String);
  }

  Future<AuthResult> registerWithEmail({
    required String fullName,
    required String email,
    required String password,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/v1/auth/register',
        data: {'full_name': fullName, 'email': email, 'password': password},
      );
      final body = response.data as Map<String, dynamic>;
      await _persistSession(body);
      return AuthResult(
        userId: body['user_id'] as String,
        role: body['role'] as String,
        isVerifiedHost: body['is_verified_host'] as bool,
      );
    } on DioException catch (e) {
      throw AuthException(_errorMessage(e, 'Could not create your account. Please try again.'));
    }
  }

  Future<void> requestPhoneSignupOtp({required String fullName, required String phoneNumber}) async {
    try {
      await _apiClient.dio.post(
        '/v1/auth/register/phone/request-otp',
        data: {'full_name': fullName, 'phone_number': phoneNumber},
      );
    } on DioException catch (e) {
      throw AuthException(_errorMessage(e, 'Could not send a code to that number.'));
    }
  }

  Future<AuthResult> verifyPhoneSignupOtp({required String phoneNumber, required String otpCode}) async {
    try {
      final response = await _apiClient.dio.post(
        '/v1/auth/register/phone/verify-otp',
        data: {'phone_number': phoneNumber, 'otp_code': otpCode},
      );
      final body = response.data as Map<String, dynamic>;
      await _persistSession(body);
      return AuthResult(
        userId: body['user_id'] as String,
        role: body['role'] as String,
        isVerifiedHost: body['is_verified_host'] as bool,
      );
    } on DioException catch (e) {
      throw AuthException(_errorMessage(e, 'otp_expired'));
    }
  }

  Future<AuthResult> loginWithEmail({required String email, required String password}) async {
    try {
      final response = await _apiClient.dio.post(
        '/v1/auth/login',
        data: {'email': email, 'password': password},
      );
      final body = response.data as Map<String, dynamic>;
      await _persistSession(body);
      return AuthResult(
        userId: body['user_id'] as String,
        role: body['role'] as String,
        isVerifiedHost: body['is_verified_host'] as bool,
      );
    } on DioException catch (e) {
      throw AuthException(
        _errorMessage(e, "We couldn't verify those details. Try again or reset your password."),
      );
    }
  }

  Future<void> requestLoginOtp({required String phoneNumber}) async {
    try {
      await _apiClient.dio.post(
        '/v1/auth/login/phone/request-otp',
        queryParameters: {'phone_number': phoneNumber},
      );
    } on DioException catch (e) {
      throw AuthException(_errorMessage(e, 'Could not send a code to that number.'));
    }
  }

  Future<AuthResult> loginWithPhoneOtp({required String phoneNumber, required String otpCode}) async {
    try {
      final response = await _apiClient.dio.post(
        '/v1/auth/login',
        data: {'phone_number': phoneNumber, 'otp_code': otpCode},
      );
      final body = response.data as Map<String, dynamic>;
      await _persistSession(body);
      return AuthResult(
        userId: body['user_id'] as String,
        role: body['role'] as String,
        isVerifiedHost: body['is_verified_host'] as bool,
      );
    } on DioException catch (e) {
      throw AuthException(_errorMessage(e, 'otp_expired'));
    }
  }

  Future<void> requestPasswordReset({required String email}) async {
    try {
      await _apiClient.dio.post('/v1/auth/forgot-password', data: {'email': email});
    } on DioException catch (e) {
      throw AuthException(_errorMessage(e, 'Could not process that request.'));
    }
  }

  Future<void> resetPassword({required String resetToken, required String newPassword}) async {
    try {
      await _apiClient.dio.post(
        '/v1/auth/reset-password',
        data: {'reset_token': resetToken, 'new_password': newPassword},
      );
    } on DioException catch (e) {
      throw AuthException(_errorMessage(e, 'Could not reset your password. The link may have expired.'));
    }
  }

  Future<void> logout() => _sessionStore.clear();
}
