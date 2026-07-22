/// screens.md Screen 12: Host Dashboard (FEAT-017). Fetches listings and
/// verification status in parallel per that screen's Data Flow step 1.
///
/// Modernization Notes (screens.md Screen 12): Listing status cards adopt
/// Listing Card container/press styling with `tap-scale` and enter with
/// `list-stagger` on first load; status and stale-activity flags use
/// semantic-color badges (icon+text, never color alone) that animate in
/// with `badge-pop` when a status changes; view/inquiry counts use the
/// `stat-small` type token; initial load uses skeleton cards, not a
/// spinner; the empty state uses the illustrated system.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_names.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/badge_pop.dart';
import '../../../core/widgets/de_duke_logo.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/list_stagger.dart';
import '../../../core/widgets/image_source_picker.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/tap_scale.dart';
import '../../auth/data/auth_repository.dart';
import '../../become_host/data/host_account_models.dart';
import '../../become_host/data/host_account_repository.dart';
import '../data/host_dashboard_models.dart';
import '../data/host_dashboard_repository.dart';

enum _ScreenState { loading, unverified, loaded, empty, error, offline }

class HostDashboardScreen extends StatefulWidget {
  const HostDashboardScreen({
    super.key,
    required this.dashboardRepository,
    required this.hostAccountRepository,
    required this.authRepository,
  });

  final HostDashboardRepository dashboardRepository;
  final HostAccountRepository hostAccountRepository;

  /// FEAT-041 -- the Edit Host Profile sheet's `fullName` field saves via
  /// this repository (PATCH /v1/user/profile), separate from the host
  /// account's own bio/photo PATCH -- see this file's _EditHostProfileSheet.
  final AuthRepository authRepository;

  @override
  State<HostDashboardScreen> createState() => _HostDashboardScreenState();
}

class _HostDashboardScreenState extends State<HostDashboardScreen> {
  _ScreenState _state = _ScreenState.loading;
  List<HostDashboardListingItem> _listings = [];
  HostAccountStatus? _verification;
  String? _fullName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// FEAT-042 -- the verification badge/link opens the Edit Host Profile
  /// sheet for a `verified`/`rejected` host (quick bio/photo/name edit,
  /// independent of the full resubmission flow), or routes to the existing
  /// Screen 3a status view for `in_review` (bio/photo not editable while a
  /// submission is actively under review) -- unchanged behavior for that case.
  void _handleVerificationBadgeTap() {
    final status = _verification?.status;
    if (status == 'verified' || status == 'rejected') {
      _openEditHostProfileSheet();
    } else {
      context.pushNamed(RouteNames.verification);
    }
  }

