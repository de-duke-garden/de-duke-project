import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Required before any firebase_auth/cloud_firestore call (FEAT-010 chat).
  // No Firebase project is provisioned in this environment yet (no
  // google-services.json/GoogleService-Info.plist, no generated
  // firebase_options.dart) -- this deliberately does not crash app startup
  // if initialization fails; chat screens surface a clear error via
  // ChatRepository.ensureSignedIn() at the point of use instead.
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Intentionally swallowed -- see comment above.
  }

  runApp(const DeDukeApp());
}

class DeDukeApp extends StatelessWidget {
  const DeDukeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'De-Duke',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
    );
  }
}
