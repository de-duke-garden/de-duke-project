/// Build-time environment configuration.
///
/// Values are injected via `--dart-define-from-file=.env.json` (see
/// `.env.example.json` for the documented key set and `README.md` for the
/// exact run/build/test commands). Never hardcode a real backend host,
/// API key, or secret directly in Dart source -- add a new key here and
/// to both `.env.json` (local, gitignored) and `.env.example.json`
/// (tracked, REPLACE_ME placeholder) instead.
library;

class AppConfig {
  AppConfig._();

  /// Base URL for the FastAPI backend, e.g. `http://10.0.2.2:8000` when
  /// targeting the Android emulator (which cannot reach the host machine's
  /// `localhost` directly), `http://localhost:8000` for iOS
  /// simulator/desktop/web, or a real deployed URL for staging/production
  /// builds.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );
}
