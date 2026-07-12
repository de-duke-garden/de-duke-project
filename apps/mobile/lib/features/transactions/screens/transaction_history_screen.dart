/// screens.md Screen 19: Transaction History.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_spacing.dart';
import '../../checkout/data/checkout_repository.dart';
import '../../checkout/data/transaction_models.dart';
import '../data/dispute_repository.dart';
import '../data/transactions_repository.dart';

enum _ScreenState { loading, loaded, empty, error, offline }

enum _TransactionAction { viewReceipt, reportIssue }

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({
    super.key,
    required this.transactionsRepository,
    required this.checkoutRepository,
    required this.disputeRepository,
  });

  final TransactionsRepository transactionsRepository;
  final CheckoutRepository checkoutRepository;
  final DisputeRepository disputeRepository;

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  _ScreenState _state = _ScreenState.loading;
  String? _errorMessage;
  List<TransactionSummary> _items = [];
  String? _nextCursor;

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
      final page = await widget.transactionsRepository.listTransactions();
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _nextCursor = page.nextCursor;
        _state = _items.isEmpty ? _ScreenState.empty : _ScreenState.loaded;
      });
    } catch (e) {
      if (!mounted) return;
      final message =
          e is TransactionsException ? e.message : 'Something went wrong.';
      setState(() {
        _state =
            message == 'offline' ? _ScreenState.offline : _ScreenState.error;
        _errorMessage = message == 'offline'
            ? "You're offline. Showing your last cached transactions."
            : message;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_nextCursor == null) return;
    final page = await widget.transactionsRepository
        .listTransactions(cursor: _nextCursor);
    if (!mounted) return;
    setState(() {
      _items = [..._items, ...page.items];
      _nextCursor = page.nextCursor;
    });
  }

  Future<void> _openReceipt(String transactionId) async {
    final detail =
        await widget.checkoutRepository.getTransaction(transactionId);
    if (!mounted) return;
    if (detail.receiptUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Receipt is not ready yet. Please check back shortly.')),
      );
      return;
    }
    final uri = Uri.tryParse(detail.receiptUrl!);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// FEAT-026: the mobile entry point for raising a dispute -- there is no
  /// dedicated mobile screen for this (screens.md's Dispute & Refund
  /// Management, Screen 24, is Admin Web Console-only), so it's a
  /// lightweight bottom sheet reachable from the transaction it concerns,
  /// keeping every dispute tied to a real Transaction.id per the Dispute
  /// model's required transaction_id field.
  Future<void> _openReportIssueSheet(TransactionSummary txn) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ReportIssueSheet(
        transaction: txn,
        disputeRepository: widget.disputeRepository,
      ),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Report submitted. De-Duke's team will review it and follow up."),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transactions')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: switch (_state) {
          _ScreenState.loading => const _SkeletonList(),
          _ScreenState.error => _ErrorView(
              message: _errorMessage ?? 'Something went wrong.',
              onRetry: _load),
          _ScreenState.empty => const _EmptyView(),
          _ScreenState.offline || _ScreenState.loaded => _buildList(context),
        },
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    return Column(
      children: [
        if (_state == _ScreenState.offline)
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.errorContainer,
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Text(_errorMessage ?? "You're offline.",
                textAlign: TextAlign.center),
          ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.pixels >=
                  notification.metrics.maxScrollExtent - 200) {
                _loadMore();
              }
              return false;
            },
            child: ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final txn = _items[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                  child: ListTile(
                    title: Text('Listing ${txn.listingId}'),
                    subtitle: Text(
                        '${_statusLabel(txn.status)} • ${_formatDate(txn.createdAt)}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('₦${txn.grossAmount.toStringAsFixed(0)}'),
                        PopupMenuButton<_TransactionAction>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (action) => switch (action) {
                            _TransactionAction.viewReceipt =>
                              _openReceipt(txn.id),
                            _TransactionAction.reportIssue =>
                              _openReportIssueSheet(txn),
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: _TransactionAction.viewReceipt,
                              child: Text('View receipt'),
                            ),
                            PopupMenuItem(
                              value: _TransactionAction.reportIssue,
                              child: Text('Report an issue'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    onTap: () => _openReceipt(txn.id),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  String _statusLabel(String status) => switch (status) {
        'succeeded' => 'Paid',
        'held' => 'Held',
        'pending_payment' => 'Processing',
        'failed' => 'Failed',
        'expired' => 'Expired',
        'refunded' => 'Refunded',
        _ => status,
      };

  String _formatDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 6,
      itemBuilder: (context, index) => Container(
        height: 72,
        margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long_outlined, size: 48),
            const SizedBox(height: AppSpacing.md),
            const Text('No transactions yet'),
            const SizedBox(height: AppSpacing.sm),
            const Text('Browse listings to make your first booking.',
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
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

/// FEAT-026 "Report an issue" form -- reason dropdown + free-text
/// description, matching the fields app/schemas/dispute.py's
/// DisputeCreateRequest requires. Pops `true` on a successful submit so
/// the caller (TransactionHistoryScreen) can show a confirmation snackbar.
class _ReportIssueSheet extends StatefulWidget {
  const _ReportIssueSheet({
    required this.transaction,
    required this.disputeRepository,
  });

  final TransactionSummary transaction;
  final DisputeRepository disputeRepository;

  @override
  State<_ReportIssueSheet> createState() => _ReportIssueSheetState();
}

class _ReportIssueSheetState extends State<_ReportIssueSheet> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  DisputeReason _reason = DisputeReason.serviceIssue;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await widget.disputeRepository.raiseDispute(
        transactionId: widget.transaction.id,
        reason: _reason,
        description: _descriptionController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final message = e is DisputeException ? e.message : null;
      setState(() {
        _submitting = false;
        _errorMessage = message == 'offline'
            ? "You're offline. Try again once connected."
            : (message ?? 'Could not submit your report. Please try again.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Report an issue',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'De-Duke staff will review this transaction and follow up. '
              'This does not automatically pause or refund the payment.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            if (_errorMessage != null) ...[
              Text(_errorMessage!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: AppSpacing.sm),
            ],
            DropdownButtonFormField<DisputeReason>(
              initialValue: _reason,
              decoration: const InputDecoration(labelText: 'Reason'),
              items: DisputeReason.values
                  .map((r) =>
                      DropdownMenuItem(value: r, child: Text(r.label)))
                  .toList(),
              onChanged: _submitting
                  ? null
                  : (value) {
                      if (value != null) setState(() => _reason = value);
                    },
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                  labelText: 'What happened?', alignLabelWithHint: true),
              minLines: 3,
              maxLines: 6,
              enabled: !_submitting,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Please describe the issue.'
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Submit report'),
            ),
          ],
        ),
      ),
    );
  }
}
