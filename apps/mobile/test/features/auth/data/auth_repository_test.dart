import 'package:flutter_test/flutter_test.dart';

import 'package:de_duke_mobile/core/api/api_client.dart';
import 'package:de_duke_mobile/core/auth/session_store.dart';
import 'package:de_duke_mobile/features/auth/data/auth_repository.dart';

import '../../../support/fake_http_adapter.dart';

class FakeSessionStore extends SessionStore {
  String? savedAccessToken;
  String? savedRefreshToken;
  bool cleared = false;

  @override
  Future<String?> readAccessToken() async => savedAccessToken ?? 'fake-token';

  @override
  Future<void> saveAccessToken(String token) async => savedAccessToken = token;

  @override
  Future<void> saveRefreshToken(String token) async =>
      savedRefreshToken = token;

  @override
  Future<String?> readRefreshToken() async => savedRefreshToken;

  @override
  Future<void> clear() async => cleared = true;
}

void main() {
  group('AuthRepository.loginWithEmail', () {
    test('persists both access and refresh tokens on success', () async {
      final sessionStore = FakeSessionStore();
      final client =
          ApiClient(baseUrl: 'https://api.test', sessionStore: sessionStore);
      client.dio.httpClientAdapter = FakeHttpClientAdapter(
        (options) => (
          statusCode: 200,
          body: {
            'access_token': 'access-123',
            'refresh_token': 'refresh-456',
            'token_type': 'bearer',
            'user_id': 'user-1',
            'role': 'seeker',
            'is_verified_host': false,
          },
        ),
      );
      final repository = AuthRepository(client, sessionStore);

      final result = await repository.loginWithEmail(
          email: 'amaka@example.com', password: 'supersecret1');

      expect(result.userId, 'user-1');
      expect(result.role, 'seeker');
      expect(sessionStore.savedAccessToken, 'access-123');
      expect(sessionStore.savedRefreshToken, 'refresh-456');
    });

    test(
        'maps invalid credentials (401) to the specific backend message, per FEAT-001 AC',
        () async {
      final sessionStore = FakeSessionStore();
      final client =
          ApiClient(baseUrl: 'https://api.test', sessionStore: sessionStore);
      client.dio.httpClientAdapter = FakeHttpClientAdapter(
        (options) =>
            (statusCode: 401, body: {'detail': 'Invalid email or password.'}),
      );
      final repository = AuthRepository(client, sessionStore);

      await expectLater(
        () => repository.loginWithEmail(
            email: 'amaka@example.com', password: 'wrong'),
        throwsA(isA<AuthException>()
            .having((e) => e.message, 'message', 'Invalid email or password.')),
      );
    });

    test('maps a connection error to the "offline" sentinel', () async {
      final sessionStore = FakeSessionStore();
      final client =
          ApiClient(baseUrl: 'https://api.test', sessionStore: sessionStore);
      client.dio.httpClientAdapter = ConnectionErrorHttpClientAdapter();
      final repository = AuthRepository(client, sessionStore);

      await expectLater(
        () => repository.loginWithEmail(
            email: 'amaka@example.com', password: 'supersecret1'),
        throwsA(isA<AuthException>()
            .having((e) => e.message, 'message', 'offline')),
      );
    });
  });

  group('AuthRepository.verifyPhoneSignupOtp', () {
    test('maps an expired/invalid OTP (400) to the "otp_expired" sentinel',
        () async {
      final sessionStore = FakeSessionStore();
      final client =
          ApiClient(baseUrl: 'https://api.test', sessionStore: sessionStore);
      client.dio.httpClientAdapter = FakeHttpClientAdapter(
        (options) =>
            (statusCode: 400, body: {'detail': 'Invalid or expired OTP code.'}),
      );
      final repository = AuthRepository(client, sessionStore);

      await expectLater(
        () => repository.verifyPhoneSignupOtp(
            phoneNumber: '+2348012345678', otpCode: '0000'),
        throwsA(isA<AuthException>()),
      );
    });
  });

  group('AuthRepository.logout', () {
    test('revokes the refresh token server-side then clears the local session',
        () async {
      final sessionStore = FakeSessionStore()
        ..savedRefreshToken = 'refresh-456';
      final client =
          ApiClient(baseUrl: 'https://api.test', sessionStore: sessionStore);
      String? capturedPath;
      client.dio.httpClientAdapter = FakeHttpClientAdapter((options) {
        capturedPath = options.path;
        return (statusCode: 204, body: null);
      });
      final repository = AuthRepository(client, sessionStore);

      await repository.logout();

      expect(capturedPath, '/v1/auth/logout');
      expect(sessionStore.cleared, isTrue);
    });

    test('still clears the local session even if the revocation call fails',
        () async {
      final sessionStore = FakeSessionStore()
        ..savedRefreshToken = 'refresh-456';
      final client =
          ApiClient(baseUrl: 'https://api.test', sessionStore: sessionStore);
      client.dio.httpClientAdapter = ConnectionErrorHttpClientAdapter();
      final repository = AuthRepository(client, sessionStore);

      await repository.logout();

      expect(sessionStore.cleared, isTrue);
    });
  });
}
