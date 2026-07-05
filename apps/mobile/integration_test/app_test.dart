/// End-to-end integration test driving the real app widget tree (not a
/// pumped-in-isolation widget), per the user's request for integration
/// test coverage. Runs against a real Flutter engine (e.g. `flutter test
/// integration_test/app_test.dart -d chrome`), unlike `flutter test`'s
/// fake/headless widget test environment.
///
/// Scope: navigation + screen assembly only, no live backend calls -- none
/// of the screens exercised here fetch on mount (AuthScreen only calls the
/// backend on form submit), so this is safe to run without a running
/// Backend API Service.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:de_duke_mobile/core/routing/app_router.dart';
import 'package:de_duke_mobile/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('De-Duke app navigation', () {
    testWidgets('boots to the initial route', (tester) async {
      await tester.pumpWidget(const DeDukeApp());
      await tester.pumpAndSettle();

      expect(find.textContaining('Splash/Onboarding'), findsOneWidget);
    });

    testWidgets('navigating to /auth/login shows the Sign Up / Log In screen',
        (tester) async {
      await tester.pumpWidget(const DeDukeApp());
      await tester.pumpAndSettle();

      appRouter.go('/auth/login');
      await tester.pumpAndSettle();

      expect(find.text('De-Duke'), findsOneWidget);
      expect(find.text('Sign Up'), findsOneWidget);
      expect(find.text('Log In'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
    });

    testWidgets(
        'toggling "Use phone number instead" swaps the identifier field',
        (tester) async {
      await tester.pumpWidget(const DeDukeApp());
      await tester.pumpAndSettle();

      appRouter.go('/auth/login');
      await tester.pumpAndSettle();

      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Phone number'), findsNothing);

      await tester.tap(find.text('Use phone number instead'));
      await tester.pumpAndSettle();

      expect(find.text('Phone number'), findsOneWidget);
      expect(find.text('Email'), findsNothing);
      // Screens.md edge case: switching email<->phone clears the other
      // field/mode rather than submitting mixed state -- the password
      // field (email-only) must disappear once phone mode is active.
      expect(find.text('Password'), findsNothing);
    });

    testWidgets('Forgot password link navigates to the reset flow',
        (tester) async {
      await tester.pumpWidget(const DeDukeApp());
      await tester.pumpAndSettle();

      appRouter.go('/auth/login');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();

      expect(find.text('Reset password'), findsWidgets);
    });

    testWidgets('navigating to /auth/signup shows the Sign Up tab pre-selected',
        (tester) async {
      await tester.pumpWidget(const DeDukeApp());
      await tester.pumpAndSettle();

      appRouter.go('/auth/signup');
      await tester.pumpAndSettle();

      expect(find.text('Full name'), findsOneWidget);
      expect(find.text('Create account'), findsOneWidget);
    });
  });
}
