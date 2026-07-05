import 'package:flutter_test/flutter_test.dart';

import 'package:de_duke_mobile/features/checkout/data/transaction_models.dart';

void main() {
  group('TransactionSummary.fromJson', () {
    test('parses a held transaction', () {
      final txn = TransactionSummary.fromJson({
        'id': 'txn-1',
        'listing_id': 'listing-1',
        'transaction_type': 'shortlet_booking',
        'status': 'held',
        'gross_amount': 50000.0,
        'commission_amount': 2500.0,
        'net_payout_amount': 47500.0,
        'created_at': '2026-07-01T10:00:00Z',
      });

      expect(txn.id, 'txn-1');
      expect(txn.status, 'held');
      expect(txn.grossAmount, 50000.0);
      expect(txn.commissionAmount, 2500.0);
      expect(txn.netPayoutAmount, 47500.0);
    });
  });

  group('TransactionDetail.fromJson', () {
    test('parses a succeeded transaction with a receipt url', () {
      final txn = TransactionDetail.fromJson({
        'id': 'txn-2',
        'listing_id': 'listing-2',
        'transaction_type': 'lease_deposit',
        'status': 'succeeded',
        'gross_amount': 1200000.0,
        'commission_amount': 60000.0,
        'net_payout_amount': 1140000.0,
        'created_at': '2026-07-01T10:00:00Z',
        'payer_id': 'user-payer',
        'payee_id': 'user-payee',
        'paid_at': '2026-07-01T10:05:00Z',
        'hold_expires_at': null,
        'receipt_url': 'https://example.com/receipt.pdf',
      });

      expect(txn.status, 'succeeded');
      expect(txn.payerId, 'user-payer');
      expect(txn.payeeId, 'user-payee');
      expect(txn.paidAt, DateTime.parse('2026-07-01T10:05:00Z'));
      expect(txn.holdExpiresAt, isNull);
      expect(txn.receiptUrl, 'https://example.com/receipt.pdf');
    });

    test('parses a held transaction with no receipt yet', () {
      final txn = TransactionDetail.fromJson({
        'id': 'txn-3',
        'listing_id': 'listing-3',
        'transaction_type': 'sale_reservation',
        'status': 'held',
        'gross_amount': 5000000.0,
        'commission_amount': 250000.0,
        'net_payout_amount': 4750000.0,
        'created_at': '2026-07-01T10:00:00Z',
        'payer_id': 'user-payer',
        'payee_id': 'user-payee',
        'paid_at': null,
        'hold_expires_at': '2026-07-01T10:15:00Z',
        'receipt_url': null,
      });

      expect(txn.status, 'held');
      expect(txn.paidAt, isNull);
      expect(txn.holdExpiresAt, DateTime.parse('2026-07-01T10:15:00Z'));
      expect(txn.receiptUrl, isNull);
    });
  });
}
