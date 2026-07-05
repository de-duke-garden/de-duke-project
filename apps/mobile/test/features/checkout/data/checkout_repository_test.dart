import 'package:flutter_test/flutter_test.dart';

import 'package:de_duke_mobile/core/api/api_client.dart';
import 'package:de_duke_mobile/core/auth/session_store.dart';
import 'package:de_duke_mobile/features/checkout/data/checkout_repository.dart';

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
  group('CheckoutRepository.newIdempotencyKey', () {
    test('generates a unique key per call', () {
      final client = ApiClient(
          baseUrl: 'https://api.test', sessionStore: FakeSessionStore());
      final repository = CheckoutRepository(client);

      final first = repository.newIdempotencyKey();
      final second = repository.newIdempotencyKey();

      expect(first, isNotEmpty);
      expect(first, isNot(equals(second)));
      // UUID v4 format: 8-4-4-4-12 hex groups.
      expect(
          RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
              .hasMatch(first),
          isTrue);
    });
  });

  group('CheckoutRepository.getTransaction', () {
    test('parses a successful response into a TransactionDetail', () async {
      final client = ApiClient(
          baseUrl: 'https://api.test', sessionStore: FakeSessionStore());
      client.dio.httpClientAdapter = FakeHttpClientAdapter(
        (options) => (
          statusCode: 200,
          body: {
            'id': 'txn-1',
            'listing_id': 'listing-1',
            'transaction_type': 'shortlet_booking',
            'status': 'held',
            'gross_amount': 45000.0,
            'commission_amount': 2250.0,
            'net_payout_amount': 42750.0,
            'created_at': '2026-07-01T10:00:00Z',
            'payer_id': 'user-payer',
            'payee_id': 'user-payee',
            'paid_at': null,
            'hold_expires_at': '2026-07-01T10:15:00Z',
            'receipt_url': null,
          },
        ),
      );
      final repository = CheckoutRepository(client);

      final txn = await repository.getTransaction('txn-1');

      expect(txn.id, 'txn-1');
      expect(txn.status, 'held');
      expect(txn.grossAmount, 45000.0);
    });

    test(
        'maps a 404 response to a CheckoutException with the backend detail message',
        () async {
      final client = ApiClient(
          baseUrl: 'https://api.test', sessionStore: FakeSessionStore());
      client.dio.httpClientAdapter = FakeHttpClientAdapter(
        (options) =>
            (statusCode: 404, body: {'detail': 'Transaction not found'}),
      );
      final repository = CheckoutRepository(client);

      await expectLater(
        () => repository.getTransaction('does-not-exist'),
        throwsA(isA<CheckoutException>()
            .having((e) => e.message, 'message', 'Transaction not found')),
      );
    });

    test('maps a connection error to the sentinel "offline" message', () async {
      final client = ApiClient(
          baseUrl: 'https://api.test', sessionStore: FakeSessionStore());
      client.dio.httpClientAdapter = ConnectionErrorHttpClientAdapter();
      final repository = CheckoutRepository(client);

      await expectLater(
        () => repository.getTransaction('txn-1'),
        throwsA(isA<CheckoutException>()
            .having((e) => e.message, 'message', 'offline')),
      );
    });
  });

  group('CheckoutRepository.initiateCheckout', () {
    test('maps a 409 (expired hold) response to the "hold_expired" sentinel',
        () async {
      final client = ApiClient(
          baseUrl: 'https://api.test', sessionStore: FakeSessionStore());
      client.dio.httpClientAdapter = FakeHttpClientAdapter(
        (options) => (
          statusCode: 409,
          body: {'detail': 'Booking hold is no longer active.'}
        ),
      );
      final repository = CheckoutRepository(client);

      await expectLater(
        () => repository.initiateCheckout(
            transactionId: 'txn-1', idempotencyKey: 'idem-1'),
        throwsA(isA<CheckoutException>()
            .having((e) => e.message, 'message', 'hold_expired')),
      );
    });
  });
}
