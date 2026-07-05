/// Repository wrapping the Backend API Service's /v1/host-accounts
/// endpoints (FEAT-002). Screens depend on this, never on Dio directly.
library;

import 'dart:convert';

import 'package:dio/dio.dart';

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

    final formMap = <String, dynamic>{
      'submission': jsonEncode(submission),
      'files': [
        await MultipartFile.fromFile(profilePhotoLocalPath,
            filename: profilePhotoTempKey),
        for (final doc in documents)
          await MultipartFile.fromFile(doc.localPath, filename: doc.tempKey),
      ],
    };

    try {
      final response = await _apiClient.dio.post(
        '/v1/host-accounts',
        data: FormData.fromMap(formMap),
      );
      return HostAccountStatus.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw HostAccountException(
          _errorMessage(e, 'Could not submit your application.'));
    }
  }
}
