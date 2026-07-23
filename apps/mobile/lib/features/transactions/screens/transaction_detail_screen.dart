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

import '../../../core/theme/app_semantic_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_format.dart';
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

  /// No longer used to resolve the "Listing" row's title -- the backend
  /// now denormalizes `listing_title` directly onto the transaction
  /// response (see transactions.py), so this screen no longer needs a
  /// separate GET /v1/listings/{id} call for that. Kept on the
  /// constructor since other call sites/tests still wire it through; a
  /// follow-up could drop it from the router entirely.
  final ListingRepository listingRepository;

  @override
  State<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  _ScreenState _state = _ScreenState.loading;
  TransactionDetail? _transaction;
  String? _errorMessage;
  // Bug fix: pressing "Download Hold Confirmation"/"Download PDF Receipt"
  // could appear to freeze the screen -- `_downloadReceipt` awaited
  // `launchUrl` with no timeout and no loading state, so a slow-to-resolve
  // URL (e.g. a local-dev LocalStack `http://` PDF link the OS takes a
  // while to hand off, or simply no app registered to open it) left the
  // button doing nothing with zero visual feedback, indistinguishable from
  // a hang. Guards against a second tap piling on a second launch attempt
  // while one is already in flight, same as any other in-flight action in
  // this app.
  bool _downloadingReceipt = false;

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
    if (_downloadingReceipt) return; // already in flight -- see field doc.
    final txn = _transaction;
    // Bug fix: previously null-checked `receiptUrl` alone, but the backend
    // (paystack_webhook_handler.py) seeds `pdf_url` as `""` (empty string,
    // not null) when a Receipt row is first created -- real PDF generation
    // is still a backend TODO, so an empty string is exactly what a
    // genuinely "succeeded" transaction has today, and `Uri.tryParse('')`
    // silently no-ops instead of showing this snackbar. `isEmpty` catches
    // both cases the same way.
    if (txn == null || txn.receiptUrl == null || txn.receiptUrl!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Receipt is not ready yet. Please check back shortly.')),
      );
      return;
    }
    final uri = Uri.tryParse(txn.receiptUrl!);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This receipt link looks invalid.')),
      );
      return;
    }
    setState(() => _downloadingReceipt = true);
    try {
      // Bounded timeout (AGENTS.md Behavior Rules: every external hand-off
      // must fail fast rather than hang indefinitely) -- `launchUrl`
      // itself has no built-in timeout, so a device with no browser/PDF
      // viewer able to resolve the intent (or, in local dev, a
      // `http://localhost:...` LocalStack URL the OS is slow to hand off)
      // previously left this awaited Future pending forever with the
      // button showing no feedback at all, indistinguishable from the app
      // having frozen.
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication)
          .timeout(const Duration(seconds: 10), onTimeout: () => false);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  "Couldn't open the receipt -- no app available to view it.")),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open the receipt.")),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingReceipt = false);
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
                        formatNairaDecimal(txn.grossAmount),
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
                    // Bug fix: this screen showed every other identifying
                    // field (listing, type, parties, timestamps) but never
                    // the transaction's own id -- the one value a user
                    // needs to reference when contacting support about a
                    // specific payment/hold, and the same id the receipt
                    // PDF's own header row already prints (see
                    // receipt_service._build_pdf_bytes's `header_rows`).
                    // Monospace + selectable so it can actually be copied,
                    // matching how a raw id is usually presented.
                    _rowWidget(
                      'Transaction ID',
                      SelectableText(
                        txn.id,
                        textAlign: TextAlign.right,
                        style: AppTypography.bodySmall
                            .copyWith(fontFamily: 'monospace'),
                      ),
                    ),
                    // Was `_row('Listing', txn.listingId)` -- the raw id --
                    // then a `ListingTitleText` fetch. The backend now
                    // denormalizes the title directly onto the transaction
                    // response (transactions.py), so no separate
                    // GET /v1/listings/{id} call is needed here anymore.
                    _row('Listing', txn.listingTitle),
                    _row('Transaction type', txn.transactionType),
                    const Divider(height: AppSpacing.lg),
                    // Bug fix (reported confusion): this used to show only
                    // "Gross amount" / "Commission" (the COMBINED buyer
                    // fee + owner commission total) / "Net payout", with
                    // no listing price row at all. That made
                    // `netPayoutAmount` look wrong at a glance -- e.g. a
                    // ₦10,000 listing at 4%/6% shows Gross ₦10,400,
                    // Commission ₦1,000, Net payout ₦9,400, and
                    // ₦10,000 - ₦1,000 = ₦9,000 looks like the "obvious"
                    // expected payout. That arithmetic is wrong: only the
                    // OWNER's commission share (₦600 here) is ever
                    // deducted from the listing price to produce the
                    // payout -- the buyer fee (₦400) is a guest-side
                    // surcharge on top of the listing price that never
                    // touches the host's payout at all (two-sided
                    // commission model, commission_service.
                    // compute_price_breakdown). Showing the full split
                    // makes `netPayoutAmount = listingPrice -
                    // ownerCommissionAmount` self-evident instead of
                    // needing this explanation.
                    _row('Listing price', formatNairaDecimal(txn.listingPrice)),
                    _row('Buyer fee (added to guest charge)',
                        formatNairaDecimal(txn.buyerFeeAmount)),
                    _row('Gross amount (charged to guest)',
                        formatNairaDecimal(txn.grossAmount)),
                    const Divider(height: AppSpacing.lg),
                    _row('Owner commission (deducted from payout)',
                        formatNairaDecimal(txn.ownerCommissionAmount)),
                    _row('Net payout (paid to host)',
                        formatNairaDecimal(txn.netPayoutAmount)),
                    const Divider(height: AppSpacing.lg),
                    _row('Total De-Duke commission',
                        formatNairaDecimal(txn.commissionAmount)),
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
            // Bug fix: this button used to render unconditionally for
            // every transaction status, including failed/expired/refunded
            // ones that will never have a document. The backend
            // (receipt_service.py) now generates a real PDF for exactly
            // two cases -- a "Booking Hold Confirmation" the moment a hold
            // is created (`held`/`pending_payment`), upgraded in place to
            // a full "Payment Receipt" once the same transaction succeeds
            // -- so the button is shown for those statuses only, with a
            // label that reflects which document the user will actually
            // get. `_downloadReceipt`'s "not ready yet" snackbar is a
            // genuinely accurate, retryable message for these two
            // statuses (PDF generation is best-effort and could briefly
            // lag); it would still be actively misleading for a
            // failed/expired/refunded transaction, which is why those
            // remain excluded entirely rather than just risking a
            // permanent "not ready yet".
            if (paidTransactionStatuses.contains(txn.status) ||
                txn.status == 'held' ||
                txn.status == 'pending_payment') ...[
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  // Disabled (rather than merely no-op-ing) while a launch
                  // is in flight so the button itself visibly reflects
                  // "working on it" instead of looking frozen/unresponsive.
                  onPressed: _downloadingReceipt ? null : _downloadReceipt,
                  icon: _downloadingReceipt
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(paidTransactionStatuses.contains(txn.status)
                      ? 'Download PDF Receipt'
                      : 'Download Hold Confirmation'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final colorScheme = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<AppSemanticColors>()!;
    final (label, color) = switch (status) {
      'payment_received' => ('Paid', semantic.success),
      'released_to_wallet' => ('Paid', semantic.success),
      'held' => ('Held', semantic.warning),
      'pending_payment' => ('Processing', semantic.info),
      'failed' => ('Failed', colorScheme.error),
      'expired' => ('Expired', colorScheme.error),
      'refunded' => ('Refunded', colorScheme.onSurfaceVariant),
      _ => (status, colorScheme.onSurfaceVariant),
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
              style: AppTypography.bodySmall.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
