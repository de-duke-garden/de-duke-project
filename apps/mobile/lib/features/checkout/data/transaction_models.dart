/// Data models mirroring apps/backend/app/schemas/transaction.py.
library;

// Bug fix: `Transaction.status`'s old 'succeeded' value was renamed to
// 'payment_received' (plus a new 'released_to_wallet' status added) when
// the escrow/wallet model shipped on the backend -- every mobile screen
// still checking for the literal string 'succeeded' silently stopped
// recognizing a paid transaction as paid. Both values below mean "the
// guest's payment succeeded" from this app's point of view (the
// difference between them is purely about whether a De-Duke Admin has
// since released the payee's funds, not about payment outcome) -- use
// this shared set instead of re-typing the status list per screen.
const paidTransactionStatuses = {'payment_received', 'released_to_wallet'};

class TransactionSummary {
  const TransactionSummary({
    required this.id,
    required this.listingId,
    required this.listingTitle,
    required this.transactionType,
    required this.status,
    required this.grossAmount,
    required this.commissionAmount,
    required this.netPayoutAmount,
    required this.createdAt,
  });

  final String id;
  final String listingId;

  /// The listing's actual title -- the backend now denormalizes this onto
  /// every transaction response (see transactions.py's `_listing_titles`)
  /// specifically so screens never have to show the raw `listingId` (or
  /// make a second per-row `GET /v1/listings/{id}` call just to get a
  /// human-readable label). Falls back to a fixed placeholder string
  /// server-side, never null, if the listing was since deleted (FEAT-015:
  /// receipts stay accessible even then).
  final String listingTitle;
  final String transactionType;
  // held | pending_payment | payment_received | released_to_wallet |
  // failed | expired | refunded
  final String status;
  final double grossAmount;
  final double commissionAmount;
  final double netPayoutAmount;
  final DateTime createdAt;

  factory TransactionSummary.fromJson(Map<String, dynamic> json) =>
      TransactionSummary(
        id: json['id'] as String,
        listingId: json['listing_id'] as String,
        listingTitle: json['listing_title'] as String,
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
    required super.listingTitle,
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
        listingTitle: json['listing_title'] as String,
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
