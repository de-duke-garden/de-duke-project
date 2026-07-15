/// Repository wrapping FEAT-001 (Google & Firebase Sign-Up / Login) --
/// Google Sign-In, Firebase email/password, and Firebase phone/OTP, all
/// via the Firebase Authentication SDK client-side -- plus the Backend API
/// Service's /v1/auth session endpoints. Screens depend on this, never on
/// FirebaseAuth/GoogleSignIn/Dio directly.
///
/// Every sign-in AND account-linking method funnels through
/// `_completeFirebaseFlow`, which is the ONLY place that ever calls the
/// backend with a Firebase ID token (POST /v1/auth/firebase-exchange for
/// sign-in, POST /v1/auth/link-firebase-identity for linking an existing
/// session, FEAT-040) -- see architecture.md's Authentication &
/// Authorization: the Firebase ID token is a one-time credential-
/// collection proof, never used as the app's ongoing session credential
/// itself.
library;

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/session_store.dart';

class AuthResult {
  const AuthResult({
    required this.userId,
    required this.role,
    required this.isVerifiedHost,
    this.isNewUser = false,
  });

  final String userId;
  final String role;
  final bool isVerifiedHost;

  /// True only for a brand-new account's very first sign-in
  /// (POST /firebase-exchange's `is_new_user`) -- FEAT-001 AC: routes to
  /// Role Selection. NOT inferable from `role` alone (a returning user
  /// can still legitimately be "seeker") -- see
  /// auth_service.exchange_firebase_token's docstring on the backend for
  /// why this is a real field, not a client-side guess.
  final bool isNewUser;
}

/// GET /v1/auth/me -- current user's identity, for role/verification
/// checks (e.g. the app shell's bottom-nav tab selection). Distinct from
/// [UserProfile] below (GET/PATCH /v1/user/profile, FEAT-041), which is
/// Account Settings' own profile-editing data source.
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

/// GET/PATCH /v1/user/profile -- FEAT-041 (Self-Service Profile Editing).
/// Carries `authProvider`/`isFirebaseLinked` too, which Account Settings
/// needs to decide which fields are editable (FEAT-041) and what the
/// Linked Sign-In Methods section shows (FEAT-040).
class UserProfile {
  const UserProfile({
    required this.userId,
    required this.fullName,
    required this.email,
    required this.phoneNumber,
    required this.authProvider,
    required this.isFirebaseLinked,
    this.profilePhotoUrl,
  });

  final String userId;
  final String fullName;
  final String? email;
  final String? phoneNumber;

  /// "firebase" | "password" -- see schema.md's User.authProvider.
  final String authProvider;
  final bool isFirebaseLinked;

  /// FEAT-041 -- personal avatar, available to EVERY account type
  /// equally (not gated by `authProvider` the way `email` is). Distinct
  /// from FEAT-042's `HostAccount.hostPhotoUrl` (host-verification/listing
  /// photo, hosts only) -- see host_account_models.dart's
  /// `HostAccountStatus.hostPhotoUrl`.
  final String? profilePhotoUrl;

  bool get isFirebaseProvider => authProvider == 'firebase';
  bool get isPasswordProvider => authProvider == 'password';

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        userId: json['user_id'] as String,
        fullName: json['full_name'] as String,
        email: json['email'] as String?,
        phoneNumber: json['phone_number'] as String?,
        authProvider: json['auth_provider'] as String,
        isFirebaseLinked: json['is_firebase_linked'] as bool,
        profilePhotoUrl: json['profile_photo_url'] as String?,
      );
}

/// Thrown for any auth failure the UI needs to react to with a specific,
/// user-facing message (FEAT-001 AC: "provider-specific failures show a
/// clear, specific error message" -- never a generic "something went
/// wrong"). `message` doubles as a small set of sentinel values
/// ('offline', 'cancelled') the screen switches on for a dedicated state,
/// same pattern the pre-Firebase version of this file established.
class AuthException implements Exception {
  AuthException(this.message, {this.isAccountDeactivated = false});

  final String message;

  /// True only for screens.md Screen 1's "Account Deactivated" state --
  /// Firebase verification succeeded but the matched `User.isActive` is
  /// false (backend 403). Distinct from every other failure: no retry
  /// makes sense here, since the credential itself was fine.
  final bool isAccountDeactivated;

  @override
  String toString() => message;
}

