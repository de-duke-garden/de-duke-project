/// T-023 coverage for `uploadContentTypeForPath`: every multipart upload
/// call site derives its part content type from this lookup, so the map
/// must match the formats the app's pickers produce exactly, and an
/// unrecognized extension must fall through to Dio's own path-extension
/// lookup (never silently octet-stream).
library;

import 'package:dio/dio.dart' show DioMediaType, MultipartFile;
import 'package:flutter_test/flutter_test.dart';

import 'package:de_duke_mobile/core/utils/upload_mime.dart';

void main() {
  String? mimeTypeFor(String path) => uploadContentTypeForPath(path)?.mimeType;

  test('maps image_picker photo output to its real image type', () {
    expect(mimeTypeFor('/data/user/0/cache/IMG_0001.jpg'), 'image/jpeg');
    expect(mimeTypeFor('/data/user/0/cache/IMG_0001.jpeg'), 'image/jpeg');
    expect(mimeTypeFor('/data/user/0/cache/IMG_0001.JPG'), 'image/jpeg');
    expect(
        mimeTypeFor('C:\\Users\\amaka\\Pictures\\screenshot.png'), 'image/png');
    expect(mimeTypeFor('/var/mobile/Containers/photo.webp'), 'image/webp');
  });

  test('maps picked video output to its real video type', () {
    // Android camera and most gallery clips arrive as .mp4...
    expect(mimeTypeFor('/data/user/0/cache/VID_0001.mp4'), 'video/mp4');
    // ...but the iOS camera records QuickTime .mov, and the bytes are
    // quicktime -- mislabeling them video/mp4 would repeat the octet-
    // stream bug with a plausible-looking lie.
    expect(
        mimeTypeFor('/var/mobile/Containers/VID_0001.MOV'), 'video/quicktime');
  });

  test('maps PDFs for any future document picker', () {
    expect(mimeTypeFor('/storage/emulated/0/Download/CAC_cert.pdf'),
        'application/pdf');
  });

  test('falls through to Dio extension lookup for unmapped-but-known types',
      () {
    // e.g. iOS gallery HEIC picks: still image/heic, not octet-stream.
    expect(mimeTypeFor('/var/mobile/photo.heic'), 'image/heic');
    // An unmapped-in-our-table extension is not a license for
    // octet-stream either: Dio's own lookup still classifies it from the
    // path (mime's table maps .xyz to chemical/x-xyz).
    expect(mimeTypeFor('/tmp/blobfile.xyz'), 'chemical/x-xyz');
  });

  test('returns null for extensions nothing recognizes', () {
    expect(uploadContentTypeForPath('/tmp/blobfile.zzznotreal'), isNull);
  });

  test('returns null for paths without an extension', () {
    expect(uploadContentTypeForPath('/tmp/profile_photo'), isNull);
    expect(uploadContentTypeForPath(''), isNull);
  });

  test('returned objects are real Dio MediaTypes usable on MultipartFile', () {
    final type = uploadContentTypeForPath('/tmp/photo.jpg');
    expect(type, isA<DioMediaType>());
    // Compare by media type string, not object identity: http_parser's
    // MediaType equality also weighs the parameters map, which differs
    // between a directly constructed instance and a parsed one.
    expect(
      type?.mimeType,
      MultipartFile.lookupMediaType('/tmp/photo.jpg')?.mimeType,
    );
  });
}
