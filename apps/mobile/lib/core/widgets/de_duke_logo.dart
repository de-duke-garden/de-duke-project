/// De-Duke brand mark -- branding.md's Logo & Iconography section.
///
/// The shipped asset (`assets/images/de-duke.png`) is the mark-only
/// lockup (no wordmark baked into the file, transparent background).
/// Two widgets cover the two documented usages:
/// - [DeDukeLogo]: the mark alone -- app icon/favicon parity inside the
///   app itself, used as the in-app compact header (chat, notifications,
///   Home Feed's `AppBar`).
/// - [DeDukeLogoLockup]: mark + separately-set Manrope wordmark, used on
///   the splash screen and other marketing-tier surfaces (e.g. the
///   Sign-Up/Login screen's full-bleed branded top section).
///
/// Both respect branding.md's clear-space rule ("always on a clear-space
/// margin of at least the height of one 'D' stroke") via [clearSpace],
/// which defaults to a value proportional to the mark's own size.
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

class DeDukeLogo extends StatelessWidget {
  const DeDukeLogo({super.key, this.size = 28, this.clearSpace});

  /// Rendered mark height/width (the asset is roughly square).
  final double size;

  /// Padding applied uniformly around the mark. Defaults to ~1 "D" stroke
  /// width, approximated as 18% of [size] per branding.md's clear-space
  /// rule -- there's no literal stroke-width metric to reference, so this
  /// is a deliberate, documented approximation rather than an exact value.
  final double? clearSpace;

  @override
  Widget build(BuildContext context) {
    final resolvedClearSpace = clearSpace ?? size * 0.18;
    return Padding(
      padding: EdgeInsets.all(resolvedClearSpace),
      child: Image.asset(
        'assets/images/de-duke.png',
        height: size,
        width: size,
        fit: BoxFit.contain,
        semanticLabel: 'De-Duke',
      ),
    );
  }
}

/// Standard `AppBar` title for the four bottom-nav tab roots (Home, Chat,
/// Dashboard, Profile per `core/routing/app_shell.dart`) -- mark + tab
/// label, consistently, on every tab root. Established by Chat Inbox's
/// original "mark alone doesn't communicate which tab this is" reasoning;
/// applied here to all four so the chrome doesn't feel like a different
/// app depending on which tab you're on (Home Feed/Chat Inbox previously
/// used the mark inconsistently, and Dashboard/Profile omitted it
/// entirely).
class TabAppBarTitle extends StatelessWidget {
  const TabAppBarTitle(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const DeDukeLogo(size: 28, clearSpace: 0),
        const SizedBox(width: AppSpacing.sm),
        Text(label),
      ],
    );
  }
}

class DeDukeLogoLockup extends StatelessWidget {
  const DeDukeLogoLockup({
    super.key,
    this.markSize = 56,
    this.direction = Axis.vertical,
  });

  /// Size of the mark half of the lockup; the wordmark scales with it.
  final double markSize;

  /// Vertical (splash/onboarding, mark above wordmark) or horizontal
  /// (compact marketing header, mark beside wordmark) arrangement.
  final Axis direction;

  @override
  Widget build(BuildContext context) {
    final mark = Image.asset(
      'assets/images/de-duke.png',
      height: markSize,
      width: markSize,
      fit: BoxFit.contain,
      semanticLabel: 'De-Duke',
    );
    // branding.md: Manrope 700 weight, uppercase, tracked out slightly.
    // "De-Duke" per README.md/branding.md's Product Name casing.
    final wordmark = Text(
      'DE-DUKE',
      style: AppTypography.h2.copyWith(
        fontFamily: 'Manrope',
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
        // color: AppColors.textPrimary,
        // color: Theme.of(context).
      ),
    );

    if (direction == Axis.horizontal) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [mark, const SizedBox(width: AppSpacing.sm), wordmark],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [mark, const SizedBox(height: AppSpacing.sm), wordmark],
    );
  }
}