class AuthRepository {
  AuthRepository(
    this._apiClient,
    this._sessionStore, {
    fb_auth.FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
  })  : _firebaseAuth = firebaseAuth ?? fb_auth.FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn();

  final ApiClient _apiClient;
  final SessionStore _sessionStore;
  final fb_auth.FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;

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

  /// Maps a subset of Firebase Authentication's error codes to the
  /// specific, plain-language messages screens.md Screen 1's States table
  /// documents (e.g. "That password's incorrect," "Too many attempts").
  /// Firebase's own `e.message` is technical/SDK-flavored and unsuitable
  /// to show directly -- falls back to it only for codes not worth a
  /// bespoke message.
  String _firebaseErrorMessage(fb_auth.FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
      case 'invalid-credential':
        return "That password's incorrect. Try again.";
      case 'user-not-found':
        return "We couldn't find an account for that email.";
      case 'invalid-verification-code':
      case 'invalid-otp':
      case 'session-expired':
        return 'That code expired. Request a new one.';
      case 'too-many-requests':
        return 'Too many attempts. Try again in a few minutes.';
      case 'network-request-failed':
        return 'offline';
      case 'weak-password':
        return 'Choose a stronger password (at least 6 characters).';
      case 'email-already-in-use':
        return 'That email is already in use with a different sign-in method.';
      case 'invalid-phone-number':
        return 'Enter a valid Nigerian phone number.';
      case 'user-disabled':
        return 'This account has been deactivated. Contact support.';
      default:
        return e.message ?? 'Something went wrong. Please try again.';
    }
  }

  Future<void> _persistSession(Map<String, dynamic> body) async {
    await _sessionStore.saveAccessToken(body['access_token'] as String);
    await _sessionStore.saveRefreshToken(body['refresh_token'] as String);
  }

  /// The single entry point for every consumer sign-in method below --
  /// takes the already-signed-in Firebase `User`, fetches its ID token,
  /// and either exchanges it for a NEW De-Duke session
  /// (`linking: false`, `POST /v1/auth/firebase-exchange`) or attaches it
  /// to the CALLER'S EXISTING session (`linking: true`,
  /// `POST /v1/auth/link-firebase-identity`, FEAT-040) -- see this file's
  /// module docstring. Split out from `UserCredential` (rather than each
  /// caller passing the credential object) specifically so
  /// `retryPendingExchange` below can re-invoke this same logic against
  /// `_firebaseAuth.currentUser` without needing a fresh `UserCredential`.
  Future<AuthResult> _completeFirebaseFlow(
    fb_auth.User? user, {
    bool linking = false,
  }) async {
    final idToken = await user?.getIdToken();
    if (idToken == null) {
      throw AuthException(
          'Your sign-in could not be verified. Please try again.');
    }
    try {
      final response = await _apiClient.dio.post(
        linking
            ? '/v1/auth/link-firebase-identity'
            : '/v1/auth/firebase-exchange',
        data: {'id_token': idToken},
      );
      final body = response.data as Map<String, dynamic>;
      if (linking) {
        // link-firebase-identity attaches to the caller's EXISTING
        // session (CurrentUserResponse shape -- no tokens to persist,
        // unlike firebase-exchange's AuthTokenResponse).
        return AuthResult(
          userId: body['user_id'] as String,
          role: body['role'] as String,
          isVerifiedHost: body['is_verified_host'] as bool,
        );
      }
      await _persistSession(body);
      return AuthResult(
        userId: body['user_id'] as String,
        role: body['role'] as String,
        isVerifiedHost: body['is_verified_host'] as bool,
        isNewUser: body['is_new_user'] as bool? ?? false,
      );
    } on DioException catch (e) {
      final deactivated = e.response?.statusCode == 403;
      throw AuthException(
        _errorMessage(
          e,
          deactivated
              ? 'This account has been deactivated. Contact support.'
              : linking
                  ? 'Could not link that sign-in method. Please try again.'
                  : 'Your sign-in could not be verified. Please try again.',
        ),
        isAccountDeactivated: deactivated,
      );
    }
  }

  /// Screen 1 "Continue with Google" -- hands off to the native system
  /// account picker (not an in-app form), then exchanges the resulting
  /// Firebase ID token for a De-Duke session.
  Future<AuthResult> signInWithGoogle() => _signInWithGoogle(linking: false);

  /// Screen 21 "Link a sign-in method" -> Google (FEAT-040) -- identical
  /// Google sign-in flow, but attaches the result to the caller's
  /// EXISTING session instead of starting a new one.
  Future<AuthResult> linkGoogleIdentity() => _signInWithGoogle(linking: true);

  Future<AuthResult> _signInWithGoogle({required bool linking}) async {
    // `GoogleSignIn.signIn()` itself is a NATIVE call (account picker,
    // Play Services) that can fail for reasons entirely unrelated to
    // Firebase -- most commonly a `PlatformException` (e.g. code
    // 'sign_in_failed' wrapping "ApiException: 10", Google's
    // DEVELOPER_ERROR for a SHA-1 fingerprint/OAuth client that isn't
    // registered for this app's package+signing cert in the Firebase/
    // Google Cloud console). Previously uncaught here entirely -- it
    // propagated past every AuthException-aware catch up to the screen,
    // which doesn't recognize a bare PlatformException and falls back to
    // a generic "Something went wrong," giving no signal at all about
    // what's actually broken.
    GoogleSignInAccount? googleUser;
    try {
      googleUser = await _googleSignIn.signIn();
    } on PlatformException catch (e) {
      throw AuthException(_googleSignInErrorMessage(e));
    }
    if (googleUser == null) {
      // User dismissed the picker -- screens.md's Edge Cases: this is not
      // an error banner moment, the screen just returns to Default.
      throw AuthException('cancelled');
    }
    try {
      final googleAuth = await googleUser.authentication;
      final credential = fb_auth.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCredential =
          await _firebaseAuth.signInWithCredential(credential);
      return await _completeFirebaseFlow(userCredential.user, linking: linking);
    } on fb_auth.FirebaseAuthException catch (e) {
      throw AuthException(_firebaseErrorMessage(e));
    } on PlatformException catch (e) {
      throw AuthException(_googleSignInErrorMessage(e));
    }
  }

  /// Maps common native Google Sign-In `PlatformException`s to a specific,
  /// actionable message rather than a generic fallback -- these are
  /// config/environment failures (or connectivity), not something a user
  /// retry alone fixes for the DEVELOPER_ERROR case.
  String _googleSignInErrorMessage(PlatformException e) {
    final detail = '${e.code} ${e.message ?? ''}';
    if (detail.contains('ApiException: 10')) {
      // DEVELOPER_ERROR -- the app's SHA-1 certificate fingerprint (or
      // OAuth client ID) isn't registered for this package name in the
      // Firebase console / Google Cloud OAuth consent screen. No retry
      // fixes this; it needs a config change on the Firebase project.
      return "Google sign-in isn't set up correctly for this app build yet. Contact support.";
    }
    if (detail.contains('ApiException: 7') || e.code == 'network_error') {
      return 'offline';
    }
    if (e.code == 'sign_in_canceled' ||
        detail.contains('ApiException: 12501')) {
      return 'cancelled';
    }
    return 'Google sign-in failed. Please try again.';
  }

  /// screens.md Screen 1 Edge Case: "Google Sign-In succeeds at the
  /// Firebase layer but the ID token exchange with the Backend API
  /// Service fails (e.g. network drop mid-exchange) -- the user is not
  /// left in a stuck 'signed into Firebase but not into De-Duke' state;
  /// the screen retries the exchange automatically once." Call this
  /// (instead of `signInWithGoogle` again) for that one automatic retry --
  /// it re-exchanges the ALREADY-signed-in Firebase user's ID token
  /// without re-prompting the Google account picker. Returns null if
  /// there is no current Firebase user to retry (nothing to recover, so
  /// the caller should fall back to a normal `signInWithGoogle` retry
  /// instead).
  Future<AuthResult?> retryPendingExchange() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return null;
    return _completeFirebaseFlow(user);
  }

  /// Screen 1 Email method. Firebase itself resolves whether `email` is a
  /// returning identity or brand-new -- there is deliberately no separate
  /// "Sign Up" vs. "Log In" mode for this method (screens.md Data Flow
  /// step 4): try sign-in first, and only create a new Firebase user on
  /// `user-not-found`.
  Future<AuthResult> signInOrRegisterWithEmail({
    required String email,
    required String password,
  }) =>
      _emailFlow(email: email, password: password, linking: false);

  /// Screen 21 "Link a sign-in method" -> Email/Password (FEAT-040).
  Future<AuthResult> linkEmailIdentity({
    required String email,
    required String password,
  }) =>
      _emailFlow(email: email, password: password, linking: true);

  Future<AuthResult> _emailFlow({
    required String email,
    required String password,
    required bool linking,
  }) async {
    try {
      fb_auth.UserCredential credential;
      try {
        credential = await _firebaseAuth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } on fb_auth.FirebaseAuthException catch (e) {
        if (e.code == 'user-not-found') {
          credential = await _firebaseAuth.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
        } else {
          rethrow;
        }
      }
      return await _completeFirebaseFlow(credential.user, linking: linking);
    } on fb_auth.FirebaseAuthException catch (e) {
      throw AuthException(_firebaseErrorMessage(e));
    }
  }

  /// Firebase's own "forgot password" email -- FEAT-001 AC: "Password
  /// reset ... handled entirely within Firebase's own flows," not a
  /// De-Duke-hosted reset screen. Errors are swallowed into the same
  /// non-leaking shape the old backend endpoint used (Firebase itself
  /// already avoids confirming account existence for this call).
  Future<void> sendFirebasePasswordResetEmail(String email) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email);
    } on fb_auth.FirebaseAuthException catch (e) {
      throw AuthException(_firebaseErrorMessage(e));
    }
  }

  /// Screen 1 Phone method, step 1 -- starts Firebase phone verification.
  /// Exactly one of `onCodeSent`/`onAutoVerified`/`onFailed` fires:
  ///   - `onCodeSent`: the common path -- screen transitions to the 6-box
  ///     OTP entry (screens.md "Phone: OTP Sent" state); pass the given
  ///     `verificationId` to `verifyPhoneCode` once the user enters it.
  ///   - `onAutoVerified`: Android's SMS auto-retrieval completed the
  ///     whole sign-in (including the backend exchange) without the user
  ///     ever typing a code -- screens.md's OTP entry state is simply
  ///     never reached; treat exactly like a manual `verifyPhoneCode`
  ///     success.
  ///   - `onFailed`: e.g. invalid-phone-number, before any code was even
  ///     sent.
  /// `linking: true` for Screen 21's "Link a sign-in method" -> Phone
  /// (FEAT-040) -- same live Firebase phone verification, but the eventual
  /// `verifyPhoneCode`/auto-verified result attaches to the caller's
  /// EXISTING session instead of starting a new one.
  Future<void> requestPhoneCode({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(AuthResult result) onAutoVerified,
    required void Function(AuthException error) onFailed,
    bool linking = false,
  }) async {
    await _firebaseAuth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) async {
        try {
          final userCredential =
              await _firebaseAuth.signInWithCredential(credential);
          onAutoVerified(await _completeFirebaseFlow(userCredential.user,
              linking: linking));
        } on AuthException catch (e) {
          onFailed(e);
        } catch (_) {
          onFailed(AuthException('Verification failed. Please try again.'));
        }
      },
      verificationFailed: (e) =>
          onFailed(AuthException(_firebaseErrorMessage(e))),
      codeSent: (verificationId, _) => onCodeSent(verificationId),
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  /// Screen 1 Phone method, step 2 -- the user's manually entered 6-digit
  /// code for the `verificationId` `requestPhoneCode` handed back. Pass
  /// the same `linking` value used on the matching `requestPhoneCode` call.
  Future<AuthResult> verifyPhoneCode({
    required String verificationId,
    required String smsCode,
    bool linking = false,
  }) async {
    try {
      final credential = fb_auth.PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      final userCredential =
          await _firebaseAuth.signInWithCredential(credential);
      return await _completeFirebaseFlow(userCredential.user, linking: linking);
    } on fb_auth.FirebaseAuthException catch (e) {
      throw AuthException(_firebaseErrorMessage(e));
    }
  }

  /// FEAT-040 -- Screen 21's "Unlink" action. Clears `firebaseUid` only;
  /// the account's password remains fully functional.
  Future<void> unlinkFirebaseIdentity() async {
    try {
      await _apiClient.dio.delete('/v1/auth/link-firebase-identity');
    } on DioException catch (e) {
      throw AuthException(
          _errorMessage(e, 'Could not unlink that sign-in method.'));
    }
  }

  /// FEAT-012's Agency Team invite AC ("the invitee sets their own
  /// password"): an invited team member pastes the userId + invite token
  /// from their invite email/link (see AcceptInviteScreen) and chooses a
  /// real password here. Unaffected by FEAT-001's move to Firebase --
  /// FEAT-012 team-member accounts stay backend-managed password accounts
  /// (see auth_service.py's module docstring). Returns a full session --
  /// same shape as firebase-exchange -- so the invitee lands signed-in
  /// immediately.
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

  /// Resolves the caller's identity from the persisted De-Duke session
  /// token (GET /v1/auth/me) -- used by the app shell (role-based bottom
  /// nav) and Account Settings.
  Future<CurrentUser> getCurrentUser() async {
    try {
      final response = await _apiClient.dio.get('/v1/auth/me');
      return CurrentUser.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AuthException(_errorMessage(e, 'Could not load your profile.'));
    }
  }

  /// FEAT-041 -- Account Settings' Profile fields section, plus the
  /// Linked Sign-In Methods section's current-state row (FEAT-040).
  Future<UserProfile> getProfile() async {
    try {
      final response = await _apiClient.dio.get('/v1/user/profile');
      return UserProfile.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AuthException(_errorMessage(e, 'Could not load your profile.'));
    }
  }

  /// Partial update -- only non-null fields are sent. `email` is rejected
  /// server-side (403) for `firebase`-provider accounts regardless of
  /// what's sent here -- see PATCH /v1/user/profile's backend docstring;
  /// the Account Settings screen shouldn't offer an editable email field
  /// for those accounts in the first place, but this call is not the only
  /// place that invariant is enforced.
  ///
  /// Multipart (not JSON), since `profilePhotoLocalPath` (FEAT-041) is a
  /// file upload -- matching host_account_repository.dart's own
  /// updateProfile. `clearProfilePhoto` resets the avatar to null
  /// independent of every other field; `profilePhotoLocalPath` takes
  /// precedence if both are somehow set in the same call (matching the
  /// backend's own precedence).
  Future<UserProfile> updateProfile({
    String? fullName,
    String? email,
    String? profilePhotoLocalPath,
    bool clearProfilePhoto = false,
  }) async {
    try {
      final formMap = <String, dynamic>{
        if (fullName != null) 'full_name': fullName,
        if (email != null) 'email': email,
        if (profilePhotoLocalPath != null)
          'profile_photo': await MultipartFile.fromFile(profilePhotoLocalPath),
        if (clearProfilePhoto) 'clear_profile_photo': 'true',
      };
      final response = await _apiClient.dio.patch(
        '/v1/user/profile',
        data: FormData.fromMap(formMap),
      );
      return UserProfile.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AuthException(_errorMessage(e, 'Could not save your profile.'));
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
      throw AuthException(
          _errorMessage(e, "Couldn't save your selection, try again."));
    }
  }

  /// GET /v1/auth/me/notification-preferences -- FEAT-024. Mirrors
  /// PushNotificationRepository.getPreferences exactly (see that file),
  /// but for email's own category set (account | verification | payments
  /// -- distinct from push's listings | chat | payments per FEAT-024's
  /// "separate from push preferences" AC).
  Future<Map<String, bool>> getEmailPreferences() async {
    try {
      final response =
          await _apiClient.dio.get('/v1/auth/me/notification-preferences');
      final body = response.data as Map<String, dynamic>;
      return Map<String, bool>.from(
          body['email_notification_preferences'] as Map);
    } on DioException catch (e) {
      throw AuthException(
          _errorMessage(e, 'Could not load notification preferences.'));
    }
  }

  /// Partial update -- only the categories present in `updates` are
  /// changed, mirroring the backend's own partial-update contract
  /// (UpdateNotificationPreferencesRequest).
  Future<Map<String, bool>> updateEmailPreferences(
      Map<String, bool> updates) async {
    try {
      final response = await _apiClient.dio
          .patch('/v1/auth/me/notification-preferences', data: updates);
      final body = response.data as Map<String, dynamic>;
      return Map<String, bool>.from(
          body['email_notification_preferences'] as Map);
    } on DioException catch (e) {
      throw AuthException(
          _errorMessage(e, 'Could not update notification preferences.'));
    }
  }

  /// Revokes the refresh token server-side (best-effort -- proceeds to
  /// clear local session even if the network call fails, since the user
  /// must always be able to log out locally regardless of connectivity),
  /// then signs out of Firebase/Google too, so a subsequent "Continue with
  /// Google" doesn't silently reuse the previous account without a picker.
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
    try {
      await _firebaseAuth.signOut();
      await _googleSignIn.signOut();
    } catch (_) {
      // Best-effort here too -- a Firebase/Google sign-out failure must
      // never block the user from being logged out of De-Duke itself.
    }
  }
}
