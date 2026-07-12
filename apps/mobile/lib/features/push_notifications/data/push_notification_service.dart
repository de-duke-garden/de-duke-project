/// FEAT-022 (Push Notifications) -- FCM registration and foreground
/// message handling. Was a TODO left in chat_repository.dart ("push
/// delivery/topic wiring belongs with the notifications feature") and a
/// TODO in main.dart ("no Firebase project is provisioned in this
/// environment yet") -- both are now real, `firebase_options.dart` and
/// `google-services.json` exist (flutterfire configure has been run).
library;

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'push_notification_repository.dart';

/// Must be a top-level (or static) function per firebase_messaging's own
/// requirement -- it runs in a separate isolate when the app is fully
/// terminated, so it cannot close over any instance state. Deliberately a
/// no-op beyond Firebase's own OS-level notification display (which
/// happens automatically for a `notification` payload even without this
/// handler) -- there is nothing else to do for a backgrounded/terminated
/// app; foreground-specific handling lives in
/// PushNotificationService._onForegroundMessage instead.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class PushNotificationService {
  PushNotificationService({
    required PushNotificationRepository repository,
    FirebaseMessaging? messaging,
  })  : _repository = repository,
        _messaging = messaging ?? FirebaseMessaging.instance;

  final PushNotificationRepository _repository;
  final FirebaseMessaging _messaging;
  StreamSubscription<String>? _tokenRefreshSubscription;
  bool _initialized = false;

  /// Requests notification permission, registers the current device's FCM
  /// token with the backend, and subscribes to token-refresh events (a
  /// token can change -- app reinstall, OS-level rotation -- and
  /// push_service.register_token's upsert-by-token handles re-registration
  /// correctly, see that function's docstring).
  ///
  /// Called once per authenticated session (see home_feed_screen.dart's
  /// `_load`, the one screen every successful auth flow reaches) --
  /// idempotent to call more than once (`_initialized` guard), since Home
  /// Feed's `_load` can re-run (pull-to-refresh).
  ///
  /// Never throws -- a push registration failure must not block the
  /// screen that triggered it (AGENTS.md External Service Resilience);
  /// failures are logged via debugPrint only.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        // User declined -- nothing more to do. FEAT-022's AC is "user CAN
        // manage preferences", not "push is forced on"; a denied OS
        // permission is a valid end state, not an error to surface.
        return;
      }

      final token = await _messaging.getToken();
      if (token != null) {
        await _repository.registerToken(token);
      }

      _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = _messaging.onTokenRefresh.listen(
        (refreshedToken) => _repository.registerToken(refreshedToken),
        onError: (Object e) => debugPrint('push_notification_service: token refresh failed: $e'),
      );

      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    } catch (e) {
      // Firebase not actually reachable (offline, misconfigured) --
      // degrade gracefully, same pattern as main.dart's own
      // Firebase.initializeApp() try/catch.
      debugPrint('push_notification_service: initialize failed: $e');
      _initialized = false; // allow a retry on the next Home Feed load
    }
  }

  /// FCM does not show a system notification for foreground messages on
  /// its own (that's the whole reason `onMessage` exists, vs. relying on
  /// OS-level display like background/terminated messages get) -- for now
  /// this just logs; in-app foreground notification UI (a toast/banner) is
  /// a follow-up, not blocking FEAT-022's stated AC ("push notification
  /// ... when app is backgrounded").
  void _onForegroundMessage(RemoteMessage message) {
    debugPrint('push_notification_service: foreground message: ${message.messageId}');
  }

  void dispose() {
    _tokenRefreshSubscription?.cancel();
  }
}