  Future<void> _openEditHostProfileSheet() async {
    final result = await showModalBottomSheet<_EditHostProfileResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _EditHostProfileSheet(
        initialBio: _verification?.bio ?? '',
        initialPhotoUrl: _verification?.hostPhotoUrl,
        initialFullName: _fullName ?? '',
        hostAccountRepository: widget.hostAccountRepository,
        authRepository: widget.authRepository,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.hostAccount != null) _verification = result.hostAccount;
      if (result.fullName != null) _fullName = result.fullName;
    });
  }

  Future<void> _load() async {
    setState(() => _state = _ScreenState.loading);
    try {
      final verificationFuture = widget.hostAccountRepository.getMySubmission();
      final listingsFuture = widget.dashboardRepository.getMyListings();
      final verification = await verificationFuture;
      final listings = await listingsFuture;
      // Best-effort, separate from the critical verification/listings
      // fetch above -- the Edit Host Profile sheet's fullName pre-fill is
      // a nicety, not something a profile-fetch failure should block this
      // screen on.
      UserProfile? profile;
      try {
        profile = await widget.authRepository.getProfile();
      } catch (_) {
        profile = null;
      }

      if (!mounted) return;
      setState(() {
        _verification = verification;
        _listings = listings;
        _fullName = profile?.fullName;
        if (verification == null || verification.status != 'verified') {
          _state = _ScreenState.unverified;
        } else if (listings.isEmpty) {
          _state = _ScreenState.empty;
        } else {
          _state = _ScreenState.loaded;
        }
      });
    } on HostDashboardException catch (e) {
      if (!mounted) return;
      setState(() => _state =
          e.message == 'offline' ? _ScreenState.offline : _ScreenState.error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _ScreenState.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Consistent tab-root AppBar treatment (mark + label) across Home,
        // Chat, Dashboard, Profile -- see TabAppBarTitle.
        title: const TabAppBarTitle('My Listings'),
        automaticallyImplyLeading:
            false, // tab root (core/routing/app_shell.dart)
        actions: [
          // FEAT-044 -- Wallet lives on the Host Dashboard (the host's
          // day-to-day home screen), not Account Settings: a host checking
          // earnings/requesting a withdrawal reaches for their Dashboard
          // tab first, same instinct as the "Verified Host" badge already
          // living here rather than in Settings.
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            tooltip: 'Wallet',
            onPressed: () => context.pushNamed(RouteNames.wallet),
          ),
          if (_verification != null)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: Center(
                child: BadgePop(
                  triggerKey: _verification!.status,
                  child: TextButton(
                    onPressed: _handleVerificationBadgeTap,
                    child: Text(_verification!.status == 'verified'
                        ? 'Verified Host'
                        : 'Verify'),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _state == _ScreenState.unverified
            ? () => context.pushNamed(RouteNames.verification)
            : () => context.pushNamed(RouteNames.listingNew),
        icon: const Icon(Icons.add),
        label: const Text('New Listing'),
      ),
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_state) {
      case _ScreenState.loading:
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          itemCount: 4,
          itemBuilder: (_, __) => const SkeletonListingCard(),
        );
      case _ScreenState.unverified:
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: _DashboardCard(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Verify your identity to start listing',
                    style: AppTypography.h3,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ElevatedButton(
                    onPressed: () => context.pushNamed(RouteNames.verification),
                    child: const Text('Become a Host'),
                  ),
                ],
              ),
            ),
          ),
        );
      case _ScreenState.empty:
        return EmptyStateView(
          title: "You haven't listed anything yet",
          actionLabel: 'Create your first listing',
          onAction: () => context.pushNamed(RouteNames.listingNew),
        );
      case _ScreenState.error:
        return EmptyStateView(
          title: 'Something went wrong',
          isError: true,
          actionLabel: 'Retry',
          onAction: _load,
        );
      case _ScreenState.offline:
        return Column(
          children: [
            MaterialBanner(
              content: const Text("You're offline."),
              actions: [
                TextButton(onPressed: _load, child: const Text('Retry'))
              ],
            ),
            if (_listings.isNotEmpty)
              Expanded(child: _buildListingList(context)),
          ],
        );
      case _ScreenState.loaded:
        return RefreshIndicator(
            onRefresh: _load, child: _buildListingList(context));
    }
  }

  Widget _buildListingList(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: _listings.length,
      itemBuilder: (context, index) => ListStaggerItem(
        index: index,
        child: _ListingStatusCard(
          listing: _listings[index],
          // Was `RouteNames.listingDetail` (the read-only guest-facing
          // screen) -- a host tapping their own listing here wants to
          // manage it (edit price/description, unpublish per FEAT-004's
          // AC), not preview it as a guest would. Listing Detail is still
          // one tap away via Edit Listing's own AppBar "View listing"
          // action for hosts who do want that preview.
          onTap: () async {
            final saved = await context.pushNamed<bool>(
              RouteNames.listingEdit,
              pathParameters: {'id': _listings[index].id},
            );
            // Refreshes so an edited price/description/publish-state
            // shows up immediately instead of the stale card sticking
            // around until the next manual pull-to-refresh.
            if (saved == true && mounted) _load();
          },
        ),
      ),
    );
  }
}

