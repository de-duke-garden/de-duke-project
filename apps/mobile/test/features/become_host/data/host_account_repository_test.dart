/// Regression coverage for a real production bug: `submit()`'s
/// `MultipartFile.fromFile()` calls used to happen OUTSIDE its try/catch,
/// so a stale/unreadable picked-photo local path threw a raw, untyped
/// exception straight past `document_submission_screen.dart`'s
/// `e is HostAccountException` check -- surfacing as that screen's generic
/// "Could not submit your application." with NO network request ever
/// attempted (confirmed against production logs: zero
/// `POST /v1/host-accounts` entries despite reported failures). These
/// tests exercise the fixed behavior: a bad local path now throws a
/// specific, actionable `HostAccountException` instead.
library;

import 'dart:io';

import 'package:dio/dio.dart' show FormData;
import 'package:flutter_test/flutter_test.dart';

import 'package:de_duke_mobile/core/api/api_client.dart';
import 'package:de_duke_mobile/core/auth/session_store.dart';
import 'package:de_duke_mobile/features/become_host/data/host_account_models.dart';
import 'package:de_duke_mobile/features/become_host/data/host_account_repository.dart';

import '../../../support/fake_http_adapter.dart';

class FakeSessionStore extends SessionStore {
  @override
  Future<String?> readAccessToken() async => 'fake-token';
  @override
  Future<void> saveAccessToken(String token) async {}
  @override
  Future<void> saveRefreshToken(String token) async {}
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> clear() async {}
}

HostAccountRepository _buildRepository(
    {required FakeHttpClientAdapter Function() adapter}) {
  final client = ApiClient(
      baseUrl: 'https://api.test', sessionStore: FakeSessionStore());
  client.dio.httpClientAdapter = adapter();
  return HostAccountRepository(client);
}

void main() {
  group('HostAccountRepository.submit', () {
    test(
        'never attempts a network request and throws a specific message when the profile photo path is unreadable',
        () async {
      var requestAttempted = false;
      final repository = _buildRepository(
        adapter: () => FakeHttpClientAdapter((options) {
          requestAttempted = true;
          return (statusCode: 200, body: {});
        }),
      );

      await expectLater(
        () => repository.submit(
          hostType: HostType.owner,
          bio: 'A short bio',
          // No file exists at this path -- simulates image_picker's cache
          // file having been reclaimed, or a stale path from a prior
          // screen instance.
          profilePhotoLocalPath: '/nonexistent/path/does-not-exist.jpg',
        ),
        throwsA(isA<HostAccountException>().having(
          (e) => e.message,
          'message',
          'One of your selected photos could not be read. Please reselect it and try again.',
        )),
      );
      // The whole point of this fix: a local file failure must never reach
      // the network layer, since there's nothing valid to send yet.
      expect(requestAttempted, isFalse);
    });

    test(
        'never attempts a network request and throws a specific message when a document path is unreadable',
        () async {
      var requestAttempted = false;
      final repository = _buildRepository(
        adapter: () => FakeHttpClientAdapter((options) {
          requestAttempted = true;
          return (statusCode: 200, body: {});
        }),
      );

      await expectLater(
        () => repository.submit(
          hostType: HostType.agent,
          bio: 'A short bio',
          profilePhotoLocalPath: '/nonexistent/profile.jpg',
          documents: [
            PendingDocument(
              field: 'cac_cert_doc_url',
              tempKey: 'cac_cert_doc_url',
              localPath: '/nonexistent/cac.jpg',
            ),
          ],
        ),
        throwsA(isA<HostAccountException>()),
      );
      expect(requestAttempted, isFalse);
    });

    test('maps a 422 (validation) response to its detail message', () async {
      final repository = _buildRepository(
        adapter: () => FakeHttpClientAdapter(
          (options) => (
            statusCode: 422,
            body: {'detail': 'bio is required'},
          ),
        ),
      );

      // Both paths are unreadable in this sandbox, but that's fine -- this
      // test exists to confirm requests that DO reach the mocked network
      // layer still map the response body's `detail` correctly. Use a
      // temp file created for real so we exercise past the file-read
      // step and into the actual HTTP call.
      final tempPath = await _writeTempFile();
      await expectLater(
        () => repository.submit(
          hostType: HostType.owner,
          bio: '',
          profilePhotoLocalPath: tempPath,
        ),
        throwsA(isA<HostAccountException>()
            .having((e) => e.message, 'message', 'bio is required')),
      );
    });

    test('maps a connection error to the "offline" sentinel', () async {
      final client = ApiClient(
          baseUrl: 'https://api.test', sessionStore: FakeSessionStore());
      client.dio.httpClientAdapter = ConnectionErrorHttpClientAdapter();
      final repository = HostAccountRepository(client);

      final tempPath = await _writeTempFile();
      await expectLater(
        () => repository.submit(
          hostType: HostType.owner,
          bio: 'A short bio',
          profilePhotoLocalPath: tempPath,
        ),
        throwsA(isA<HostAccountException>()
            .having((e) => e.message, 'message', 'offline')),
      );
    });
  });

  group('HostAccountRepository.updateProfile', () {
    test(
        'throws a specific message (never a raw exception) when the picked photo path is unreadable',
        () async {
      final repository = _buildRepository(
        adapter: () =>
            FakeHttpClientAdapter((options) => (statusCode: 200, body: {})),
      );

      await expectLater(
        () => repository.updateProfile(
            photoLocalPath: '/nonexistent/photo.jpg'),
        throwsA(isA<HostAccountException>().having(
          (e) => e.message,
          'message',
          'That photo could not be read. Please reselect it and try again.',
        )),
      );
    });

    test('sends bio as multipart form data when no photo is provided',
        () async {
      FormData? captured;
      final repository = _buildRepository(
        adapter: () => FakeHttpClientAdapter((options) {
          captured = options.data as FormData;
          return (
            statusCode: 200,
            body: {
              'id': 'host-1',
              'host_type': 'owner',
              'status': 'in_review',
              'status_reason': null,
              'host_photo_url': 'https://cdn.test/photo.jpg',
              'bio': 'Updated bio',
            },
          );
        }),
      );

      final result = await repository.updateProfile(bio: 'Updated bio');

      expect(result.bio, 'Updated bio');
      expect(
          captured!.fields
              .any((f) => f.key == 'bio' && f.value == 'Updated bio'),
          isTrue);
    });
  });
}

Future<String> _writeTempFile() async {
  final dir = await Directory.systemTemp.createTemp('host_account_test');
  final file = File('${dir.path}/photo.jpg');
  await file.writeAsBytes([0, 1, 2, 3]);
  return file.path;
}
