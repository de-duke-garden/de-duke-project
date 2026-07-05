/// Repository wrapping /v1/transactions and /v1/checkout endpoints
/// (FEAT-013/FEAT-032). Screens depend on this, never on Dio directly.
library;

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_client.dart';
import 'transaction_models.dart';

class CheckoutException implements Exception {
  CheckoutException(this.message);
  final String message;

  @override
  String toString() => message;
}

class InitiateCheckoutResult {
  const InitiateCheckoutResult({
    required this.transactionId,
    required this.status,
    required this.authorizationUrl,
  });

  final String transactionId;
  final String status;
  final String authorizationUrl;

  factory InitiateCheckoutResult.fromJson(Map<String, dynamic> json) =>
      InitiateCheckoutResult(
        transactionId: json['transaction_id'] as String,
        status: json['status'] as String,
        authorizationUrl: json['authorization_url'] as String,
      );
}

class CheckoutRepository {
  CheckoutRepository(this._apiClient);

  final ApiClient _apiClient;
  static const _uuid = Uuid();

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

  Future<TransactionDetail> getTransaction(String transactionId) async {
    try {
      final response =
          await _apiClient.dio.get('/v1/transactions/$transactionId');
      return TransactionDetail.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw CheckoutException(
          _errorMessage(e, 'Could not load this transaction.'));
    }
  }

  /// One idempotency key per checkout *attempt* -- callers should generate
  /// this once and reuse it across retries of the same payment attempt, per
  /// AGENTS.md (a retried request must never result in a duplicate charge).
  String newIdempotencyKey() => _uuid.v4();

  Future<InitiateCheckoutResult> initiateCheckout({
    required String transactionId,
    required String idempotencyKey,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/v1/checkout/initiate',
        data: {
          'transaction_id': transactionId,
          'idempotency_key': idempotencyKey
        },
      );
      return InitiateCheckoutResult.fromJson(
          response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        throw CheckoutException('hold_expired');
      }
      throw CheckoutException(
          _errorMessage(e, 'Could not start payment. Please try again.'));
    }
  }
}
