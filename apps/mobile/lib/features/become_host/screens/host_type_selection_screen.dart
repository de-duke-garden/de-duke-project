/// screens.md Screen 3a: Become a Host -- Type Selection.
/// Fetches the current submission status on mount; shows six selectable
/// host-type cards only if no submission exists yet, otherwise shows the
/// corresponding status view (In Review/Verified/Rejected), per screens.md
/// -- a user can only hold one host type submission at a time.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../data/host_account_models.dart';
import '../data/host_account_repository.dart';

enum _ScreenState { loading, notStarted, inReview, verified, rejected, error }

class HostTypeSelectionScreen extends StatefulWidget {
  const HostTypeSelectionScreen({super.key, required this.repository});

  final HostAccountRepository repository;

  @override
  State<HostTypeSelectionScreen> createState() =>
      _HostTypeSelectionScreenState();
}

class _HostTypeSelectionScreenState extends State<HostTypeSelectionScreen> {
  _ScreenState _state = _ScreenState.loading;
  HostAccountStatus? _submission;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _ScreenState.loading);
    try {
      final submission = await widget.repository.getMySubmission();
      if (!mounted) return;
      setState(() {
        _submission = submission;
        if (submission == null) {
          _state = _ScreenState.notStarted;
        } else {
          _state = switch (submission.status) {
            'verified' => _ScreenState.verified,
            'rejected' => _ScreenState.rejected,
            _ => _ScreenState.inReview,
          };
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _ScreenState.error);
    }
  }

  void _selectType(HostType type) {
    context.push('/become-host/${type.apiValue}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Become a Host')),
      body: switch (_state) {
        _ScreenState.loading =>
          const Center(child: CircularProgressIndicator()),
        _ScreenState.error => _ErrorView(onRetry: _load),
        _ScreenState.notStarted => _TypeSelectionGrid(onSelect: _selectType),
        _ScreenState.inReview => _StatusView(
            icon: Icons.hourglass_top,
            title:
                "We're reviewing your ${_submission?.hostType ?? ''} application",
            message:
                'This usually takes a short while. We will notify you once a decision is made.',
          ),
        _ScreenState.verified => _StatusView(
            icon: Icons.verified,
            title: 'Verified Host',
            message:
                'Your ${_submission?.hostType ?? ''} application has been approved.',
            actionLabel: 'Go to Host Dashboard',
            onAction: () => context.go('/home'),
          ),
        _ScreenState.rejected => _StatusView(
            icon: Icons.error_outline,
            title: 'Application rejected',
            message: _submission?.statusReason ??
                'Your application was not approved.',
            actionLabel: 'Resubmit',
            onAction: () {
              final hostType = _submission?.hostType;
              if (hostType != null) context.push('/become-host/$hostType');
            },
          ),
      },
    );
  }
}

class _TypeSelectionGrid extends StatelessWidget {
  const _TypeSelectionGrid({required this.onSelect});

  final void Function(HostType) onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: HostType.values
          .map(
            (type) => Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ListTile(
                minVerticalPadding: AppSpacing.sm,
                leading: const Icon(Icons.badge_outlined),
                title: Text(type.label),
                subtitle: Text(type.description),
                onTap: () => onSelect(type),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _StatusView extends StatelessWidget {
  const _StatusView({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: AppSpacing.md),
            Text(title,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: AppSpacing.md),
          const Text('Could not load your verification status.'),
          const SizedBox(height: AppSpacing.md),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
