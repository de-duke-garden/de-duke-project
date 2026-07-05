/// Repository wrapping GET /v1/transactions (FEAT-015). Reuses the
/// TransactionSummary/TransactionDetail models from the checkout feature
/// (same backend entity, schemas/transaction.py), rather than duplicating
/// them.
library;

import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../checkout/data/transaction_models.dart';

class TransactionsException implements Exception {
  TransactionsException(this.message);
  final String message;

  @override
  String toString() => message;
}

class TransactionsPage {
  const TransactionsPage({required this.items, required this.nextCursor});
  final List<TransactionSummary> items;
  final String? nextCursor;
}

class TransactionsRepository {
  TransactionsRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<TransactionsPage> listTransactions(
      {String? cursor, int limit = 20}) async {
    try {
      final response = await _apiClient.dio.get(
        '/v1/transactions',
        queryParameters: {if (cursor != null) 'cursor': cursor, 'limit': limit},
      );
      final data = response.data as Map<String, dynamic>;
      return TransactionsPage(
        items: (data['items'] as List)
            .map((e) => TransactionSummary.fromJson(e as Map<String, dynamic>))
            .toList(),
        nextCursor: data['next_cursor'] as String?,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        throw TransactionsException('offline');
      }
      throw TransactionsException('Could not load your transactions.');
    }
  }
}
