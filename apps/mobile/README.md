# De-Duke Mobile

Flutter client app for De-Duke (seekers, hosts, agencies, corporate).
See the project root's `AGENTS.md` and `docs/De-Duke/` for product/architecture
context -- this file only documents local dev commands.

## Environment Configuration

Build-time config (currently just the backend `API_BASE_URL`) is injected via
`--dart-define-from-file`, never hardcoded in Dart source (see
`lib/core/config/env.dart`).

1. Copy `.env.example.json` to `.env.json` (gitignored -- never commit it).
2. Fill in real values. For `API_BASE_URL`:
   - Android emulator: `http://10.0.2.2:8000` (loopback to the host machine)
   - iOS simulator / desktop / web: `http://localhost:8000`
   - Staging/production: the real deployed backend URL
3. Pass `--dart-define-from-file=.env.json` to every `flutter run`/`build`/`test`
   command below.

## Commands

- `fvm flutter pub get` -- install dependencies
- `fvm flutter run --dart-define-from-file=.env.json` -- run the app (Android emulator, or `-d chrome`/`-d windows`)
- `fvm flutter test` -- unit tests (`test/`) -- no backend config needed, these don't hit a real network
- `fvm flutter test integration_test/app_test.dart -d <device> --dart-define-from-file=.env.json` -- integration tests
- `fvm flutter build apk --debug --dart-define-from-file=.env.json` -- debug APK build
- `fvm flutter analyze` -- static analysis
- `fvm dart format --set-exit-if-changed .` -- format check
