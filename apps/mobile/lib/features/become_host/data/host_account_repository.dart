/// Repository wrapping the Backend API Service's /v1/host-accounts
/// endpoints (FEAT-002). Screens depend on this, never on Dio directly.
library;

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/api/api_client.dart';
import 'host_account_models.dart';

class HostAccountException implements Exception {
  HostAccountException(this.message);
  final String message;

  @override
  String toString() => message;
}

class HostAccountRepository {
  HostAccountRepository(this._apiClient);

  final ApiClient _apiClient;

  String _errorMessage(DioException e, String fallback) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return 'offline';
    }
    final data = e.response?.data;
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
    return fallback;
  }

  /// Screen 3a data need: current submission status, if any. Returns null
  /// if the user has never started the Become a Host flow.
  Future<HostAccountStatus?> getMySubmission() async {
    try {
      final response = await _apiClient.dio.get('/v1/host-accounts/me');
      if (response.data == null) return null;
      return HostAccountStatus.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw HostAccountException(
          _errorMessage(e, 'Could not load your verification status.'));
    }
  }

  /// Screen 3b Submit button. Uses the structured multi-file upload
  /// contract: a JSON `submission` part plus one `files` multipart entry
  /// per document, each with its filename set to its declared temp_key so
  /// the backend can match it without index-encoded field names.
  ///
  /// Reading the picked local files (`MultipartFile.fromFile`) used to
  /// happen OUTSIDE this method's try/catch, so a stale/unreadable local
  /// path (e.g. the OS reclaiming `image_picker`'s cache file between
  /// picking a photo and tapping Submit, or -- on some Android
  /// versions/OEM galleries -- a content:// URI `dart:io File` can't read
  /// directly) threw a raw, un-typed exception straight past this
  /// repository, past `document_submission_screen.dart`'s
  /// `e is HostAccountException` check, and surfaced as that screen's
  /// generic fallback message -- indistinguishable from an actual network
  /// failure, and with NO request ever reaching the Backend API Service
  /// (confirmed against production CloudWatch logs: zero
  /// `POST /v1/host-accounts` entries across 30 days despite reported
  /// failures). Wrapping the whole method fixes that: local file failures
  /// now get their own specific, actionable `HostAccountException` instead
  /// of being indistinguishable from "the server rejected this."
  Future<HostAccountStatus> submit({
    required HostType hostType,
    required String bio,
    required String profilePhotoLocalPath,
    List<PendingDocument> documents = const [],
    String? nbaEnrolNo,
    String? arconRegNo,
    String? surconRegNo,
    String? refPhoneNo,
  }) async {
    const profilePhotoTempKey = 'profile_photo';
    final submission = {
      'host_type': hostType.apiValue,
      'bio': bio,
      'profile_photo_temp_key': profilePhotoTempKey,
      'documents': documents.map((d) => d.toMetaJson()).toList(),
      if (nbaEnrolNo != null) 'nba_enrol_no': nbaEnrolNo,
      if (arconRegNo != null) 'arcon_reg_no': arconRegNo,
      if (surconRegNo != null) 'surcon_reg_no': surconRegNo,
      if (refPhoneNo != null) 'ref_phone_no': refPhoneNo,
    };

    debugPrint('host_account_repository: submit() starting, reading ${1 + documents.length} local file(s)');

    final List<MultipartFile> files;
    try {
      files = [
        await MultipartFile.fromFile(profilePhotoLocalPath,
            filename: profilePhotoTempKey),
        for (final doc in documents)
          await MultipartFile.fromFile(doc.localPath, filename: doc.tempKey),
      ];
    } catch (e, stackTrace) {
      // No crash-reporting SDK is wired into this app yet. Logged via BOTH
      // dart:developer.log (posts to the VM service's Logging stream --
      // visible in DevTools, but NOT auto-printed by `flutter attach`/`run`
      // consoles) and debugPrint (goes through the Dart print zone, which
      // IS surfaced by `flutter attach`/`run` AND appears in `adb logcat`
      // under the "flutter" tag even for a standalone-launched debug
      // build) so this is diagnosable however the device is being
      // inspected.
      developer.log(
        'HostAccountRepository.submit: failed to read a picked local file',
        name: 'host_account_repository',
        error: e,
        stackTrace: stackTrace,
      );
      debugPrint('host_account_repository: submit() failed reading a local file: $e\n$stackTrace');
      throw HostAccountException(
          'One of your selected photos could not be read. Please reselect it and try again.');
    }

    debugPrint('host_account_repository: submit() local files read OK, POSTing to /v1/host-accounts');

    final formMap = <String, dynamic>{
      'submission': jsonEncode(submission),
      'files': files,
    };

    try {
      final response = await _apiClient.dio.post(
        '/v1/host-accounts',
        data: FormData.fromMap(formMap),
      );
      debugPrint('host_account_repository: submit() succeeded');
      return HostAccountStatus.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      debugPrint('host_account_repository: submit() DioException: ${e.type} ${e.message} response=${e.response?.statusCode} ${e.response?.data}');
      throw HostAccountException(
          _errorMessage(e, 'Could not submit your application.'));
    }
  }

  /// FEAT-042 -- Host Dashboard's Edit Host Profile bottom sheet. Bio
  /// and/or photo, no document resubmission; the backend blocks this (403)
  /// while the most recent submission is `in_review`. Both params are
  /// optional and independent -- pass whichever changed; at least one must
  /// be non-null (the backend also enforces this, 422 otherwise).
  Future<HostAccountStatus> updateProfile({
    String? bio,
    String? photoLocalPath,
  }) async {
    MultipartFile? photo;
    if (photoLocalPath != null) {
      try {
        photo = await MultipartFile.fromFile(photoLocalPath);
      } catch (e, stackTrace) {
        developer.log(
          'HostAccountRepository.updateProfile: failed to read the picked local photo',
          name: 'host_account_repository',
          error: e,
          stackTrace: stackTrace,
        );
        throw HostAccountException(
            'That photo could not be read. Please reselect it and try again.');
      }
    }
    final formMap = <String, dynamic>{
      if (bio != null) 'bio': bio,
      if (photo != null) 'photo': photo,
    };
    try {
      final response = await _apiClient.dio.patch(
        '/v1/host-accounts/me',
        data: FormData.fromMap(formMap),
      );
      return HostAccountStatus.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw HostAccountException(
          _errorMessage(e, 'Could not save your host profile.'));
    }
  }
}
