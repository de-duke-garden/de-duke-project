/// screens.md Screen 19: Transaction History.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_spacing.dart';
import '../../checkout/data/checkout_repository.dart';
import '../../checkout/data/transaction_models.dart';
import '../data/transactions_repository.dart';

enum _ScreenState { loading, loaded, empty, error, offline }

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({
    super.key,
    required this.transactionsRepository,
    required this.checkoutRepository,
  });

  final TransactionsRepository transactionsRepository;
  final CheckoutRepository checkoutRepository;

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
                    trailing: Text('₦${txn.grossAmount.toStringAsFixed(0)}'),
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
