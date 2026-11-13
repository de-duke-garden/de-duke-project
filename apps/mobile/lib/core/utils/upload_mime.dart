/// Multipart upload content-type resolution (T-023).
///
/// Every `MultipartFile.fromFile` call site must send an explicit
/// `contentType`. Why: the backend persists each upload with the multipart
/// part's content type (falling back to extension sniffing only when the
/// part carries none), so a part whose content type is missing ends up
/// served from the media CDN as `application/octet-stream` -- which the
/// time was for every host-verification upload, whose part filenames are
/// bare temp keys (`profile_photo`, `cac_cert_doc_url`) with no extension
/// for anything to sniff. This is mobile-side half of the fix: derive the
/// type from the picked file's own path extension, never from the part
/// filename, and never claim a type the bytes don't have (e.g. never
/// `image/jpeg` for a `.png`).
library;

import 'package:dio/dio.dart' show DioMediaType, MultipartFile;

/// Content type for a locally picked upload file, or null when the path's
/// extension is unrecognized (the caller then passes null through and Dio
/// falls back to its own extension lookup, which reads the same path, so
/// the behavior for exotic-but-recognizable types is unchanged).
///
/// Extension map covers every format the app's pickers can realistically
/// hand back: `image_picker`'s compressed photos (JPEG), gallery picks
/// (PNG/WebP, HEIC on some iOS galleries), `pickVideo` output (MP4 from
/// Android and most galleries; QuickTime .mov from the iOS camera), and
/// PDFs from any future document picker. `.mov` maps to
/// `video/quicktime` because that is what the bytes are -- mislabeling it
/// `video/mp4` would repeat the octet-stream problem with a plausible lie.
DioMediaType? uploadContentTypeForPath(String path) {
  final name = path.toLowerCase();
  final dot = name.lastIndexOf('.');
  if (dot == -1) return null;
  final ext = name.substring(dot + 1);
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return DioMediaType('image', 'jpeg');
    case 'png':
      return DioMediaType('image', 'png');
    case 'webp':
      return DioMediaType('image', 'webp');
    case 'mp4':
      return DioMediaType('video', 'mp4');
    case 'mov':
      return DioMediaType('video', 'quicktime');
    case 'pdf':
      return DioMediaType('application', 'pdf');
  }
  // Not in the explicit map: defer to Dio's own filename/extension lookup
  // (package:mime's table) so e.g. `.heic` still travels as image/heic
  // rather than silently degrading to application/octet-stream.
  return MultipartFile.lookupMediaType(path);
}
