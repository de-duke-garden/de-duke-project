/// Hardware-backed secure storage for the session token (architecture.md
/// Client Application: "Sensitive data stored using hardware-backed secure
/// storage on-device").
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionStore {
  SessionStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _accessTokenKey = 'de_duke_access_token';

  final FlutterSecureStorage _storage;

  Future<void> saveAccessToken(String token) => _storage.write(key: _accessTokenKey, value: token);

  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  Future<void> clear() => _storage.delete(key: _accessTokenKey);
}
