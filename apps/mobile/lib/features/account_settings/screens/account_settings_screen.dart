/// screens.md Screen 21: Account Settings.
///
/// Profile fields (name/contact) and notification preferences are shown
/// read-only / as "not yet available" respectively -- schema.md/features.md
/// do not define GET/PATCH /user/profile or /user/notification-preferences
/// endpoints anywhere in this codebase (FEAT-022 push preferences is P1
/// and not yet built), so this screen does not fabricate editable fields
/// that would silently no-op. Log Out and Request Account Deletion are
/// fully wired to real backend endpoints (FEAT-001, FEAT-030).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../../auth/data/auth_repository.dart';
import '../data/account_deletion_repository.dart';

enum _ScreenState { loading, loaded, error, offline }

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({
    super.key,
    required this.authRepository,
    required this.accountDeletionRepository,
  });

  final AuthRepository authRepository;
  final AccountDeletionRepository accountDeletionRepository;

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  _ScreenState _state = _ScreenState.loading;
  CurrentUser? _user;
  String? _errorMessage;
  bool _actionInFlight = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _ScreenState.loading);
    try {
      final user = await widget.authRepository.getCurrentUser();
      if (!mounted) return;
      setState(() {
        _user = user;
        _state = _ScreenState.loaded;
      });
    } catch (e) {
      if (!mounted) return;
      final message = e is AuthException ? e.message : 'Something went wrong.';
      setState(() {
        _state =
            message == 'offline' ? _ScreenState.offline : _ScreenState.error;
        _errorMessage = message == 'offline'
            ? "You're offline. Check your connection and try again."
            : message;
      });
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out of De-Duke?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Log out')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _actionInFlight = true);
    await widget.authRepository.logout();
    if (!mounted) return;
    context.go('/auth/login');
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'Your profile, saved searches, and notification preferences are deleted immediately. '
          'Verification documents are anonymized. Transaction and financial records are retained '
          'for the legally required period. This cannot be undone.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _actionInFlight = true);
    try {
      final result = await widget.accountDeletionRepository.requestDeletion();
      if (!mounted) return;
      await _showDeletionSummary(result);
      await widget.authRepository.logout();
      if (!mounted) return;
      context.go('/auth/login');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _actionInFlight = false;
        _state = _ScreenState.error;
        _errorMessage = e is AccountDeletionException
            ? e.message
            : 'Could not process your deletion request.';
      });
    }
  }

  Future<void> _showDeletionSummary(AccountDeletionResult result) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Account deletion requested'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Deleted immediately:',
                  style: Theme.of(context).textTheme.titleSmall),
              for (final item in result.deletedImmediately) Text('• $item'),
              const SizedBox(height: AppSpacing.sm),
              Text('Anonymized immediately:',
                  style: Theme.of(context).textTheme.titleSmall),
              for (final item in result.anonymizedImmediately) Text('• $item'),
              const SizedBox(height: AppSpacing.sm),
              Text('Retained for a defined period:',
                  style: Theme.of(context).textTheme.titleSmall),
              for (final item in result.retainedForADefinedPeriod)
                Text('• $item'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: switch (_state) {
        _ScreenState.loading => const _SkeletonList(),
        _ScreenState.error => _ErrorBanner(
            message: _errorMessage ?? 'Something went wrong.', onRetry: _load),
        _ScreenState.offline => _ErrorBanner(
            message: _errorMessage ??
                "You're offline. Check your connection and try again.",
            onRetry: _load,
          ),
        _ScreenState.loaded => _buildLoaded(context),
      },
    );
  }

  Widget _buildLoaded(BuildContext context) {
    final user = _user!;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _SectionHeader('Profile'),
        Card(
          child: Column(
            children: [
              ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(user.fullName)),
              if (user.email != null)
                ListTile(
                    leading: const Icon(Icons.email_outlined),
                    title: Text(user.email!)),
              if (user.phoneNumber != null)
                ListTile(
                    leading: const Icon(Icons.phone_outlined),
                    title: Text(user.phoneNumber!)),
              if (user.isVerifiedHost)
                const ListTile(
                  leading: Icon(Icons.verified, color: Colors.green),
                  title: Text('Verified Host'),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _SectionHeader('Role'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: Text(_roleLabel(user.role)),
            trailing: (user.role == 'individual_host' || user.role == 'agency')
                ? TextButton(
                    onPressed: () => context.push('/become-host'),
                    child: const Text('Verification status'),
                  )
                : null,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _SectionHeader('Notifications'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Push & email preferences'),
            subtitle: const Text('Coming soon'),
            enabled: false,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _SectionHeader('Legal'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Terms of Service'),
                onTap: () => _showNotYetAvailable(context),
              ),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Privacy Policy'),
                onTap: () => _showNotYetAvailable(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _SectionHeader('Data & Privacy'),
        Card(
          child: ListTile(
            leading: Icon(Icons.delete_outline,
                color: Theme.of(context).colorScheme.error),
            title: Text('Delete account',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: _actionInFlight ? null : _confirmDeleteAccount,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Card(
          child: ListTile(
            leading:
                Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
            title: Text('Log Out',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: _actionInFlight ? null : _confirmLogout,
          ),
        ),
      ],
    );
  }

  void _showNotYetAvailable(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Legal pages are not yet published. Check back soon.')),
    );
  }

  String _roleLabel(String role) => switch (role) {
        'seeker' => 'Individual Seeker',
        'individual_host' => 'Individual Host',
        'agency' => 'Agency',
        'corporate' => 'Business/Corporate',
        'deduke_staff' => 'De-Duke Staff',
        'deduke_admin' => 'De-Duke Admin',
        _ => role,
      };
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: List.generate(
        4,
        (_) => Container(
          height: 56,
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: AppSpacing.md),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
