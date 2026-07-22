/// FEAT-043/044/045 -- Wallet, WalletTransaction (ledger entry),
/// PayoutSettings, WithdrawalRequest, BankOption. Mirrors
/// app/schemas/wallet.py's response shapes.
library;

class WalletSummary {
  const WalletSummary({
    required this.id,
    required this.ownerId,
    required this.balance,
    required this.currency,
    required this.updatedAt,
  });

  final String id;
  final String ownerId;
  final double balance;
  final String currency;
  final DateTime updatedAt;

  factory WalletSummary.fromJson(Map<String, dynamic> json) => WalletSummary(
        id: json['id'] as String,
        ownerId: json['owner_id'] as String,
        balance: (json['balance'] as num).toDouble(),
        currency: json['currency'] as String,
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}

class WalletLedgerEntry {
  const WalletLedgerEntry({
    required this.id,
    required this.direction,
    required this.amount,
    required this.sourceType,
    required this.sourceId,
    required this.balanceAfter,
    required this.notes,
    required this.createdAt,
  });

  final String id;
  // credit | debit
  final String direction;
  final double amount;
  // transaction_release | withdrawal | withdrawal_reversal | manual_adjustment
  final String sourceType;
  final String? sourceId;
  final double balanceAfter;
  final String? notes;
  final DateTime createdAt;

  factory WalletLedgerEntry.fromJson(Map<String, dynamic> json) =>
      WalletLedgerEntry(
        id: json['id'] as String,
        direction: json['direction'] as String,
        amount: (json['amount'] as num).toDouble(),
        sourceType: json['source_type'] as String,
        sourceId: json['source_id'] as String?,
        balanceAfter: (json['balance_after'] as num).toDouble(),
        notes: json['notes'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class WalletLedgerPage {
  const WalletLedgerPage({required this.items, required this.nextCursor});
  final List<WalletLedgerEntry> items;
  final String? nextCursor;
}

class PayoutSettings {
  const PayoutSettings({
    required this.id,
    required this.accountNumber,
    required this.bankCode,
    required this.bankName,
    required this.accountHolderName,
    required this.verificationStatus,
    required this.updatedAt,
  });

  final String id;
  final String accountNumber;
  final String bankCode;
  final String bankName;
  final String accountHolderName;
  // unverified | verified | failed
  final String verificationStatus;
  final DateTime updatedAt;

  bool get isVerified => verificationStatus == 'verified';

  factory PayoutSettings.fromJson(Map<String, dynamic> json) =>
      PayoutSettings(
        id: json['id'] as String,
        accountNumber: json['account_number'] as String,
        bankCode: json['bank_code'] as String,
        bankName: json['bank_name'] as String,
        accountHolderName: json['account_holder_name'] as String,
        verificationStatus: json['verification_status'] as String,
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}

class BankOption {
  const BankOption({required this.name, required this.code});
  final String name;
  final String code;

  factory BankOption.fromJson(Map<String, dynamic> json) => BankOption(
        name: json['name'] as String,
        code: json['code'] as String,
      );
}

class WithdrawalRequestItem {
  const WithdrawalRequestItem({
    required this.id,
    required this.walletId,
    required this.amount,
    required this.status,
    required this.requestedAt,
    required this.paystackTransferReference,
    required this.fulfilledAt,
    required this.failureReason,
  });

  final String id;
  final String walletId;
  final double amount;
  // requested | processing | paid | failed
  final String status;
  final DateTime requestedAt;
  final String? paystackTransferReference;
  final DateTime? fulfilledAt;
  final String? failureReason;

  factory WithdrawalRequestItem.fromJson(Map<String, dynamic> json) =>
      WithdrawalRequestItem(
        id: json['id'] as String,
        walletId: json['wallet_id'] as String,
        amount: (json['amount'] as num).toDouble(),
        status: json['status'] as String,
        requestedAt: DateTime.parse(json['requested_at'] as String),
        paystackTransferReference:
            json['paystack_transfer_reference'] as String?,
        fulfilledAt: json['fulfilled_at'] != null
            ? DateTime.parse(json['fulfilled_at'] as String)
            : null,
        failureReason: json['failure_reason'] as String?,
      );
}
