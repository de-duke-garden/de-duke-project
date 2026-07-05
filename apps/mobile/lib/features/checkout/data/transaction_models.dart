/// Data models mirroring apps/backend/app/schemas/transaction.py.
library;

class TransactionSummary {
  const TransactionSummary({
    required this.id,
    required this.listingId,
    required this.transactionType,
    required this.status,
    required this.grossAmount,
    required this.commissionAmount,
    required this.netPayoutAmount,
    required this.createdAt,
  });

  final String id;
  final String listingId;
  final String transactionType;
  // held | pending_payment | succeeded | failed | expired | refunded
  final String status;
  final double grossAmount;
  final double commissionAmount;
  final double netPayoutAmount;
  final DateTime createdAt;

  factory TransactionSummary.fromJson(Map<String, dynamic> json) =>
      TransactionSummary(
        id: json['id'] as String,
        listingId: json['listing_id'] as String,
        transactionType: json['transaction_type'] as String,
        status: json['status'] as String,
        grossAmount: (json['gross_amount'] as num).toDouble(),
        commissionAmount: (json['commission_amount'] as num).toDouble(),
        netPayoutAmount: (json['net_payout_amount'] as num).toDouble(),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class TransactionDetail extends TransactionSummary {
  TransactionDetail({
    required super.id,
    required super.listingId,
    required super.transactionType,
    required super.status,
    required super.grossAmount,
    required super.commissionAmount,
    required super.netPayoutAmount,
    required super.createdAt,
    required this.payerId,
    required this.payeeId,
    this.paidAt,
    this.holdExpiresAt,
    this.receiptUrl,
  });

  final String payerId;
  final String payeeId;
  final DateTime? paidAt;
  final DateTime? holdExpiresAt;
  final String? receiptUrl;

  factory TransactionDetail.fromJson(Map<String, dynamic> json) =>
      TransactionDetail(
        id: json['id'] as String,
        listingId: json['listing_id'] as String,
        transactionType: json['transaction_type'] as String,
        status: json['status'] as String,
        grossAmount: (json['gross_amount'] as num).toDouble(),
        commissionAmount: (json['commission_amount'] as num).toDouble(),
        netPayoutAmount: (json['net_payout_amount'] as num).toDouble(),
        createdAt: DateTime.parse(json['created_at'] as String),
        payerId: json['payer_id'] as String,
        payeeId: json['payee_id'] as String,
        paidAt: json['paid_at'] != null
            ? DateTime.parse(json['paid_at'] as String)
            : null,
        holdExpiresAt: json['hold_expires_at'] != null
            ? DateTime.parse(json['hold_expires_at'] as String)
            : null,
        receiptUrl: json['receipt_url'] as String?,
      );
}
