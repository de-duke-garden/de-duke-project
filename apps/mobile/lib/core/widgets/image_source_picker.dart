/// Shared camera/gallery chooser -- screens.md requires every photo/document
/// picker (Become a Host document submission, Create Listing photo grid) to
/// support both capture and gallery selection. Centralized here so both
/// features go through the same bottom sheet and the same image_picker
/// configuration instead of duplicating it.
library;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Shows a bottom sheet offering "Take Photo" / "Choose from Gallery", then
/// invokes `image_picker` with the chosen source. Returns the picked file's
/// local path, or null if the user dismissed the sheet or picker without
/// selecting anything.
///
/// `imageQuality` downsizes/compresses on-device before upload -- documents
/// and profile photos don't need full sensor resolution, and this keeps
/// multipart submission fast on slower connections.
Future<String?> pickImageFromCameraOrGallery(
  BuildContext context, {
  int imageQuality = 85,
}) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take Photo'),
            onTap: () => Navigator.of(context).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from Gallery'),
            onTap: () => Navigator.of(context).pop(ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;

  final picker = ImagePicker();
  try {
    final picked =
        await picker.pickImage(source: source, imageQuality: imageQuality);
    return picked?.path;
  } on Exception {
    // Permission denied, camera unavailable, etc. -- caller's existing
    // "Please add a profile photo" / required-field validation already
    // covers the resulting empty-selection state, so no separate error
    // surface is needed here.
    return null;
  }
}
