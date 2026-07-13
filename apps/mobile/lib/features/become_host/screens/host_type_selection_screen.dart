/// screens.md Screen 3a: Become a Host -- Type Selection.
/// Fetches the current submission status on mount; shows six selectable
/// host-type cards only if no submission exists yet, otherwise shows the
/// corresponding status view (In Review/Verified/Rejected), per screens.md
/// -- a user can only hold one host type submission at a time.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/celebratory_sequence.dart';
import '../../../core/widgets/illustration.dart';
import '../../../core/widgets/list_stagger.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/tap_scale.dart';
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
    context.pushNamed(
      RouteNames.verificationHostType,
      pathParameters: {'hostType': type.apiValue},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Become a Host')),
      body: switch (_state) {
        // screens.md Screen 3a Modernization Notes: loading uses a skeleton
        // block sized to the six-card grid rather than a bare spinner.
        _ScreenState.loading => ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            physics: const NeverScrollableScrollPhysics(),
            children: const [
              SkeletonListingCard(),
              SkeletonListingCard(),
              SkeletonListingCard(),
              SkeletonListingCard(),
              SkeletonListingCard(),
              SkeletonListingCard(),
            ],
          ),
        _ScreenState.error => _ErrorView(onRetry: _load),
        _ScreenState.notStarted => _TypeSelectionGrid(onSelect: _selectType),
        // In Review / Rejected stay calmer: standard empty-state weight
        // illustration (single-tone, lower opacity), not the celebratory
        // treatment -- these are waiting/action-needed states.
        _ScreenState.inReview => _StatusView(
            title:
                "We're reviewing your ${_submission?.hostType ?? ''} application",
            message:
                'This usually takes a short while. We will notify you once a decision is made.',
          ),
        _ScreenState.verified => _VerifiedStatusView(
            hostType: _submission?.hostType ?? '',
            onAction: () => context.goNamed(RouteNames.host),
          ),
        _ScreenState.rejected => _StatusView(
            title: 'Application rejected',
            message: _submission?.statusReason ??
                'Your application was not approved.',
            actionLabel: 'Resubmit',
            onAction: () {
              final hostType = _submission?.hostType;
              if (hostType != null) {
                context.pushNamed(
                  RouteNames.verificationHostType,
                  pathParameters: {'hostType': hostType},
                );
              }
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
    // screens.md Screen 3a Modernization Notes: same Listing Card
    // border/shadow treatment as Screen 2 (`radius-lg`, `shadow-sm`,
    // hairline border), `tap-scale` on press, `list-stagger` on first
    // paint.
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        for (final (index, type) in HostType.values.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ListStaggerItem(
              index: index,
              child: TapScale(
                onTap: () => onSelect(type),
                borderRadius: BorderRadius.circular(AppRadii.lg),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    border: Border.all(
                        color: AppColors.border.withValues(alpha: 0.6)),
                    boxShadow: AppShadows.sm,
                  ),
                  child: ListTile(
                    minVerticalPadding: AppSpacing.sm,
                    leading: const Icon(Icons.badge_outlined),
                    title: Text(type.label),
                    subtitle: Text(type.description),
                    onTap: () => onSelect(type),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _VerifiedStatusView extends StatelessWidget {
  const _VerifiedStatusView({required this.hostType, required this.onAction});

  final String hostType;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    // screens.md Screen 3a Modernization Notes: Verified is a genuine
    // milestone -- celebratory-tier illustration (accent/success) paired
    // with the `celebratory-sequence` motion token.
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: CelebratorySequence(
          icon: Icons.verified,
          accentColor: AppColors.success,
          supportingContent: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Verified Host',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.sm),
              Text('Your $hostType application has been approved.',
                  textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                  onPressed: onAction,
                  child: const Text('Go to Host Dashboard')),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusView extends StatelessWidget {
  const _StatusView({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    // In Review / Rejected: standard empty-state weight illustration
    // (single-tone, lower opacity) rather than the celebratory treatment.
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DeDukeIllustration(tier: IllustrationTier.empty),
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
