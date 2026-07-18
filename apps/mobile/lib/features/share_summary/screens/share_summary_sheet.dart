/// screens.md Screen 17: Shareable Summary (Generate).
///
/// A `ModalBottomSheet` (not a full screen/route) opened from Listing
/// Detail's Share action. Lets a corporate seeker (David persona, FEAT-020)
/// generate a no-login-required link summarizing a listing, then copy or
/// hand it to the OS share sheet, or revoke it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/env.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../listings/data/listing_models.dart';
import '../data/share_models.dart';
import '../data/share_repository.dart';

enum _SheetState { preview, generating, generated, error, revoking, offline }

/// Opens Screen 17 as a modal bottom sheet. Call from Listing Detail's
/// Share `IconButton`.
Future<void> showShareSummarySheet(
  BuildContext context, {
  required Listing listing,
  required ShareRepository repository,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
    ),
    builder: (_) => ShareSummarySheet(listing: listing, repository: repository),
  );
}

class ShareSummarySheet extends StatefulWidget {
  const ShareSummarySheet({
    super.key,
    required this.listing,
    required this.repository,
  });

  final Listing listing;
  final ShareRepository repository;

  @override
  State<ShareSummarySheet> createState() => _ShareSummarySheetState();
}

class _ShareSummarySheetState extends State<ShareSummarySheet> {
  _SheetState _state = _SheetState.preview;
  ShareLink? _shareLink;
  String? _errorMessage;
  bool _justCopied = false;

  String get _fullShareUrl =>
      '${AppConfig.publicShareBaseUrl}/s/${_shareLink!.shareToken}';

  Future<void> _generate() async {
    setState(() => _state = _SheetState.generating);
    try {
      final link = await widget.repository.generateShareLink(widget.listing.id);
      if (!mounted) return;
      setState(() {
        _shareLink = link;
        _state = _SheetState.generated;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      final message = e.toString();
      final isOffline = message.contains('SocketException') ||
          message.contains('connection');
      if (isOffline) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("You're offline. Try again once connected.")),
        );
        setState(() => _state = _SheetState.preview);
      } else {
        setState(() {
          _errorMessage = message;
          _state = _SheetState.error;
        });
      }
    }
  }

  Future<void> _revoke() async {
    final link = _shareLink;
    if (link == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Revoke this link?'),
        content: const Text(
          'Anyone with the old link will no longer be able to view this summary.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _state = _SheetState.revoking);
    try {
      await widget.repository.revokeShareLink(widget.listing.id, link.shareToken);
      if (!mounted) return;
      // Edge case (screens.md Screen 17): after revoking, the sheet returns
      // to its pre-generation state -- a fresh "Generate Link" tap always
      // mints a brand-new token server-side, the old one stays dead.
      setState(() {
        _shareLink = null;
        _state = _SheetState.preview;
      });
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't revoke the link. Try again.")),
      );
      setState(() => _state = _SheetState.generated);
    }
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _fullShareUrl));
    if (!mounted) return;
    setState(() => _justCopied = true);
    Future.delayed(AppDurations.instant * 6, () {
      if (mounted) setState(() => _justCopied = false);
    });
  }

  Future<void> _shareLinkExternally() async {
    await SharePlus.instance.share(
      ShareParams(
        text: 'Take a look at this listing on De-Duke: $_fullShareUrl',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom: AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Share Summary', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            _buildPreview(context),
            const SizedBox(height: AppSpacing.lg),
            _buildActionArea(context),
          ],
        ),
      ),
    );
  }

  /// Read-only preview of what will be shared -- price, location, key terms,
  /// verification status -- built entirely from the already-loaded Listing
  /// Detail payload (screens.md: "no extra fetch needed").
  Widget _buildPreview(BuildContext context) {
    final listing = widget.listing;
    final commercial = listing.commercial;
    final shortlet = listing.shortlet;
    final priceLabel = commercial != null
        ? '₦${commercial.price.toStringAsFixed(0)}${commercial.dealType == 'lease' ? ' / lease' : ''}'
        : shortlet != null
            ? '₦${shortlet.nightlyPrice.toStringAsFixed(0)} / night'
            : '';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(listing.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '${listing.addressLine}, ${listing.city}, ${listing.state}',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(priceLabel, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                listing.isVerifiedActive ? Icons.verified : Icons.info_outline,
                size: 16,
                color: listing.isVerifiedActive
                    ? AppColors.verified
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                listing.isVerifiedActive ? 'Verified' : 'Unverified',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionArea(BuildContext context) {
    switch (_state) {
      case _SheetState.preview:
        return ElevatedButton(
          onPressed: _generate,
          child: const Text('Generate Link'),
        );
      case _SheetState.generating:
        return const ElevatedButton(
          onPressed: null,
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case _SheetState.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _errorMessage ?? 'Something went wrong generating this link.',
              style: const TextStyle(color: AppColors.error),
            ),
            const SizedBox(height: AppSpacing.sm),
            ElevatedButton(onPressed: _generate, child: const Text('Retry')),
          ],
        );
      case _SheetState.generated:
      case _SheetState.revoking:
        return _buildGeneratedLinkArea(context);
      case _SheetState.offline:
        // Unreachable directly (handled via SnackBar in _generate), kept
        // for state-machine completeness/documentation per screens.md.
        return const SizedBox.shrink();
    }
  }

  Widget _buildGeneratedLinkArea(BuildContext context) {
    final revoking = _state == _SheetState.revoking;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          readOnly: true,
          controller: TextEditingController(text: _fullShareUrl),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            // `badge-pop`-style reveal on the copy/share icons per
            // screens.md's Modernization Notes -- a light touch scale-in
            // rather than a hero treatment for this small utility sheet.
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.85, end: 1),
              duration: AppDurations.badgePop,
              curve: AppCurves.easeSpringSoft,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: IconButton(
                onPressed: _copyLink,
                icon: const Icon(Icons.copy),
                tooltip: 'Copy link',
              ),
            ),
            AnimatedOpacity(
              opacity: _justCopied ? 1 : 0,
              duration: AppDurations.instant,
              child: const Text('Copied!', style: TextStyle(color: AppColors.success)),
            ),
            const Spacer(),
            IconButton(
              onPressed: _shareLinkExternally,
              icon: const Icon(Icons.ios_share),
              tooltip: 'Share',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: revoking ? null : _revoke,
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: revoking
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Revoke Link'),
        ),
      ],
    );
  }
}
