/// FEAT-045 (Withdrawal half): bottom sheet from WalletScreen's "Withdraw"
/// button. No further Admin approval at this step -- automatic Paystack
/// Transfer per FEAT-043's own checkpoint already having happened when an
/// Admin released funds into this wallet (see withdrawal_service.py's
/// module docstring).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_names.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_format.dart';
import '../data/wallet_models.dart';
import '../data/wallet_repository.dart';

class WithdrawSheet extends StatefulWidget {
  const WithdrawSheet({
    super.key,
    required this.repository,
    required this.wallet,
    required this.payoutSettings,
  });

  final WalletRepository repository;
  final WalletSummary wallet;
  final PayoutSettings? payoutSettings;

  @override
  State<WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<WithdrawSheet> {
  final _amountController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  double? get _parsedAmount => double.tryParse(_amountController.text.trim());

  bool get _canSubmit {
    final amount = _parsedAmount;
    return !_submitting &&
        widget.payoutSettings?.isVerified == true &&
        amount != null &&
        amount > 0 &&
        amount <= widget.wallet.balance;
  }

  Future<void> _submit() async {
    final amount = _parsedAmount;
    if (amount == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.repository.requestWithdrawal(amount);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on WalletException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message == 'offline'
            ? "You're offline. Check your connection and try again."
            : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = "Couldn't start this withdrawal -- try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final needsPayoutSettings = widget.payoutSettings?.isVerified != true;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Withdraw', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Available balance: ${formatNaira(widget.wallet.balance)}',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          if (needsPayoutSettings) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .errorContainer
                    .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add and verify a payout bank account before you can withdraw.',
                    style: AppTypography.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop(false);
                      context.pushNamed(RouteNames.walletPayoutSettings);
                    },
                    child: const Text('Set up payout settings'),
                  ),
                ],
              ),
            ),
          ] else ...[
            TextField(
              controller: _amountController,
              enabled: !_submitting,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount (₦)',
                prefixText: '₦',
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(
              onPressed: _canSubmit ? _submit : null,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Confirm withdrawal'),
            ),
          ],
        ],
      ),
    );
  }
}
