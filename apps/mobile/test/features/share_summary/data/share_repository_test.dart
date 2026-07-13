import 'package:flutter_test/flutter_test.dart';

import 'package:de_duke_mobile/core/api/api_client.dart';
import 'package:de_duke_mobile/core/auth/session_store.dart';
import 'package:de_duke_mobile/features/share_summary/data/share_repository.dart';

import '../../../support/fake_http_adapter.dart';

/// Avoids touching the real flutter_secure_storage platform channel
/// (unavailable in a plain `flutter_test` unit test) -- ApiClient's
/// interceptor calls readAccessToken() on every request regardless of
/// whether the endpoint under test needs auth.
class FakeSessionStore extends SessionStore {
  @override
  Future<String?> readAccessToken() async => 'fake-token';
}

void main() {
  group('ShareRepository.generateShareLink', () {
    test('parses a successful POST into a ShareLink', () async {
      final client = ApiClient(
          baseUrl: 'https://api.test', sessionStore: FakeSessionStore());
      client.dio.httpClientAdapter = FakeHttpClientAdapter(
        (options) => (
          statusCode: 201,
          body: {
            'share_token': 'tok-abc123',
            'listing_id': 'listing-1',
            'expires_at': '2026-08-12T00:00:00Z',
          },
        ),
      );
      final repository = ShareRepository(client);

      final link = await repository.generateShareLink('listing-1');

      expect(link.shareToken, 'tok-abc123');
      expect(link.listingId, 'listing-1');
      expect(link.expiresAt, '2026-08-12T00:00:00Z');
    });

    test('propagates a connection error for the offline state', () async {
      final client = ApiClient(
          baseUrl: 'https://api.test', sessionStore: FakeSessionStore());
      client.dio.httpClientAdapter = ConnectionErrorHttpClientAdapter();
      final repository = ShareRepository(client);

      await expectLater(
        () => repository.generateShareLink('listing-1'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('ShareRepository.revokeShareLink', () {
    test('completes without error on a 200 response', () async {
      final client = ApiClient(
          baseUrl: 'https://api.test', sessionStore: FakeSessionStore());
      client.dio.httpClientAdapter = FakeHttpClientAdapter(
        (options) => (
          statusCode: 200,
          body: {'share_token': 'tok-abc123', 'is_revoked': true},
        ),
      );
      final repository = ShareRepository(client);

      await expectLater(
        repository.revokeShareLink('listing-1', 'tok-abc123'),
        completes,
      );
    });

    test('throws when the server rejects the revoke as forbidden', () async {
      final client = ApiClient(
          baseUrl: 'https://api.test', sessionStore: FakeSessionStore());
      client.dio.httpClientAdapter = FakeHttpClientAdapter(
        (options) => (
          statusCode: 403,
          body: {'detail': 'Only the originating user may revoke this share link.'},
        ),
      );
      final repository = ShareRepository(client);

      await expectLater(
        () => repository.revokeShareLink('listing-1', 'tok-abc123'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
