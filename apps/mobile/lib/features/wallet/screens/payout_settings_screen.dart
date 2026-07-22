/// FEAT-045 (Payout Settings half): bank account a payee's withdrawals
/// pay out to. Resolution happens server-side (Paystack account
/// resolution + Transfer Recipient creation) on save -- this screen never
/// invents/accepts an account holder name itself; it's always the
/// server's resolved value shown back for explicit confirmation before
/// saving (FEAT-045 AC).
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_semantic_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../data/wallet_models.dart';
import '../data/wallet_repository.dart';

enum _ScreenState { loading, loaded, error, offline }

class PayoutSettingsScreen extends StatefulWidget {
  const PayoutSettingsScreen({super.key, required this.repository});

  final WalletRepository repository;

  @override
  State<PayoutSettingsScreen> createState() => _PayoutSettingsScreenState();
}

class _PayoutSettingsScreenState extends State<PayoutSettingsScreen> {
  _ScreenState _state = _ScreenState.loading;
  PayoutSettings? _existing;
  List<BankOption> _banks = [];
  String? _errorMessage;

  final _accountNumberController = TextEditingController();
  BankOption? _selectedBank;

  bool _saving = false;
  String? _saveError;
  // Set once the account resolves server-side and is saved -- shown as
  // confirmation of the resolved holder name (FEAT-045 AC), distinct from
  // `_existing?.accountHolderName` which only reflects a PRIOR save.
  PayoutSettings? _justSaved;

  @override
  void dispose() {
    _accountNumberController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _ScreenState.loading);
    try {
      final banksFuture = widget.repository.listBanks();
      final existing = await widget.repository.getPayoutSettings();
      final banks = await banksFuture;
      if (!mounted) return;
      setState(() {
        _existing = existing;
        _banks = banks;
        if (existing != null) {
          _accountNumberController.text = existing.accountNumber;
          final match = banks
              .where((b) => b.code == existing.bankCode)
              .cast<BankOption?>()
              .firstWhere((b) => b != null, orElse: () => null);
          _selectedBank = match;
        }
        _state = _ScreenState.loaded;
      });
    } on WalletException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = e.message == 'offline'
            ? _ScreenState.offline
            : _ScreenState.error;
        _errorMessage = e.message == 'offline' ? null : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _ScreenState.error);
    }
  }

  bool get _canSave =>
      !_saving &&
      _selectedBank != null &&
      _accountNumberController.text.trim().length == 10;

  Future<void> _save() async {
    final bank = _selectedBank;
    if (bank == null) return;
    setState(() {
      _saving = true;
      _saveError = null;
      _justSaved = null;
    });
    try {
      final saved = await widget.repository.savePayoutSettings(
        accountNumber: _accountNumberController.text.trim(),
        bankCode: bank.code,
        bankName: bank.name,
      );
      if (!mounted) return;
      setState(() {
        _existing = saved;
        _justSaved = saved;
        _saving = false;
      });
    } on WalletException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = e.message == 'offline'
            ? "You're offline. Check your connection and try again."
            : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = "Couldn't verify and save that account -- try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payout Settings')),
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_state) {
      case _ScreenState.loading:
        return const Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: [SkeletonRow(), SkeletonRow(), SkeletonRow()],
          ),
        );
      case _ScreenState.error:
        return EmptyStateView(
          title: 'Something went wrong',
          message: _errorMessage,
          isError: true,
          actionLabel: 'Retry',
          onAction: _load,
        );
      case _ScreenState.offline:
        return EmptyStateView(
          title: "You're offline",
          message: 'Check your connection and try again.',
          isError: true,
          actionLabel: 'Retry',
          onAction: _load,
        );
      case _ScreenState.loaded:
        return _buildLoaded(context);
    }
  }

  Widget _buildLoaded(BuildContext context) {
    final semantic = Theme.of(context).extension<AppSemanticColors>()!;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (_existing != null) ...[
          _StatusBanner(payoutSettings: _existing!),
          const SizedBox(height: AppSpacing.lg),
        ],
        Text(
          _existing != null
              ? 'Update your payout account'
              : 'Add your payout account',
          style: AppTypography.h3,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Withdrawals are transferred automatically to this account once you '
          'request one -- verify it carefully before saving.',
          style: AppTypography.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<BankOption>(
          initialValue: _selectedBank,
          decoration: const InputDecoration(labelText: 'Bank'),
          isExpanded: true,
          items: _banks
              .map((b) => DropdownMenuItem(value: b, child: Text(b.name)))
              .toList(),
          onChanged: _saving
              ? null
              : (b) => setState(() {
                    _selectedBank = b;
                    _justSaved = null;
                  }),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _accountNumberController,
          enabled: !_saving,
          keyboardType: TextInputType.number,
          maxLength: 10,
          decoration: const InputDecoration(
            labelText: 'Account number',
            counterText: '',
          ),
          onChanged: (_) => setState(() => _justSaved = null),
        ),
        if (_saveError != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(_saveError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        if (_justSaved != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: semantic.success, size: 18),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Verified: ${_justSaved!.accountHolderName}',
                    style:
                        AppTypography.bodySmall.copyWith(color: semantic.success),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        ElevatedButton(
          onPressed: _canSave ? _save : null,
          child: _saving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Verify and save'),
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.payoutSettings});

  final PayoutSettings payoutSettings;

  @override
  Widget build(BuildContext context) {
    final semantic = Theme.of(context).extension<AppSemanticColors>()!;
    final tone = payoutSettings.isVerified ? semantic.success : semantic.warning;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: [
          Icon(
            payoutSettings.isVerified ? Icons.verified : Icons.info_outline,
            color: tone,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '${payoutSettings.bankName} · ${payoutSettings.accountNumber}\n'
              '${payoutSettings.accountHolderName}',
              style: AppTypography.bodySmall.copyWith(color: tone),
            ),
          ),
        ],
      ),
    );
  }
}