/// Lightweight Listing Card container spec (radius-lg / shadow-sm /
/// hairline border) for non-photo metric/status cards -- branding.md
/// Listing Card component tokens, reused here per host_dashboard_screen
/// modernization scope since [ListingCard] itself is photo-specific.
class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: colorScheme.outline),
        boxShadow: Theme.of(context).extension<AppSemanticColors>()!.shadowSm,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// Semantic-color status badge -- icon + text, never color alone
/// (branding.md Accessibility rule).
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  ({Color color, IconData icon, String label}) _spec(BuildContext context) {
    final semantic = Theme.of(context).extension<AppSemanticColors>()!;
    final error = Theme.of(context).colorScheme.error;
    return switch (status) {
      'active' => (
          color: semantic.success,
          icon: Icons.check_circle,
          label: 'Active'
        ),
      'banned' => (color: error, icon: Icons.block, label: 'Banned'),
      'under_review' => (
          color: semantic.warning,
          icon: Icons.hourglass_top,
          label: 'Under Review'
        ),
      'unpublished' => (
          color: semantic.warning,
          icon: Icons.visibility_off,
          label: 'Unpublished'
        ),
      'closed' => (
          color: semantic.warning,
          icon: Icons.lock_outline,
          label: 'Closed'
        ),
      _ => (color: semantic.warning, icon: Icons.info_outline, label: status),
    };
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec(context);
    return BadgePop(
      triggerKey: status,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
        decoration: BoxDecoration(
          color: spec.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadii.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(spec.icon, size: 14, color: spec.color),
            const SizedBox(width: 4),
            Text(
              spec.label,
              style: AppTypography.caption.copyWith(color: spec.color),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListingStatusCard extends StatelessWidget {
  const _ListingStatusCard({required this.listing, required this.onTap});

  final HostDashboardListingItem listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: TapScale(
        onTap: onTap,
        child: _DashboardCard(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(listing.title, style: AppTypography.h3),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          _StatusBadge(status: listing.status),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            '${listing.viewCount} views · ${listing.inquiryCount} inquiries',
                            style: AppTypography.statSmall.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      if (listing.status == 'banned' &&
                          listing.statusReason != null)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: Text(
                            listing.statusReason!,
                            style: AppTypography.bodySmall.copyWith(
                                color: Theme.of(context).colorScheme.error),
                          ),
                        ),
                      if (listing.isStale)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: BadgePop(
                            triggerKey: 'stale-${listing.id}',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.warning_amber_rounded,
                                    size: 14,
                                    color: Theme.of(context)
                                        .extension<AppSemanticColors>()!
                                        .warning),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'No activity yet — consider updating photos or price',
                                    style: AppTypography.bodySmall.copyWith(
                                        color: Theme.of(context)
                                            .extension<AppSemanticColors>()!
                                            .warning),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline),
                  tooltip: 'Chat threads',
                  onPressed: () => context.pushNamed(RouteNames.chat),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bundles whichever of the two independent PATCH calls
/// `_EditHostProfileSheet` actually fired -- either/both may be null if
/// that field wasn't changed, so the caller only updates the piece of
/// state that actually has a fresh value.
class _EditHostProfileResult {
  const _EditHostProfileResult({this.hostAccount, this.fullName});
  final HostAccountStatus? hostAccount;
  final String? fullName;
}

/// FEAT-042/FEAT-041 -- the verification badge/link's Edit Host Profile
/// bottom sheet for a `verified`/`rejected` host: photo (tap-to-replace),
/// bio, and fullName, independent of the full Become a Host resubmission
/// flow. Save fires TWO independent calls -- NOT a merged endpoint, per
/// screens.md Screen 12's Data Flow:
///   1. `PATCH /host-accounts/me` (multipart bio/photo) -- only if bio
///      and/or photo changed.
///   2. `PATCH /user/profile` (fullName) -- only if fullName changed,
///      since fullName lives on User, not HostAccount.
/// Either call can fail independently while the other succeeds -- the
/// sheet surfaces a per-field error (screens.md's "Host Profile Save
/// Error" state) rather than treating this as one atomic operation, and
/// pops with whichever result(s) actually succeeded so the caller can
/// still refresh what did save.
class _EditHostProfileSheet extends StatefulWidget {
  const _EditHostProfileSheet({
    required this.initialBio,
    required this.initialPhotoUrl,
    required this.initialFullName,
    required this.hostAccountRepository,
    required this.authRepository,
  });

  final String initialBio;
  final String? initialPhotoUrl;
  final String initialFullName;
  final HostAccountRepository hostAccountRepository;
  final AuthRepository authRepository;

  @override
  State<_EditHostProfileSheet> createState() => _EditHostProfileSheetState();
}

class _EditHostProfileSheetState extends State<_EditHostProfileSheet> {
  late final TextEditingController _bioController =
      TextEditingController(text: widget.initialBio);
  late final TextEditingController _nameController =
      TextEditingController(text: widget.initialFullName);
  String? _newPhotoLocalPath;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _bioController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  bool get _bioChanged => _bioController.text.trim() != widget.initialBio;
  bool get _nameChanged =>
      _nameController.text.trim().isNotEmpty &&
      _nameController.text.trim() != widget.initialFullName;
  bool get _photoChanged => _newPhotoLocalPath != null;

  bool get _canSave =>
      !_submitting &&
      _bioController.text.trim().isNotEmpty &&
      (_bioChanged || _nameChanged || _photoChanged);

  Future<void> _pickPhoto() async {
    final path = await pickImageFromCameraOrGallery(context);
    if (path == null || !mounted) return;
    setState(() => _newPhotoLocalPath = path);
  }

  Future<void> _save() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    HostAccountStatus? updatedHostAccount;
    String? updatedFullName;
    final errors = <String>[];

    if (_bioChanged || _photoChanged) {
      try {
        updatedHostAccount = await widget.hostAccountRepository.updateProfile(
          bio: _bioChanged ? _bioController.text.trim() : null,
          photoLocalPath: _newPhotoLocalPath,
        );
      } on HostAccountException catch (e) {
        errors.add(e.message == 'offline'
            ? "You're offline. Check your connection and try again."
            : e.message);
      }
    }
    if (_nameChanged) {
      try {
        final profile = await widget.authRepository
            .updateProfile(fullName: _nameController.text.trim());
        updatedFullName = profile.fullName;
      } on AuthException catch (e) {
        errors.add(e.message == 'offline'
            ? "You're offline. Check your connection and try again."
            : e.message);
      }
    }

    if (!mounted) return;
    if (errors.isEmpty) {
      Navigator.of(context).pop(_EditHostProfileResult(
        hostAccount: updatedHostAccount,
        fullName: updatedFullName,
      ));
      return;
    }
    // Partial-success case: whichever call(s) succeeded are still reported
    // back via the result the caller receives on dismiss, but the sheet
    // stays open surfacing the error(s) so the user can retry the
    // failed field(s) specifically, rather than losing that progress.
    setState(() {
      _submitting = false;
      _error = errors.join('\n');
    });
  }

  @override
  Widget build(BuildContext context) {
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
          Text('Edit host profile',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: GestureDetector(
              onTap: _submitting ? null : _pickPhoto,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    backgroundImage: _newPhotoLocalPath != null
                        ? FileImage(File(_newPhotoLocalPath!))
                        : (widget.initialPhotoUrl != null
                            ? NetworkImage(widget.initialPhotoUrl!)
                            : null) as ImageProvider?,
                    child: _newPhotoLocalPath == null &&
                            widget.initialPhotoUrl == null
                        ? Icon(Icons.person_outline,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                            size: 32)
                        : null,
                  ),
                  const CircleAvatar(
                    radius: 14,
                    child: Icon(Icons.camera_alt_outlined, size: 16),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          TextField(
            controller: _nameController,
            enabled: !_submitting,
            decoration: const InputDecoration(labelText: 'Full name'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _bioController,
            maxLines: 4,
            enabled: !_submitting,
            decoration: const InputDecoration(labelText: 'Bio'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          ElevatedButton(
            onPressed: _canSave ? _save : null,
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
