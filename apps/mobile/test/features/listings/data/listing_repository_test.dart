/// T-023 coverage for ListingRepository.uploadMedia's multipart parts:
/// each `file_<tempKey>` part must carry an explicit, extension-derived
/// content type (previously Dio guessed from the part filename, which
/// worked only while the picked path's extension mapped cleanly -- now it
/// is pinned to the picked file's extension either way), and the part
/// filename keeps the picked file's real extension (these parts are
/// matched by field name, not filename, per the frozen T-023 decisions).
library;

import 'dart:io';

import 'package:dio/dio.dart' show FormData, RequestOptions;
import 'package:flutter_test/flutter_test.dart';

import 'package:de_duke_mobile/core/api/api_client.dart';
import 'package:de_duke_mobile/core/auth/session_store.dart';
import 'package:de_duke_mobile/features/listings/data/listing_models.dart';
import 'package:de_duke_mobile/features/listings/data/listing_repository.dart';

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

Future<String> _writeTempFile(String name) async {
  final dir = await Directory.systemTemp.createTemp('listing_repo_test');
  final file = File('${dir.path}/$name');
  await file.writeAsBytes([0, 1, 2, 3]);
  return file.path;
}

void main() {
  test(
      'T-023: sends one content-typed part per media item, keyed by its tempKey',
      () async {
    RequestOptions? captured;
    final client = ApiClient(
        baseUrl: 'https://api.test', sessionStore: FakeSessionStore());
    client.dio.httpClientAdapter = FakeHttpClientAdapter((options) {
      captured = options;
      return (
        statusCode: 200,
        body: {
          'media': [
            {
              'id': 'media-1',
              'media_type': 'image',
              'media_url': 'https://cdn.test/a.jpg',
              'display_order': 0,
              'is_primary': true,
            },
            {
              'id': 'media-2',
              'media_type': 'video',
              'media_url': 'https://cdn.test/b.mp4',
              'processing_status': 'pending',
              'display_order': 1,
              'is_primary': false,
            },
          ],
        },
      );
    });
    final repository = ListingRepository(client);

    final photoPath = await _writeTempFile('IMG_1.webp');
    final videoPath = await _writeTempFile('VID_1.mp4');

    final result = await repository.uploadMedia('listing-1', [
      PendingListingMedia(
        tempKey: 'img_0',
        localPath: photoPath,
        mediaType: 'image',
        displayOrder: 0,
        isPrimary: true,
      ),
      PendingListingMedia(
        tempKey: 'vid_0',
        localPath: videoPath,
        mediaType: 'video',
        displayOrder: 1,
      ),
    ]);

    expect(result.length, 2);
    expect(result[0].id, 'media-1');
    expect(result[1].processingStatus, 'pending');

    final parts = (captured!.data as FormData).files;
    expect(parts.length, 2);

    final imagePart = parts.singleWhere((part) => part.key == 'file_img_0');
    // Part filename keeps the picked file's real extension -- accurate to
    // the bytes, never a repurposed temp key for these (non-correlated)
    // parts.
    expect(imagePart.value.filename, 'IMG_1.webp');
    expect(imagePart.value.contentType?.mimeType, 'image/webp');

    final videoPart = parts.singleWhere((part) => part.key == 'file_vid_0');
    expect(videoPart.value.filename, 'VID_1.mp4');
    expect(videoPart.value.contentType?.mimeType, 'video/mp4');
  });
}
