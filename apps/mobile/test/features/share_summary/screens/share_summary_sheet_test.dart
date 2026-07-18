import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:de_duke_mobile/core/api/api_client.dart';
import 'package:de_duke_mobile/core/auth/session_store.dart';
import 'package:de_duke_mobile/features/listings/data/listing_models.dart';
import 'package:de_duke_mobile/features/share_summary/data/share_repository.dart';
import 'package:de_duke_mobile/features/share_summary/screens/share_summary_sheet.dart';

import '../../../support/fake_http_adapter.dart';

class FakeSessionStore extends SessionStore {
  @override
  Future<String?> readAccessToken() async => 'fake-token';
}

Listing _buildListing() => Listing(
      id: 'listing-1',
      hostAccountId: 'host-account-1',
      listingType: 'commercial',
      title: 'Sunny Office Suite',
      description: 'A great space.',
      latitude: 6.5,
      longitude: 3.4,
      addressLine: '1 Broad Street',
      city: 'Lagos',
      state: 'Lagos',
      amenities: const [],
      status: 'active',
      viewCount: 0,
    );

void main() {
  late ApiClient client;

  setUp(() {
    client = ApiClient(baseUrl: 'https://api.test', sessionStore: FakeSessionStore());
  });

  Future<void> pumpSheet(WidgetTester tester, ShareRepository repository) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showShareSummarySheet(
                context,
                listing: _buildListing(),
                repository: repository,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('Preview state shows listing summary and Generate Link button',
      (tester) async {
    await pumpSheet(tester, ShareRepository(client));

    expect(find.text('Sunny Office Suite'), findsOneWidget);
    expect(find.text('Generate Link'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
  });

  testWidgets(
      'Generating a link transitions Preview -> Generated with copy/share/revoke actions',
      (tester) async {
    client.dio.httpClientAdapter = FakeHttpClientAdapter(
      (options) => (
        statusCode: 201,
        body: {
          'share_token': 'tok-abc123',
          'listing_id': 'listing-1',
          'expires_at': null,
        },
      ),
    );
    await pumpSheet(tester, ShareRepository(client));

    await tester.tap(find.text('Generate Link'));
    await tester.pumpAndSettle();

    expect(find.text('Generate Link'), findsNothing);
    expect(find.byIcon(Icons.copy), findsOneWidget);
    expect(find.byIcon(Icons.ios_share), findsOneWidget);
    expect(find.text('Revoke Link'), findsOneWidget);
  });

  testWidgets('Revoking a link returns the sheet to the Preview state',
      (tester) async {
    client.dio.httpClientAdapter = FakeHttpClientAdapter(
      (options) => options.method == 'DELETE'
          ? (statusCode: 200, body: {'share_token': 'tok-abc123', 'is_revoked': true})
          : (
              statusCode: 201,
              body: {
                'share_token': 'tok-abc123',
                'listing_id': 'listing-1',
                'expires_at': null,
              },
            ),
    );
    await pumpSheet(tester, ShareRepository(client));

    await tester.tap(find.text('Generate Link'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Revoke Link'));
    await tester.pumpAndSettle(); // confirmation dialog
    await tester.tap(find.text('Revoke'));
    await tester.pumpAndSettle();

    expect(find.text('Generate Link'), findsOneWidget);
    expect(find.text('Revoke Link'), findsNothing);
  });
}
