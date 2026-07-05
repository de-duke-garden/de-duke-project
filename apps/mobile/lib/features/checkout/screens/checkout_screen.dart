/// screens.md Screen 10: Checkout. Completes payment for an active booking
/// hold via Paystack's hosted checkout page (authorization_url, opened in
/// an external browser -- no flutter_paystack SDK dependency exists yet,
/// and Paystack's "Standard" flow is a browser redirect by design, so this
/// is the real integration, not a stub).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_spacing.dart';
import '../data/checkout_repository.dart';
import '../data/transaction_models.dart';

enum _ScreenState {
  loading,
  ready,
  submitting,
  paymentError,
  holdExpired,
  offline,
  error
}

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen(
      {super.key, required this.transactionId, required this.repository});

  final String transactionId;
  final CheckoutRepository repository;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen>
    with WidgetsBindingObserver {
  _ScreenState _state = _ScreenState.loading;
  String? _errorMessage;
  TransactionDetail? _transaction;
  String? _idempotencyKey;
  Timer? _countdownTicker;
  Duration _timeRemaining = Duration.zero;
  bool _awaitingReturnFromBrowser = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTicker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // screens.md edge case: user backgrounds the app mid-Paystack-flow --
    // on return, check transaction status before assuming failure, so a
    // genuinely successful payment (confirmed via webhook while the app
    // was backgrounded) is never mistaken for a failure or re-charged.
    if (state == AppLifecycleState.resumed && _awaitingReturnFromBrowser) {
      _awaitingReturnFromBrowser = false;
      _refreshStatus();
    }
  }

  Future<void> _load() async {
    setState(() {
      _state = _ScreenState.loading;
      _errorMessage = null;
    });
    try {
      final txn = await widget.repository.getTransaction(widget.transactionId);
      if (!mounted) return;
      _idempotencyKey ??= widget.repository.newIdempotencyKey();
      _applyTransaction(txn);
    } catch (e) {
      if (!mounted) return;
      final message =
          e is CheckoutException ? e.message : 'Something went wrong.';
      setState(() {
        _state =
            message == 'offline' ? _ScreenState.offline : _ScreenState.error;
        _errorMessage = message == 'offline'
            ? "You're offline. Check your connection and try again."
            : message;
      });
    }
  }

  Future<void> _refreshStatus() async {
    try {
      final txn = await widget.repository.getTransaction(widget.transactionId);
      if (!mounted) return;
      _applyTransaction(txn);
    } catch (_) {
      // Silent -- this is a background re-check, not a user-initiated
      // action; the countdown/UI simply doesn't update this cycle.
    }
  }

  void _applyTransaction(TransactionDetail txn) {
    setState(() {
      _transaction = txn;
      if (txn.status == 'succeeded') {
        _state = _ScreenState.ready; // transient, build() redirects below
      } else if (txn.status == 'held' || txn.status == 'pending_payment') {
        _state = _ScreenState.ready;
        _startCountdown(txn.holdExpiresAt);
      } else if (txn.status == 'expired') {
        _state = _ScreenState.holdExpired;
      } else {
        _state = _ScreenState.error;
        _errorMessage = 'This booking is no longer available for checkout.';
      }
    });
  }

  void _startCountdown(DateTime? holdExpiresAt) {
    _countdownTicker?.cancel();
    if (holdExpiresAt == null) return;
    void tick() {
      final remaining =
          holdExpiresAt.toUtc().difference(DateTime.now().toUtc());
      if (!mounted) return;
      if (remaining.isNegative) {
        setState(() => _state = _ScreenState.holdExpired);
        _countdownTicker?.cancel();
      } else {
        setState(() => _timeRemaining = remaining);
      }
    }

    tick();
    _countdownTicker =
        Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  Future<void> _pay() async {
    setState(() {
      _state = _ScreenState.submitting;
      _errorMessage = null;
    });
    try {
      final result = await widget.repository.initiateCheckout(
        transactionId: widget.transactionId,
        idempotencyKey: _idempotencyKey!,
      );
      if (!mounted) return;

      final uri = Uri.tryParse(result.authorizationUrl);
      if (uri == null || result.authorizationUrl.isEmpty) {
        // Idempotent replay: backend already has a processor reference for
        // this transaction (see checkout.py) and returns an empty URL --
        // just re-check status rather than trying to relaunch a browser.
        await _refreshStatus();
        return;
      }

      _awaitingReturnFromBrowser = true;
      setState(() => _state = _ScreenState.ready);
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        setState(() {
          _state = _ScreenState.paymentError;
          _errorMessage = 'Could not open the payment page. Please try again.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      final message =
          e is CheckoutException ? e.message : 'Something went wrong.';
      setState(() {
        if (message == 'offline') {
          _state = _ScreenState.offline;
          _errorMessage =
              "We couldn't confirm this payment. Please check your connection and try again.";
        } else if (message == 'hold_expired') {
          _state = _ScreenState.holdExpired;
        } else {
          _state = _ScreenState.paymentError;
          _errorMessage = message;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final txn = _transaction;

    if (txn != null && txn.status == 'succeeded') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted)
          context.go('/checkout/${widget.transactionId}/confirmation');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        bottom: (txn != null &&
                (txn.status == 'held' || txn.status == 'pending_payment'))
            ? PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    'Hold expires in ${_timeRemaining.inMinutes}m ${(_timeRemaining.inSeconds % 60).toString().padLeft(2, '0')}s',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              )
            : null,
      ),
      body: switch (_state) {
        _ScreenState.loading =>
          const Center(child: CircularProgressIndicator()),
        _ScreenState.error => _MessageView(
            message: _errorMessage ?? 'Something went wrong.', onRetry: _load),
        _ScreenState.offline => _MessageView(
            message: _errorMessage ??
                "You're offline. Check your connection and try again.",
            onRetry: _load,
          ),
        _ScreenState.holdExpired => _HoldExpiredView(
            onRestart: () {
              if (txn != null) context.go('/booking/${txn.listingId}');
            },
          ),
        _ScreenState.paymentError =>
          _buildReady(context, txn, paymentError: _errorMessage),
        _ScreenState.submitting => _buildReady(context, txn, submitting: true),
        _ScreenState.ready => _buildReady(context, txn),
      },
    );
  }

  Widget _buildReady(BuildContext context, TransactionDetail? txn,
      {bool submitting = false, String? paymentError}) {
    if (txn == null) return const Center(child: CircularProgressIndicator());
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (paymentError != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(paymentError),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Listing ${txn.listingId}',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  _row(context, 'Amount',
                      '₦${txn.grossAmount.toStringAsFixed(2)}'),
                  _row(context, 'Commission (platform fee)',
                      '₦${txn.commissionAmount.toStringAsFixed(2)}'),
                  _row(context, 'Net to host',
                      '₦${txn.netPayoutAmount.toStringAsFixed(2)}'),
                ],
              ),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: submitting ? null : _pay,
              child: submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Pay ₦${txn.grossAmount.toStringAsFixed(0)} Now'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: submitting
                ? null
                : () => context.go('/booking/${txn.listingId}'),
            child: const Text('Cancel'),
          ),
        ],
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

class _MessageView extends StatelessWidget {
  const _MessageView({required this.message, required this.onRetry});

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

class _HoldExpiredView extends StatelessWidget {
  const _HoldExpiredView({required this.onRestart});

  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.timer_off_outlined, size: 48),
            const SizedBox(height: AppSpacing.md),
            const Text('Your hold has expired',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: AppSpacing.sm),
            const Text('Start again to hold this listing.',
                textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
                onPressed: onRestart, child: const Text('Start again')),
          ],
        ),
      ),
    );
  }
}
