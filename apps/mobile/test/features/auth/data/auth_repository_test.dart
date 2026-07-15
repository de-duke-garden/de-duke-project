import 'dart:async';

import 'package:dio/dio.dart' show FormData, HttpClientAdapter, RequestOptions;
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
  group('AuthRepository.signInWithEmail', () {
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

      final result = await built.repository.signInWithEmail(
          email: 'amaka@example.com', password: 'supersecret1');

      expect(result.userId, 'user-1');
      expect(result.role, 'seeker');
      expect(result.isNewUser, isFalse);
      expect(built.sessionStore.savedAccessToken, 'access-123');
      expect(built.sessionStore.savedRefreshToken, 'refresh-456');
    });

    test(
        'never silently creates an account -- maps user-not-found to a generic, non-account-confirming message',
        () async {
      final firebaseAuth = MockFirebaseAuth(mockUser: MockUser(uid: 'uid-1'));
      whenCalling(Invocation.method(#signInWithEmailAndPassword, null))
          .on(firebaseAuth)
          .thenThrow(fb_auth.FirebaseAuthException(code: 'user-not-found'));
      final built = _buildRepository(
        firebaseAuth: firebaseAuth,
        adapter: () =>
            FakeHttpClientAdapter((options) => (statusCode: 200, body: {})),
      );

      await expectLater(
        () => built.repository.signInWithEmail(
            email: 'new@example.com', password: 'supersecret1'),
        throwsA(isA<AuthException>().having(
            (e) => e.message,
            'message',
            "We couldn't sign you in with that email and password. New here? Switch to Sign Up.")),
      );
    });

    test(
        'maps invalid-credential (Email Enumeration Protection) to the same generic Sign In failure message',
        () async {
      // Firebase projects with Email Enumeration Protection enabled (the
      // default for projects created after ~June 2023) collapse BOTH "no
      // account for this email" and "wrong password" into the same
      // 'invalid-credential' code -- 'user-not-found' is no longer
      // reliably thrown. Explicit Sign In mode deliberately does NOT try
      // to distinguish the two (that would leak which emails have
      // accounts); it just points the user at Sign Up as the resolution.
      final firebaseAuth = MockFirebaseAuth(mockUser: MockUser(uid: 'uid-1'));
      whenCalling(Invocation.method(#signInWithEmailAndPassword, null))
          .on(firebaseAuth)
          .thenThrow(fb_auth.FirebaseAuthException(code: 'invalid-credential'));
      final built = _buildRepository(
        firebaseAuth: firebaseAuth,
        adapter: () =>
            FakeHttpClientAdapter((options) => (statusCode: 200, body: {})),
      );

      await expectLater(
        () => built.repository.signInWithEmail(
            email: 'brandnew@example.com', password: 'supersecret1'),
        throwsA(isA<AuthException>().having(
            (e) => e.message,
            'message',
            "We couldn't sign you in with that email and password. New here? Switch to Sign Up.")),
      );
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
        () => built.repository.signInWithEmail(
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
        () => built.repository.signInWithEmail(
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
        () => built.repository.signInWithEmail(
            email: 'amaka@example.com', password: 'supersecret1'),
        throwsA(isA<AuthException>()
            .having((e) => e.message, 'message', 'offline')),
      );
    });
  });

  group('AuthRepository.registerWithEmail', () {
    test('creates a new Firebase user and exchanges normally', () async {
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

      final result = await built.repository.registerWithEmail(
          email: 'new@example.com',
          password: 'supersecret1',
          fullName: 'Amaka Okafor');

      expect(result.isNewUser, isTrue);
      expect(built.sessionStore.savedAccessToken, 'access-new');
    });

    test(
        'sends the Sign Up form\'s full name via a best-effort profile update after exchange',
        () async {
      final firebaseAuth = MockFirebaseAuth();
      final requestPaths = <String>[];
      String? capturedFullName;
      final built = _buildRepository(
        firebaseAuth: firebaseAuth,
        adapter: () => FakeHttpClientAdapter((options) {
          requestPaths.add(options.path);
          if (options.path == '/v1/user/profile') {
            final fields = (options.data as FormData).fields;
            capturedFullName = fields
                .firstWhere((f) => f.key == 'full_name',
                    orElse: () => const MapEntry('full_name', ''))
                .value;
            return (
              statusCode: 200,
              body: {
                'user_id': 'user-2',
                'full_name': capturedFullName,
                'email': 'new@example.com',
                'phone_number': null,
                'auth_provider': 'firebase',
                'is_firebase_linked': false,
                'profile_photo_url': null,
              },
            );
          }
          return (
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
          );
        }),
      );

      await built.repository.registerWithEmail(
          email: 'new@example.com',
          password: 'supersecret1',
          fullName: 'Amaka Okafor');

      expect(requestPaths, contains('/v1/user/profile'));
      expect(capturedFullName, 'Amaka Okafor');
    });

    test(
        'maps email-already-in-use to a message pointing at Sign In, never silently logging the user in',
        () async {
      final firebaseAuth = MockFirebaseAuth(mockUser: MockUser(uid: 'uid-1'));
      whenCalling(Invocation.method(#createUserWithEmailAndPassword, null))
          .on(firebaseAuth)
          .thenThrow(
              fb_auth.FirebaseAuthException(code: 'email-already-in-use'));
      final built = _buildRepository(
        firebaseAuth: firebaseAuth,
        adapter: () =>
            FakeHttpClientAdapter((options) => (statusCode: 200, body: {})),
      );

      await expectLater(
        () => built.repository.registerWithEmail(
            email: 'amaka@example.com',
            password: 'supersecret1',
            fullName: 'Amaka Okafor'),
        throwsA(isA<AuthException>().having(
            (e) => e.message,
            'message',
            'An account already exists for that email. Switch to Sign In instead.')),
      );
    });
  });

  group('AuthRepository.linkEmailIdentity', () {
    // FEAT-040 linking deliberately keeps the OLD combined
    // try-sign-in-then-create-on-failure behavior (see the method's
    // docstring) -- these tests exercise that fallback directly, now that
    // the main Sign Up / Sign In screen no longer uses it.
    test(
        'falls back to account creation on invalid-credential (Email Enumeration Protection), then links normally',
        () async {
      final firebaseAuth = MockFirebaseAuth(mockUser: MockUser(uid: 'uid-1'));
      whenCalling(Invocation.method(#signInWithEmailAndPassword, null))
          .on(firebaseAuth)
          .thenThrow(fb_auth.FirebaseAuthException(code: 'invalid-credential'));
      final built = _buildRepository(
        firebaseAuth: firebaseAuth,
        adapter: () => FakeHttpClientAdapter(
          (options) => (
            statusCode: 200,
            body: {
              'user_id': 'user-3',
              'role': 'seeker',
              'is_verified_host': false,
            },
          ),
        ),
      );

      final result = await built.repository.linkEmailIdentity(
          email: 'brandnew@example.com', password: 'supersecret1');

      expect(result.userId, 'user-3');
    });

    test(
        'reports "password incorrect" when invalid-credential turns out to be a genuine existing account',
        () async {
      final firebaseAuth = MockFirebaseAuth(mockUser: MockUser(uid: 'uid-1'));
      whenCalling(Invocation.method(#signInWithEmailAndPassword, null))
          .on(firebaseAuth)
          .thenThrow(fb_auth.FirebaseAuthException(code: 'invalid-credential'));
      whenCalling(Invocation.method(#createUserWithEmailAndPassword, null))
          .on(firebaseAuth)
          .thenThrow(
              fb_auth.FirebaseAuthException(code: 'email-already-in-use'));
      final built = _buildRepository(
        firebaseAuth: firebaseAuth,
        adapter: () =>
            FakeHttpClientAdapter((options) => (statusCode: 200, body: {})),
      );

      await expectLater(
        () => built.repository.linkEmailIdentity(
            email: 'amaka@example.com', password: 'wrong'),
        throwsA(isA<AuthException>().having((e) => e.message, 'message',
            "That password's incorrect. Try again.")),
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

    test(
        'verifyPhoneCode succeeds when expectingNewUser matches the backend result',
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
        verificationId: 'verification-id-1',
        smsCode: '123456',
        expectingNewUser: true,
      );

      expect(result.userId, 'user-phone');
    });

    test(
        'rolls back and points at Sign In when Sign Up was picked for a number that already has an account',
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
              'is_new_user': false,
            },
          ),
        ),
      );

      await expectLater(
        () => built.repository.verifyPhoneCode(
          verificationId: 'verification-id-1',
          smsCode: '123456',
          expectingNewUser: true,
        ),
        throwsA(isA<AuthException>().having(
            (e) => e.message,
            'message',
            'An account already exists for that phone number. Switch to Sign In instead.')),
      );
      // The mismatched session must not be left in place.
      expect(built.sessionStore.cleared, isTrue);
    });

    test(
        'rolls back and points at Sign Up when Sign In was picked for a brand-new number',
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

      await expectLater(
        () => built.repository.verifyPhoneCode(
          verificationId: 'verification-id-1',
          smsCode: '123456',
          expectingNewUser: false,
        ),
        throwsA(isA<AuthException>().having(
            (e) => e.message,
            'message',
            "We couldn't find an account for that phone number. Switch to Sign Up instead.")),
      );
      expect(built.sessionStore.cleared, isTrue);
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

  group('AuthRepository.updateProfile', () {
    test('sends fullName as multipart form data and parses the response',
        () async {
      final firebaseAuth = MockFirebaseAuth(mockUser: MockUser(uid: 'uid-1'));
      RequestOptions? captured;
      final built = _buildRepository(
        firebaseAuth: firebaseAuth,
        adapter: () => FakeHttpClientAdapter((options) {
          captured = options;
          return (
            statusCode: 200,
            body: {
              'user_id': 'user-1',
              'full_name': 'New Name',
              'email': 'amaka@example.com',
              'phone_number': null,
              'auth_provider': 'firebase',
              'is_firebase_linked': false,
              'profile_photo_url': null,
            },
          );
        }),
      );

      final result = await built.repository.updateProfile(fullName: 'New Name');

      expect(result.fullName, 'New Name');
      expect(captured!.data, isA<FormData>());
      final fields = (captured!.data as FormData).fields;
      expect(fields.any((f) => f.key == 'full_name' && f.value == 'New Name'),
          isTrue);
    });

    test('sends clearProfilePhoto as a multipart form field', () async {
      final firebaseAuth = MockFirebaseAuth(mockUser: MockUser(uid: 'uid-1'));
      RequestOptions? captured;
      final built = _buildRepository(
        firebaseAuth: firebaseAuth,
        adapter: () => FakeHttpClientAdapter((options) {
          captured = options;
          return (
            statusCode: 200,
            body: {
              'user_id': 'user-1',
              'full_name': 'Amaka',
              'email': null,
              'phone_number': null,
              'auth_provider': 'firebase',
              'is_firebase_linked': false,
              'profile_photo_url': null,
            },
          );
        }),
      );

      final result =
          await built.repository.updateProfile(clearProfilePhoto: true);

      expect(result.profilePhotoUrl, isNull);
      final fields = (captured!.data as FormData).fields;
      expect(
          fields.any(
              (f) => f.key == 'clear_profile_photo' && f.value == 'true'),
          isTrue);
    });

    test('maps a 403 (firebase-provider email change) to a specific message',
        () async {
      final firebaseAuth = MockFirebaseAuth(mockUser: MockUser(uid: 'uid-1'));
      final built = _buildRepository(
        firebaseAuth: firebaseAuth,
        adapter: () => FakeHttpClientAdapter(
          (options) => (
            statusCode: 403,
            body: {
              'detail':
                  "Your email is managed by Google/Firebase and can't be changed here."
            },
          ),
        ),
      );

      await expectLater(
        () => built.repository.updateProfile(email: 'new@example.com'),
        throwsA(isA<AuthException>().having(
          (e) => e.message,
          'message',
          "Your email is managed by Google/Firebase and can't be changed here.",
        )),
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
