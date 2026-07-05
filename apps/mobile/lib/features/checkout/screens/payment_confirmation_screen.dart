/// screens.md Screen 11: Payment Confirmation. Only reachable on a
/// genuinely confirmed success (failures never navigate here) -- fetches
/// the final transaction state to show the commission-adjusted breakdown.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../data/checkout_repository.dart';
import '../data/transaction_models.dart';

enum _ScreenState { loading, loaded, error }

class PaymentConfirmationScreen extends StatefulWidget {
  const PaymentConfirmationScreen(
      {super.key, required this.transactionId, required this.repository});

  final String transactionId;
  final CheckoutRepository repository;

  @override
  State<PaymentConfirmationScreen> createState() =>
      _PaymentConfirmationScreenState();
}

class _PaymentConfirmationScreenState extends State<PaymentConfirmationScreen> {
  _ScreenState _state = _ScreenState.loading;
  TransactionDetail? _transaction;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _ScreenState.loading);
    try {
      final txn = await widget.repository.getTransaction(widget.transactionId);
      if (!mounted) return;
      setState(() {
        _transaction = txn;
        _state = _ScreenState.loaded;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _ScreenState.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, size: 72, color: Colors.green),
                const SizedBox(height: AppSpacing.md),
                Text('Payment Successful',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.lg),
                if (_state == _ScreenState.loading)
                  const CircularProgressIndicator(),
                if (_state == _ScreenState.error) ...[
                  const Text(
                    "Your payment succeeded -- we're just confirming details.",
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                      onPressed: _load, child: const Text('Check status')),
                ],
                if (_state == _ScreenState.loaded && _transaction != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        children: [
                          _row(context, 'Listing', _transaction!.listingId),
                          _row(context, 'Amount paid',
                              '₦${_transaction!.grossAmount.toStringAsFixed(2)}'),
                          _row(context, 'Commission',
                              '₦${_transaction!.commissionAmount.toStringAsFixed(2)}'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'A receipt has also been emailed to your registered address.',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => context.go('/transactions'),
                    child: const Text('View Receipt'),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: () => context.go('/home'),
                  child: const Text('Back to Home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value),
        ],
      ),
    );
  }
}
