/// Repository wrapping POST /v1/disputes (FEAT-026) -- lets a seeker/host
/// raise a dispute against one of their own transactions from Transaction
/// History. Everything else on the Dispute & Refund Management feature
/// (list/assign/resolve) is Staff/Admin-only and lives in the Admin Web
/// Console, not this mobile repository.
library;

import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';

/// Mirrors app/schemas/dispute.py's DISPUTE_REASONS.
enum DisputeReason {
  propertyNotAsDescribed,
  incorrectCharge,
  serviceIssue,
  other;

  String get apiValue => switch (this) {
        DisputeReason.propertyNotAsDescribed => 'property_not_as_described',
        DisputeReason.incorrectCharge => 'incorrect_charge',
        DisputeReason.serviceIssue => 'service_issue',
        DisputeReason.other => 'other',
      };

  String get label => switch (this) {
        DisputeReason.propertyNotAsDescribed =>
          'Property not as described',
        DisputeReason.incorrectCharge => 'Incorrect charge',
        DisputeReason.serviceIssue => 'Service issue',
        DisputeReason.other => 'Other',
      };
}

class DisputeException implements Exception {
  DisputeException(this.message);
  final String message;

  @override
  String toString() => message;
}

class RaisedDispute {
  const RaisedDispute({
    required this.id,
    required this.transactionId,
    required this.reason,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String transactionId;
  final String reason;
  final String status;
  final DateTime createdAt;

  factory RaisedDispute.fromJson(Map<String, dynamic> json) => RaisedDispute(
        id: json['id'] as String,
        transactionId: json['transaction_id'] as String,
        reason: json['reason'] as String,
        status: json['status'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class DisputeRepository {
  DisputeRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<RaisedDispute> raiseDispute({
    required String transactionId,
    required DisputeReason reason,
    required String description,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/v1/disputes',
        data: {
          'transaction_id': transactionId,
          'reason': reason.apiValue,
          'description': description,
        },
      );
      return RaisedDispute.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        throw DisputeException('offline');
      }
      final data = e.response?.data;
      if (data is Map && data['detail'] is String) {
        throw DisputeException(data['detail'] as String);
      }
      throw DisputeException('Could not submit your report. Please try again.');
    }
  }
}
