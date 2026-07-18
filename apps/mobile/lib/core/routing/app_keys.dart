/// Process-wide keys shared between `main.dart`'s `MaterialApp.router` and
/// code that needs to reach the app's chrome without a `BuildContext` of
/// its own -- e.g. `push_notification_service.dart`'s foreground push
/// handler, which fires from a `FirebaseMessaging.onMessage` stream
/// listener that isn't part of the widget tree.
library;

import 'package:flutter/material.dart';

/// Passed to `MaterialApp.router(scaffoldMessengerKey: ...)` in main.dart.
/// `rootScaffoldMessengerKey.currentState` gives any non-widget code
/// (see push_notification_service.dart's `_onForegroundMessage`) a handle
/// on the app's single ScaffoldMessenger to show a MaterialBanner/SnackBar
/// from anywhere, regardless of which screen is currently active.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
