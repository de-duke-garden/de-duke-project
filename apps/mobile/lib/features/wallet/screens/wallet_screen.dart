/// FEAT-044 (Host/Agency Virtual Wallet) + entry point into FEAT-045
/// (Payout Settings / Withdraw). Reachable from Account Settings (host and
/// agency roles) -- see account_settings_screen.dart's "Wallet" row.
///
/// Money-safety note mirrored from the backend (wallet_service.py): the
/// balance shown here is the same denormalized `Wallet.balance` the ledger
/// itself derives, so a Withdraw succeeding always immediately reflects in
/// this screen's own next load -- there is no separate "pending" balance
/// concept a guest-facing screen needs to reconcile.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_names.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../data/wallet_models.dart';
import '../data/wallet_repository.dart';
import 'withdraw_sheet.dart';

enum _ScreenState { loading, loaded, error, offline }

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key, required this.repository});

  final WalletRepository repository;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  _ScreenState _state = _ScreenState.loading;
  WalletSummary? _wallet;
  List<WalletLedgerEntry> _ledger = [];
  PayoutSettings? _payoutSettings;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _ScreenState.loading);
    try {
      final wallet = await widget.repository.getWallet();
      final ledgerFuture = widget.repository.getLedger();
      // Best-effort -- a payee who has never opened Payout Settings yet
      // (204/null) shouldn't block the rest of the Wallet screen from
      // loading; the Withdraw sheet itself re-checks and prompts to set
      // it up if still missing at withdrawal time.
      PayoutSettings? payoutSettings;
      try {
        payoutSettings = await widget.repository.getPayoutSettings();
      } catch (_) {
        payoutSettings = null;
      }
      final ledger = await ledgerFuture;
      if (!mounted) return;
      setState(() {
        _wallet = wallet;
        _ledger = ledger.items;
        _payoutSettings = payoutSettings;
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

  Future<void> _openWithdraw() async {
    if (_wallet == null) return;
    final withdrawn = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => WithdrawSheet(
        repository: widget.repository,
        wallet: _wallet!,
        payoutSettings: _payoutSettings,
      ),
    );
    if (withdrawn == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_outlined),
            tooltip: 'Payout settings',
            onPressed: () async {
              await context.pushNamed(RouteNames.walletPayoutSettings);
              if (mounted) _load();
            },
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_state) {
      case _ScreenState.loading:
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: const [
            SkeletonBox(height: 120, borderRadius: AppRadii.lg),
            SizedBox(height: AppSpacing.lg),
            SkeletonRow(),
            SkeletonRow(),
            SkeletonRow(),
          ],
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
        return RefreshIndicator(onRefresh: _load, child: _buildLoaded(context));
    }
  }

  Widget _buildLoaded(BuildContext context) {
    final wallet = _wallet!;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _BalanceCard(
          wallet: wallet,
          onWithdraw: _openWithdraw,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Activity', style: AppTypography.h3),
        const SizedBox(height: AppSpacing.sm),
        if (_ledger.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Text(
              'No wallet activity yet. Released funds and withdrawals will show up here.',
              style: AppTypography.body,
            ),
          )
        else
          ..._ledger.map((entry) => _LedgerTile(entry: entry)),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.wallet, required this.onWithdraw});

  final WalletSummary wallet;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Available balance',
            style: AppTypography.bodySmall
                .copyWith(color: colorScheme.onPrimaryContainer),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '₦${wallet.balance.toStringAsFixed(0)}',
            style: AppTypography.h1
                .copyWith(color: colorScheme.onPrimaryContainer),
          ),
          const SizedBox(height: AppSpacing.md),
          ElevatedButton(
            onPressed: wallet.balance > 0 ? onWithdraw : null,
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
  }
}

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({required this.entry});

  final WalletLedgerEntry entry;

  String get _label => switch (entry.sourceType) {
        'transaction_release' => 'Escrow release',
        'withdrawal' => 'Withdrawal',
        'withdrawal_reversal' => 'Withdrawal reversed',
        'manual_adjustment' => entry.notes ?? 'Manual adjustment',
        _ => entry.sourceType,
      };

  @override
  Widget build(BuildContext context) {
    final isCredit = entry.direction == 'credit';
    final semantic = Theme.of(context).extension<AppSemanticColors>()!;
    final tone = isCredit ? semantic.success : Theme.of(context).colorScheme.error;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: tone.withValues(alpha: 0.12),
        child: Icon(
          isCredit ? Icons.arrow_downward : Icons.arrow_upward,
          color: tone,
          size: 18,
        ),
      ),
      title: Text(_label),
      subtitle: Text(
        '${entry.createdAt.toLocal()}'.split('.').first,
        style: AppTypography.bodySmall,
      ),
      trailing: Text(
        '${isCredit ? '+' : '-'}₦${entry.amount.toStringAsFixed(0)}',
        style: AppTypography.bodySmall.copyWith(
          color: tone,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
