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

/// GET /v1/auth/me -- current user's identity, for screens (e.g. Account
/// Settings) that need to display profile info without a dedicated
/// GET /user/profile endpoint (not yet built).
class CurrentUser {
  const CurrentUser({
    required this.userId,
    required this.role,
    required this.fullName,
    required this.email,
    required this.phoneNumber,
    required this.isVerifiedHost,
    required this.isActive,
  });

  final String userId;
  final String role;
  final String fullName;
  final String? email;
  final String? phoneNumber;
  final bool isVerifiedHost;
  final bool isActive;

  factory CurrentUser.fromJson(Map<String, dynamic> json) => CurrentUser(
        userId: json['user_id'] as String,
        role: json['role'] as String,
        fullName: json['full_name'] as String,
        email: json['email'] as String?,
        phoneNumber: json['phone_number'] as String?,
        isVerifiedHost: json['is_verified_host'] as bool,
        isActive: json['is_active'] as bool,
      );
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
    await _sessionStore.saveRefreshToken(body['refresh_token'] as String);
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
      throw AuthException(
          _errorMessage(e, 'Could not create your account. Please try again.'));
    }
  }

  Future<void> requestPhoneSignupOtp(
      {required String fullName, required String phoneNumber}) async {
    try {
      await _apiClient.dio.post(
        '/v1/auth/register/phone/request-otp',
        data: {'full_name': fullName, 'phone_number': phoneNumber},
      );
    } on DioException catch (e) {
      throw AuthException(
          _errorMessage(e, 'Could not send a code to that number.'));
    }
  }

  Future<AuthResult> verifyPhoneSignupOtp(
      {required String phoneNumber, required String otpCode}) async {
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

  Future<AuthResult> loginWithEmail(
      {required String email, required String password}) async {
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
        _errorMessage(e,
            "We couldn't verify those details. Try again or reset your password."),
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
      throw AuthException(
          _errorMessage(e, 'Could not send a code to that number.'));
    }
  }

  Future<AuthResult> loginWithPhoneOtp(
      {required String phoneNumber, required String otpCode}) async {
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
      await _apiClient.dio
          .post('/v1/auth/forgot-password', data: {'email': email});
    } on DioException catch (e) {
      throw AuthException(_errorMessage(e, 'Could not process that request.'));
    }
  }

  Future<void> resetPassword(
      {required String resetToken, required String newPassword}) async {
    try {
      await _apiClient.dio.post(
        '/v1/auth/reset-password',
        data: {'reset_token': resetToken, 'new_password': newPassword},
      );
    } on DioException catch (e) {
      throw AuthException(_errorMessage(
          e, 'Could not reset your password. The link may have expired.'));
    }
  }

  /// FEAT-012's Agency Team invite AC ("the invitee sets their own
  /// password"): an invited team member pastes the userId + invite token
  /// from their invite email/link (see AcceptInviteScreen) and chooses a
  /// real password here. Returns a full session -- same shape as
  /// register/login -- so the invitee lands signed-in immediately.
  Future<AuthResult> acceptInvite({
    required String userId,
    required String inviteToken,
    required String newPassword,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/v1/auth/accept-invite',
        data: {
          'user_id': userId,
          'invite_token': inviteToken,
          'new_password': newPassword,
        },
      );
      final body = response.data as Map<String, dynamic>;
      await _persistSession(body);
      return AuthResult(
        userId: body['user_id'] as String,
        role: body['role'] as String,
        isVerifiedHost: body['is_verified_host'] as bool,
      );
    } on DioException catch (e) {
      throw AuthException(_errorMessage(
          e, 'This invite link is invalid or has already been used.'));
    }
  }

  /// Revokes the refresh token server-side (best-effort -- proceeds to
  /// clear local session even if the network call fails, since the user
  /// must always be able to log out locally regardless of connectivity).
  Future<CurrentUser> getCurrentUser() async {
    try {
      final response = await _apiClient.dio.get('/v1/auth/me');
      return CurrentUser.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AuthException(_errorMessage(e, 'Could not load your profile.'));
    }
  }

  /// FEAT-003 (Role Selection) -- Screen 2's initial choice, and its
  /// change-later re-entry point from Account Settings. `role` must be one
  /// of the four self-service values (seeker | individual_host | agency |
  /// corporate) -- the backend rejects anything else (see
  /// app/schemas/auth.py's SELF_SERVICE_ROLES).
  Future<CurrentUser> updateRole(String role) async {
    try {
      final response =
          await _apiClient.dio.patch('/v1/auth/me/role', data: {'role': role});
      return CurrentUser.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AuthException(_errorMessage(e, "Couldn't save your selection, try again."));
    }
  }

  /// GET /v1/auth/me/notification-preferences -- FEAT-024. Mirrors
  /// PushNotificationRepository.getPreferences exactly (see that file),
  /// but for email's own category set (account | verification | payments
  /// -- distinct from push's listings | chat | payments per FEAT-024's
  /// "separate from push preferences" AC).
  Future<Map<String, bool>> getEmailPreferences() async {
    try {
      final response = await _apiClient.dio.get('/v1/auth/me/notification-preferences');
      final body = response.data as Map<String, dynamic>;
      return Map<String, bool>.from(body['email_notification_preferences'] as Map);
    } on DioException catch (e) {
      throw AuthException(_errorMessage(e, 'Could not load notification preferences.'));
    }
  }

  /// Partial update -- only the categories present in `updates` are
  /// changed, mirroring the backend's own partial-update contract
  /// (UpdateNotificationPreferencesRequest).
  Future<Map<String, bool>> updateEmailPreferences(Map<String, bool> updates) async {
    try {
      final response =
          await _apiClient.dio.patch('/v1/auth/me/notification-preferences', data: updates);
      final body = response.data as Map<String, dynamic>;
      return Map<String, bool>.from(body['email_notification_preferences'] as Map);
    } on DioException catch (e) {
      throw AuthException(_errorMessage(e, 'Could not update notification preferences.'));
    }
  }

  Future<void> logout() async {
    final refreshToken = await _sessionStore.readRefreshToken();
    if (refreshToken != null) {
      try {
        await _apiClient.dio
            .post('/v1/auth/logout', data: {'refresh_token': refreshToken});
      } on DioException {
        // Best-effort: local session is cleared regardless.
      }
    }
    await _sessionStore.clear();
  }
}
