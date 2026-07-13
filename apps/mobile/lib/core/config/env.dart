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

  /// Google Maps Platform API key -- same key used natively via
  /// android/local.properties' googleMaps.apiKey (for the GoogleMap widget
  /// itself), exposed here too so Dart code can call Google's REST APIs
  /// directly (e.g. the Geocoding API for reverse-geocoding a dropped map
  /// pin into a human-readable address). Empty default means reverse
  /// geocoding silently no-ops rather than erroring when unconfigured --
  /// consistent with this project's other optional-third-party-credential
  /// degradation pattern.
  static const String googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );

  /// Public origin hosting the Admin Web Console's unauthenticated
  /// `/s/:token` route (FEAT-020, screens.md Screen 18) -- e.g.
  /// `https://admin.de-duke.com`. The backend only ever returns a bare
  /// `share_token`; this base is what Screen 17 (Generate) prefixes onto it
  /// to build the full external URL handed to Copy/Share actions.
  static const String publicShareBaseUrl = String.fromEnvironment(
    'PUBLIC_SHARE_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );
}
