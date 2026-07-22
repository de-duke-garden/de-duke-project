/// Repository wrapping /v1/wallet/* (FEAT-044/045). Screens depend on
/// this, never on Dio directly.
library;

import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import 'wallet_models.dart';

class WalletException implements Exception {
  WalletException(this.message);
  final String message;

  @override
  String toString() => message;
}

class WalletRepository {
  WalletRepository(this._apiClient);

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

  Future<WalletSummary> getWallet() async {
    try {
      final response = await _apiClient.dio.get('/v1/wallet');
      return WalletSummary.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw WalletException(_errorMessage(e, 'Could not load your wallet.'));
    }
  }

  Future<WalletLedgerPage> getLedger({String? before}) async {
    try {
      final response = await _apiClient.dio.get(
        '/v1/wallet/transactions',
        queryParameters: {if (before != null) 'before': before},
      );
      final data = response.data as Map<String, dynamic>;
      return WalletLedgerPage(
        items: (data['items'] as List)
            .map((e) => WalletLedgerEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        nextCursor: data['next_cursor'] as String?,
      );
    } on DioException catch (e) {
      throw WalletException(
          _errorMessage(e, 'Could not load your wallet history.'));
    }
  }

  Future<List<BankOption>> listBanks() async {
    try {
      final response = await _apiClient.dio.get('/v1/wallet/banks');
      return (response.data as List)
          .map((e) => BankOption.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw WalletException(_errorMessage(e, 'Could not load banks.'));
    }
  }

  Future<PayoutSettings?> getPayoutSettings() async {
    try {
      final response = await _apiClient.dio.get('/v1/wallet/payout-settings');
      if (response.data == null) return null;
      return PayoutSettings.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw WalletException(
          _errorMessage(e, 'Could not load your payout settings.'));
    }
  }

  /// Resolves + saves in one call -- the backend runs Paystack's account
  /// resolution and Transfer Recipient creation before persisting anything
  /// (payout_settings_service.save_payout_settings), so a resolution
  /// failure here means nothing was saved at all (FEAT-045 AC).
  Future<PayoutSettings> savePayoutSettings({
    required String accountNumber,
    required String bankCode,
    required String bankName,
  }) async {
    try {
      final response = await _apiClient.dio.put(
        '/v1/wallet/payout-settings',
        data: {
          'account_number': accountNumber,
          'bank_code': bankCode,
          'bank_name': bankName,
        },
      );
      return PayoutSettings.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw WalletException(
          _errorMessage(e, 'Could not verify and save that account.'));
    }
  }

  Future<WithdrawalRequestItem> requestWithdrawal(double amount) async {
    try {
      final response = await _apiClient.dio
          .post('/v1/wallet/withdrawals', data: {'amount': amount});
      return WithdrawalRequestItem.fromJson(
          response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw WalletException(
          _errorMessage(e, 'Could not start this withdrawal.'));
    }
  }

  Future<List<WithdrawalRequestItem>> listWithdrawals() async {
    try {
      final response = await _apiClient.dio.get('/v1/wallet/withdrawals');
      return (response.data as List)
          .map((e) =>
              WithdrawalRequestItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw WalletException(
          _errorMessage(e, 'Could not load your withdrawals.'));
    }
  }
}
