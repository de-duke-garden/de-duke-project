/// In-app Transaction Detail / Receipt screen -- the destination for
/// Transaction History's (screens.md Screen 19) `Hero` shared-element
/// transition on the amount/status chip. There's no screens.md section
/// dedicated solely to this detail view distinct from Payment Confirmation
/// (Screen 11), so this screen is modeled on that screen's layout/tokens
/// (celebratory summary card pattern minus the celebratory-sequence itself
/// -- this is a look-up of a past transaction, not a fresh "peak moment"),
/// while surfacing every field Screen 19's "Receipt detail" component and
/// `schema.md`'s Transaction entity call for: listing reference, amount,
/// commission breakdown, status, timestamps, and counterparties.
///
/// Reuses `CheckoutRepository.getTransaction` (GET `/v1/transactions/:id`)
/// -- the same call Payment Confirmation already makes -- rather than
/// introducing a second transaction-detail endpoint client.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/listing_title_text.dart';
import '../../checkout/data/checkout_repository.dart';
import '../../checkout/data/transaction_models.dart';
import '../../listings/data/listing_repository.dart';

enum _ScreenState { loading, loaded, error, offline }

class TransactionDetailScreen extends StatefulWidget {
  const TransactionDetailScreen({
    super.key,
    required this.transactionId,
    required this.repository,
    required this.listingRepository,
  });

  final String transactionId;
  final CheckoutRepository repository;

  /// Resolves the transaction's `listingId` to its listing title for the
  /// "Listing" row -- previously showed the raw listing id.
  final ListingRepository listingRepository;

  @override
  State<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  _ScreenState _state = _ScreenState.loading;
  TransactionDetail? _transaction;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _state = _ScreenState.loading;
      _errorMessage = null;
    });
    try {
      final txn =
          await widget.repository.getTransaction(widget.transactionId);
      if (!mounted) return;
      setState(() {
        _transaction = txn;
        _state = _ScreenState.loaded;
      });
    } catch (e) {
      if (!mounted) return;
      final message = e is CheckoutException ? e.message : null;
      setState(() {
        _state =
            message == 'offline' ? _ScreenState.offline : _ScreenState.error;
        _errorMessage = message == 'offline'
            ? "You're offline. Showing what we last loaded, if anything."
            : (message ?? 'Could not load this transaction.');
      });
    }
  }

  /// screens.md Screen 19: "Download/Share Receipt ... Export receipt as
  /// PDF" -- kept as the secondary action alongside this screen's in-app
  /// detail (the primary experience the Hero now lands on), same
  /// `url_launcher` hand-off to the OS share sheet/file viewer as before.
  Future<void> _downloadReceipt() async {
    final txn = _transaction;
    if (txn == null || txn.receiptUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Receipt is not ready yet. Please check back shortly.')),
      );
      return;
    }
    final uri = Uri.tryParse(txn.receiptUrl!);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transaction Detail')),
      body: switch (_state) {
        _ScreenState.loading =>
          const Center(child: CircularProgressIndicator()),
        _ScreenState.error => _ErrorView(
            message: _errorMessage ?? 'Something went wrong.',
            onRetry: _load,
          ),
        _ScreenState.offline || _ScreenState.loaded => _buildDetail(context),
      },
    );
  }

  Widget _buildDetail(BuildContext context) {
    final txn = _transaction;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (_state == _ScreenState.offline)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.errorContainer,
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Text(_errorMessage ?? "You're offline.",
                    textAlign: TextAlign.center),
              ),
            ),
          if (txn == null)
            const Center(child: Text('No cached data for this transaction.'))
          else ...[
            Center(
              child: Column(
                children: [
                  _statusChip(txn.status),
                  const SizedBox(height: AppSpacing.sm),
                  // shared-element-transition (branding.md): matches the
                  // Hero tag on Transaction History's row so the amount
                  // carries visually from the list into this detail view.
                  Hero(
                    tag: 'transaction-amount-${txn.id}',
                    child: Material(
                      type: MaterialType.transparency,
                      child: Text(
                        '₦${txn.grossAmount.toStringAsFixed(2)}',
                        style: AppTypography.statDisplay,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  children: [
                    // Was `_row('Listing', txn.listingId)` -- the raw id.
                    _rowWidget(
                      'Listing',
                      DefaultTextStyle.merge(
                        textAlign: TextAlign.right,
                        child: ListingTitleText(
                          listingId: txn.listingId,
                          listingRepository: widget.listingRepository,
                        ),
                      ),
                    ),
                    _row('Transaction type', txn.transactionType),
                    const Divider(height: AppSpacing.lg),
                    _row('Gross amount',
                        '₦${txn.grossAmount.toStringAsFixed(2)}'),
                    _row('Commission',
                        '₦${txn.commissionAmount.toStringAsFixed(2)}'),
                    _row('Net payout',
                        '₦${txn.netPayoutAmount.toStringAsFixed(2)}'),
                    const Divider(height: AppSpacing.lg),
                    _row('Payer', txn.payerId),
                    _row('Payee', txn.payeeId),
                    const Divider(height: AppSpacing.lg),
                    _row('Created', _formatDateTime(txn.createdAt)),
                    if (txn.paidAt != null)
                      _row('Paid', _formatDateTime(txn.paidAt!)),
                    if (txn.holdExpiresAt != null)
                      _row('Hold expires', _formatDateTime(txn.holdExpiresAt!)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _downloadReceipt,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Download PDF Receipt'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final (label, color) = switch (status) {
      'succeeded' => ('Paid', AppColors.success),
      'held' => ('Held', AppColors.warning),
      'pending_payment' => ('Processing', AppColors.info),
      'failed' => ('Failed', AppColors.error),
      'expired' => ('Expired', AppColors.error),
      'refunded' => ('Refunded', AppColors.textSecondary),
      _ => (status, AppColors.textSecondary),
    };
    return Chip(
      label: Text(label),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide(color: color),
    );
  }

  Widget _row(String label, String value) => _rowWidget(
        label,
        Text(value, textAlign: TextAlign.right),
      );

  Widget _rowWidget(String label, Widget value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
          Flexible(child: value),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: AppSpacing.md),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(
                onPressed: () => onRetry(), child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
