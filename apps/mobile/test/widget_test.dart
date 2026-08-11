// Smoke test -- the app boots and renders without throwing.
//
// Replaces the default Flutter template counter test (which referenced a
// non-existent `MyApp` widget and failed `flutter analyze`). Pumps the real
// app entrypoint (DeDukeApp inside ProviderScope, matching main.dart) and
// verifies the first frame builds. Firebase/network services are not
// initialized in this test -- DeDukeApp must render its bootstrap/splash
// state without them (any real dependency is exercised in feature tests).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:de_duke_mobile/main.dart';

void main() {
  testWidgets('DeDukeApp renders a first frame', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: DeDukeApp()));
    await tester.pump();

    // The app bootstraps without throwing -- no crash on the first frame.
    expect(tester.takeException(), isNull);
  });
}
