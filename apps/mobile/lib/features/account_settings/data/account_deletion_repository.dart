/// Repository wrapping the Backend API Service's /v1/account-deletion
/// endpoint (FEAT-030, NDPR compliance).
library;

import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';

class AccountDeletionResult {
  const AccountDeletionResult({
    required this.deletedImmediately,
    required this.anonymizedImmediately,
    required this.retainedForADefinedPeriod,
    required this.confirmationEmail,
  });

  final List<String> deletedImmediately;
  final List<String> anonymizedImmediately;
  final List<String> retainedForADefinedPeriod;
  final String confirmationEmail;

  factory AccountDeletionResult.fromJson(Map<String, dynamic> json) =>
      AccountDeletionResult(
        deletedImmediately: (json['deleted_immediately'] as List? ?? [])
            .map((e) => e as String)
            .toList(),
        anonymizedImmediately: (json['anonymized_immediately'] as List? ?? [])
            .map((e) => e as String)
            .toList(),
        retainedForADefinedPeriod:
            (json['retained_for_a_defined_period'] as List? ?? [])
                .map((e) => e as String)
                .toList(),
        confirmationEmail: json['confirmation_email'] as String? ?? '',
      );
}

class AccountDeletionException implements Exception {
  AccountDeletionException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AccountDeletionRepository {
  AccountDeletionRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<AccountDeletionResult> requestDeletion() async {
    try {
      final response =
          await _apiClient.dio.post('/v1/account-deletion/request');
      return AccountDeletionResult.fromJson(
          response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      final data = e.response?.data;
      final detail = (data is Map && data['detail'] is String)
          ? data['detail'] as String
          : 'Could not process your deletion request. Please try again.';
      throw AccountDeletionException(detail);
    }
  }
}
