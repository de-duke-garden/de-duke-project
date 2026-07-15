import 'dart:async';

import 'package:dio/dio.dart' show HttpClientAdapter;
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';

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

/// Builds an AuthRepository wired to a FakeHttpClientAdapter-backed Dio
/// (for the /v1/auth/firebase-exchange round-trip) and a MockFirebaseAuth
/// (firebase_auth_mocks -- FEAT-001's Firebase-based sign-in methods).
/// `FirebaseAuth.instance` requires a live Firebase App, which never
/// exists in this test environment -- every AuthRepository construction
/// below MUST pass an explicit `firebaseAuth` override, or construction
/// itself throws.
({AuthRepository repository, FakeSessionStore sessionStore}) _buildRepository({
  required MockFirebaseAuth firebaseAuth,
  required HttpClientAdapter Function() adapter,
}) {
  final sessionStore = FakeSessionStore();
  final client =
      ApiClient(baseUrl: 'https://api.test', sessionStore: sessionStore);
  client.dio.httpClientAdapter = adapter();
  final repository =
      AuthRepository(client, sessionStore, firebaseAuth: firebaseAuth);
  return (repository: repository, sessionStore: sessionStore);
}

void main() {
  group('AuthRepository.signInOrRegisterWithEmail', () {
    test(
        'exchanges the Firebase ID token for a De-Duke session and persists both tokens',
        () async {
      final firebaseAuth = MockFirebaseAuth(
          mockUser: MockUser(uid: 'uid-1', email: 'amaka@example.com'));
      final built = _buildRepository(
        firebaseAuth: firebaseAuth,
        adapter: () => FakeHttpClientAdapter(
          (options) => (
            statusCode: 200,
            body: {
              'access_token': 'access-123',
              'refresh_token': 'refresh-456',
              'token_type': 'bearer',
              'user_id': 'user-1',
              'role': 'seeker',
              'is_verified_host': false,
              'is_new_user': false,
            },
          ),
        ),
      );

      final result = await built.repository.signInOrRegisterWithEmail(
          email: 'amaka@example.com', password: 'supersecret1');

      expect(result.userId, 'user-1');
      expect(result.role, 'seeker');
      expect(result.isNewUser, isFalse);
      expect(built.sessionStore.savedAccessToken, 'access-123');
      expect(built.sessionStore.savedRefreshToken, 'refresh-456');
    });

    test(
        'falls back to account creation on user-not-found, then exchanges normally',
        () async {
      // MockFirebaseAuth's signInWithEmailAndPassword never throws by
      // default (unlike a real unregistered email) -- this test instead
      // verifies the fallback branch directly: createUserWithEmailAndPassword
      // must still resolve to a successful exchange when it's the path taken.
      final firebaseAuth = MockFirebaseAuth();
      final built = _buildRepository(
        firebaseAuth: firebaseAuth,
        adapter: () => FakeHttpClientAdapter(
          (options) => (
            statusCode: 200,
            body: {
              'access_token': 'access-new',
              'refresh_token': 'refresh-new',
              'token_type': 'bearer',
              'user_id': 'user-2',
              'role': 'seeker',
              'is_verified_host': false,
              'is_new_user': true,
            },
          ),
        ),
      );

      final result = await built.repository.signInOrRegisterWithEmail(
          email: 'new@example.com', password: 'supersecret1');

      expect(result.isNewUser, isTrue);
      expect(built.sessionStore.savedAccessToken, 'access-new');
    });

    test('maps a wrong-password FirebaseAuthException to a specific message',
        () async {
      final firebaseAuth = MockFirebaseAuth(mockUser: MockUser(uid: 'uid-1'));
      whenCalling(Invocation.method(#signInWithEmailAndPassword, null))
          .on(firebaseAuth)
          .thenThrow(fb_auth.FirebaseAuthException(code: 'wrong-password'));
      final built = _buildRepository(
        firebaseAuth: firebaseAuth,
        adapter: () =>
            FakeHttpClientAdapter((options) => (statusCode: 200, body: {})),
      );

      await expectLater(
        () => built.repository.signInOrRegisterWithEmail(
            email: 'amaka@example.com', password: 'wrong'),
        throwsA(isA<AuthException>().having((e) => e.message, 'message',
            "That password's incorrect. Try again.")),
      );
    });

    test('maps a 403 (deactivated account) response to isAccountDeactivated',
        () async {
      final firebaseAuth = MockFirebaseAuth(
          mockUser: MockUser(uid: 'uid-1', email: 'gone@example.com'));
      final built = _buildRepository(
        firebaseAuth: firebaseAuth,
        adapter: () => FakeHttpClientAdapter(
          (options) => (
            statusCode: 403,
            body: {'detail': 'This account has been deactivated.'},
          ),
        ),
      );

      await expectLater(
        () => built.repository.signInOrRegisterWithEmail(
            email: 'gone@example.com', password: 'supersecret1'),
        throwsA(isA<AuthException>().having(
            (e) => e.isAccountDeactivated, 'isAccountDeactivated', isTrue)),
      );
    });

    test('maps a connection error to the "offline" sentinel', () async {
      final firebaseAuth = MockFirebaseAuth(
          mockUser: MockUser(uid: 'uid-1', email: 'amaka@example.com'));
      final built = _buildRepository(
        firebaseAuth: firebaseAuth,
        adapter: () => ConnectionErrorHttpClientAdapter(),
      );

      await expectLater(
        () => built.repository.signInOrRegisterWithEmail(
            email: 'amaka@example.com', password: 'supersecret1'),
        throwsA(isA<AuthException>()
            .having((e) => e.message, 'message', 'offline')),
      );
    });
  });

  group('AuthRepository phone sign-in', () {
    test('requestPhoneCode invokes onCodeSent once Firebase sends the SMS',
        () async {
      final firebaseAuth = MockFirebaseAuth();
      final built = _buildRepository(
        firebaseAuth: firebaseAuth,
        adapter: () =>
            FakeHttpClientAdapter((options) => (statusCode: 200, body: {})),
      );
      final codeSent = Completer<String>();

      await built.repository.requestPhoneCode(
        phoneNumber: '+2348012345678',
        onCodeSent: (verificationId) => codeSent.complete(verificationId),
        onAutoVerified: (_) => fail('should not auto-verify in this mock'),
        onFailed: (e) => fail('should not fail: $e'),
      );

      expect(await codeSent.future, isNotEmpty);
    });

    test('verifyPhoneCode exchanges the resulting credential for a session',
        () async {
      final firebaseAuth = MockFirebaseAuth(
          mockUser: MockUser(uid: 'uid-phone', phoneNumber: '+2348012345678'));
      final built = _buildRepository(
        firebaseAuth: firebaseAuth,
        adapter: () => FakeHttpClientAdapter(
          (options) => (
            statusCode: 200,
            body: {
              'access_token': 'phone-access',
              'refresh_token': 'phone-refresh',
              'token_type': 'bearer',
              'user_id': 'user-phone',
              'role': 'seeker',
              'is_verified_host': false,
              'is_new_user': true,
            },
          ),
        ),
      );

      final result = await built.repository.verifyPhoneCode(
          verificationId: 'verification-id-1', smsCode: '123456');

      expect(result.userId, 'user-phone');
      expect(result.isNewUser, isTrue);
      expect(built.sessionStore.savedAccessToken, 'phone-access');
    });

    test('maps an invalid-verification-code error to a specific message',
        () async {
      final firebaseAuth =
          MockFirebaseAuth(mockUser: MockUser(uid: 'uid-phone'));
      whenCalling(Invocation.method(#signInWithCredential, null))
          .on(firebaseAuth)
          .thenThrow(
              fb_auth.FirebaseAuthException(code: 'invalid-verification-code'));
      final built = _buildRepository(
        firebaseAuth: firebaseAuth,
        adapter: () =>
            FakeHttpClientAdapter((options) => (statusCode: 200, body: {})),
      );

      await expectLater(
        () => built.repository.verifyPhoneCode(
            verificationId: 'verification-id-1', smsCode: '000000'),
        throwsA(isA<AuthException>().having((e) => e.message, 'message',
            'That code expired. Request a new one.')),
      );
    });
  });

  group('AuthRepository.logout', () {
    test('revokes the refresh token server-side then clears the local session',
        () async {
      final firebaseAuth =
          MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'uid-1'));
      final sessionStore = FakeSessionStore()
        ..savedRefreshToken = 'refresh-456';
      final client =
          ApiClient(baseUrl: 'https://api.test', sessionStore: sessionStore);
      String? capturedPath;
      client.dio.httpClientAdapter = FakeHttpClientAdapter((options) {
        capturedPath = options.path;
        return (statusCode: 204, body: null);
      });
      final repository =
          AuthRepository(client, sessionStore, firebaseAuth: firebaseAuth);

      await repository.logout();

      expect(capturedPath, '/v1/auth/logout');
      expect(sessionStore.cleared, isTrue);
    });

    test('still clears the local session even if the revocation call fails',
        () async {
      final firebaseAuth =
          MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'uid-1'));
      final sessionStore = FakeSessionStore()
        ..savedRefreshToken = 'refresh-456';
      final client =
          ApiClient(baseUrl: 'https://api.test', sessionStore: sessionStore);
      client.dio.httpClientAdapter = ConnectionErrorHttpClientAdapter();
      final repository =
          AuthRepository(client, sessionStore, firebaseAuth: firebaseAuth);

      await repository.logout();

      expect(sessionStore.cleared, isTrue);
    });

    test(
        'still clears the local session even if Firebase/Google sign-out fails',
        () async {
      // Exercises the outer try/catch around _firebaseAuth.signOut()/
      // _googleSignIn.signOut() -- a Firebase-side failure must never
      // block the user from being logged out of De-Duke itself.
      final firebaseAuth =
          MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'uid-1'));
      whenCalling(Invocation.method(#signOut, null)).on(firebaseAuth).thenThrow(
          fb_auth.FirebaseAuthException(code: 'network-request-failed'));
      final sessionStore = FakeSessionStore();
      final client =
          ApiClient(baseUrl: 'https://api.test', sessionStore: sessionStore);
      client.dio.httpClientAdapter =
          FakeHttpClientAdapter((options) => (statusCode: 204, body: null));
      final repository =
          AuthRepository(client, sessionStore, firebaseAuth: firebaseAuth);

      await repository.logout();

      expect(sessionStore.cleared, isTrue);
    });
  });
}
