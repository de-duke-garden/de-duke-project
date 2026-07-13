/// Illustrated empty/error state -- branding.md "Empty & Loading States".
/// Centered column: illustration, `h3` headline, `body` supporting copy,
/// optional primary/secondary action. Never text-only.
library;

import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'illustration.dart';

class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.isError = false,
  });

  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  /// Error illustrations reuse the same empty-state tier per the
  /// Illustration System -- errors are not a distinct visual language.
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DeDukeIllustration(tier: IllustrationTier.empty),
            const SizedBox(height: AppSpacing.lg),
            Text(title,
                style: AppTypography.h3, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(message!,
                  style: AppTypography.body, textAlign: TextAlign.center),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
            if (secondaryActionLabel != null) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                  onPressed: onSecondaryAction,
                  child: Text(secondaryActionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
