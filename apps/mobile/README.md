# De-Duke Mobile

Flutter client app for De-Duke (seekers, hosts, agencies, corporate).
See the project root's `AGENTS.md` and `docs/De-Duke/` for product/architecture
context -- this file only documents local dev commands.

## Commands

- `fvm flutter pub get` -- install dependencies
- `fvm flutter run` -- run the app (Android emulator, or `-d chrome`/`-d windows`)
- `fvm flutter test` -- unit tests (`test/`)
- `fvm flutter test integration_test/app_test.dart -d <device>` -- integration tests
- `fvm flutter analyze` -- static analysis
- `fvm dart format --set-exit-if-changed .` -- format check
