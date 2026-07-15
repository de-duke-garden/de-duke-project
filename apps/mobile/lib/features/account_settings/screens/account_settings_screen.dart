/// screens.md Screen 21: Account Settings.
///
/// Profile fields (FEAT-041, GET/PATCH /v1/user/profile): `fullName` is
/// editable regardless of `authProvider`; `email`/`phoneNumber` are
/// read-only for `firebase`-provider accounts (owned by Google/Firebase,
/// per schema.md), `email` is additionally editable for `password`-
/// provider accounts (agency team members, Staff/Admin). Security section
/// (FEAT-040, Linked Sign-In Methods) lets a `password`-provider account
/// attach/remove a Firebase-based sign-in path. Push (FEAT-022) and email
/// (FEAT-024) notification preferences, Log Out, and Request Account
/// Deletion (FEAT-030) are all real, wired to their respective endpoints.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/badge_pop.dart';
import '../../../core/widgets/de_duke_logo.dart';
import '../../auth/data/auth_repository.dart';
import '../../push_notifications/data/push_notification_repository.dart';
import '../data/account_deletion_repository.dart';
import 'link_sign_in_sheet.dart';

enum _ScreenState { loading, loaded, error, offline }

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({
    super.key,
    required this.authRepository,
    required this.accountDeletionRepository,
    required this.pushNotificationRepository,
  });

  final AuthRepository authRepository;
  final AccountDeletionRepository accountDeletionRepository;
  final PushNotificationRepository pushNotificationRepository;

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  _ScreenState _state = _ScreenState.loading;
  CurrentUser? _user;
  UserProfile? _profile;
  String? _errorMessage;
  bool _actionInFlight = false;
  bool _linkActionInFlight = false;
  Map<String, bool>? _pushPreferences;
  Map<String, bool>? _emailPreferences;
  // Screen 21 Modernization Notes: the "Saving" state's inline checkmark
  // confirmation uses a quick duration-fast fade rather than a lingering
  // spinner for auto-saved fields. Keyed by 'push:<category>' /
  // 'email:<category>'; briefly holds the just-saved key so the checkmark
  // can fade in then back out.
  String? _justSavedKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _ScreenState.loading);
    try {
      final user = await widget.authRepository.getCurrentUser();
      final profile = await widget.authRepository.getProfile();
      // Best-effort, separate from the critical profile fetch above --
      // both preference sections are secondary to this screen's core
      // purpose, so a failure in either shouldn't block the rest of
      // Account Settings from loading (each toggle row just falls back to
      // a disabled state, per _buildLoaded below).
      Map<String, bool>? pushPreferences;
      try {
        pushPreferences =
            await widget.pushNotificationRepository.getPreferences();
      } catch (_) {
        pushPreferences = null;
      }
      Map<String, bool>? emailPreferences;
      try {
        emailPreferences = await widget.authRepository.getEmailPreferences();
      } catch (_) {
        emailPreferences = null;
      }
      if (!mounted) return;
      setState(() {
        _user = user;
        _profile = profile;
        _pushPreferences = pushPreferences;
        _emailPreferences = emailPreferences;
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

  Future<void> _togglePushPreference(String category, bool value) async {
    final previous = _pushPreferences;
    // Optimistic update -- reverted in the catch block if the PATCH fails,
    // same UX pattern as a toggle switch anywhere else in this app.
    setState(() => _pushPreferences = {...?_pushPreferences, category: value});
    try {
      final updated = await widget.pushNotificationRepository
          .updatePreferences({category: value});
      if (!mounted) return;
      setState(() => _pushPreferences = updated);
      _flashSaved('push:$category');
    } catch (_) {
      if (!mounted) return;
      setState(() => _pushPreferences = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't save that -- try again.")),
      );
    }
  }

  Future<void> _toggleEmailPreference(String category, bool value) async {
    final previous = _emailPreferences;
    setState(
        () => _emailPreferences = {...?_emailPreferences, category: value});
    try {
      final updated =
          await widget.authRepository.updateEmailPreferences({category: value});
      if (!mounted) return;
      setState(() => _emailPreferences = updated);
      _flashSaved('email:$category');
    } catch (_) {
      if (!mounted) return;
      setState(() => _emailPreferences = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't save that -- try again.")),
      );
    }
  }

  void _flashSaved(String key) {
    setState(() => _justSavedKey = key);
    Future.delayed(AppDurations.slow, () {
      if (!mounted || _justSavedKey != key) return;
      setState(() => _justSavedKey = null);
    });
  }

  /// FEAT-041 -- `fullName` is editable regardless of `authProvider`. A
  /// simple text-entry dialog rather than an inline field: this screen's
  /// other rows are read-only display/toggle, so a dialog keeps the edit
  /// affordance unambiguous rather than making every ListTile look tappable.
  Future<void> _editFullName() async {
    final controller = TextEditingController(text: _profile?.fullName ?? '');
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Full name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == _profile?.fullName) {
      return;
    }
    await _saveProfile(fullName: newName);
  }

  /// FEAT-041 -- `email` is editable only for `password`-provider accounts
  /// (agency team members, Staff/Admin); the backend also rejects this
  /// server-side for `firebase`-provider accounts regardless of what's
  /// sent, but this screen doesn't even offer the affordance for them.
  Future<void> _editEmail() async {
    final controller = TextEditingController(text: _profile?.email ?? '');
    final newEmail = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit email'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Email'),
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newEmail == null || newEmail.isEmpty || newEmail == _profile?.email) {
      return;
    }
    await _saveProfile(email: newEmail);
  }

  Future<void> _saveProfile({String? fullName, String? email}) async {
    try {
      final updated = await widget.authRepository
          .updateProfile(fullName: fullName, email: email);
      if (!mounted) return;
      setState(() => _profile = updated);
      _flashSaved('profile:${fullName != null ? 'name' : 'email'}');
    } catch (e) {
      if (!mounted) return;
      final message =
          e is AuthException ? e.message : "Couldn't save that -- try again.";
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// FEAT-040 -- opens the inline Google/Phone/Email flow (same methods
  /// as Screen 1), then re-fetches the profile so the row reflects the
  /// new linked state.
  Future<void> _linkSignInMethod() async {
    final linked =
        await showLinkSignInSheet(context, repository: widget.authRepository);
    if (linked != true || !mounted) return;
    try {
      final updated = await widget.authRepository.getProfile();
      if (!mounted) return;
      setState(() => _profile = updated);
    } catch (_) {
      // Best-effort refresh -- the link itself already succeeded.
    }
  }

  Future<void> _unlinkSignInMethod() async {
    setState(() => _linkActionInFlight = true);
    try {
      await widget.authRepository.unlinkFirebaseIdentity();
      final updated = await widget.authRepository.getProfile();
      if (!mounted) return;
      setState(() {
        _profile = updated;
        _linkActionInFlight = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _linkActionInFlight = false);
      final message =
          e is AuthException ? e.message : "Couldn't unlink -- try again.";
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
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
    context.goNamed(
      RouteNames.auth,
      queryParameters: const {'mode': 'login'},
    );
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
      context.goNamed(
        RouteNames.auth,
        queryParameters: const {'mode': 'login'},
      );
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
      appBar: AppBar(
        // Consistent tab-root AppBar treatment (mark + label) across Home,
        // Chat, Dashboard, Profile -- see TabAppBarTitle.
        title: const TabAppBarTitle('Settings'),
        automaticallyImplyLeading:
            false, // tab root (core/routing/app_shell.dart)
      ),
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
    final profile = _profile;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _SectionHeader('Profile'),
        Card(
          child: Column(
            children: [
              // fullName -- editable regardless of authProvider (FEAT-041).
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(profile?.fullName ?? user.fullName),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedOpacity(
                      opacity: _justSavedKey == 'profile:name' ? 1 : 0,
                      duration: AppDurations.fast,
                      child: const Icon(Icons.check_circle,
                          size: 18, color: AppColors.primary),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    const Icon(Icons.edit_outlined, size: 18),
                  ],
                ),
                onTap: _editFullName,
              ),
              // email -- read-only for firebase-provider accounts (owned
              // by Google/Firebase), editable for password-provider ones.
              if (user.email != null)
                ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: Text(user.email!),
                  subtitle: profile?.isFirebaseProvider == true
                      ? const Text('Managed by Google/Firebase')
                      : null,
                  trailing: profile?.isPasswordProvider == true
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedOpacity(
                              opacity: _justSavedKey == 'profile:email' ? 1 : 0,
                              duration: AppDurations.fast,
                              child: const Icon(Icons.check_circle,
                                  size: 18, color: AppColors.primary),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            const Icon(Icons.edit_outlined, size: 18),
                          ],
                        )
                      : null,
                  onTap:
                      profile?.isPasswordProvider == true ? _editEmail : null,
                ),
              if (user.phoneNumber != null)
                ListTile(
                    leading: const Icon(Icons.phone_outlined),
                    title: Text(user.phoneNumber!),
                    subtitle: profile?.isFirebaseProvider == true
                        ? const Text('Managed by Google/Firebase')
                        : null),
              if (user.isVerifiedHost)
                const ListTile(
                  leading: Icon(Icons.verified, color: Colors.green),
                  title: Text('Verified Host'),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        // FEAT-040 -- Linked Sign-In Methods. Only shown for
        // password-provider accounts (agency team members, Staff/Admin) --
        // a firebase-provider account has no password-provider row to
        // reconcile, so linking doesn't apply to it.
        if (profile?.isPasswordProvider == true) ...[
          _SectionHeader('Security'),
          Card(
            child: AnimatedSize(
              duration: AppDurations.fast,
              curve: AppCurves.easeOutSmooth,
              child: BadgePop(
                triggerKey: profile!.isFirebaseLinked,
                child: ListTile(
                  key: ValueKey('linked-${profile.isFirebaseLinked}'),
                  leading: Icon(
                      profile.isFirebaseLinked ? Icons.link : Icons.link_off),
                  title: const Text('Linked sign-in methods'),
                  subtitle: Text(_linkActionInFlight
                      ? (profile.isFirebaseLinked
                          ? 'Unlinking...'
                          : 'Linking...')
                      : (profile.isFirebaseLinked ? 'Linked' : 'Not linked')),
                  trailing: _linkActionInFlight
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : TextButton(
                          onPressed: profile.isFirebaseLinked
                              ? _unlinkSignInMethod
                              : _linkSignInMethod,
                          child: Text(profile.isFirebaseLinked
                              ? 'Unlink'
                              : 'Link a sign-in method'),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        _SectionHeader('Role'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(_roleLabel(user.role)),
                trailing:
                    (user.role == 'individual_host' || user.role == 'agency')
                        ? TextButton(
                            onPressed: () =>
                                context.pushNamed(RouteNames.verification),
                            child: const Text('Verification status'),
                          )
                        : null,
              ),
              // FEAT-003 AC: "Role can be changed later in account
              // settings." Reuses RoleSelectionScreen -- its Data Flow's
              // post-selection routing (Become a Host vs Home Feed)
              // applies here too, since switching TO Host/Agency should
              // still lead into that flow.
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('Change role'),
                onTap: () => context.pushNamed(RouteNames.authRole),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        // FEAT-022 AC: "User can manage notification preferences per
        // category in settings." Push's own category set (listings, chat,
        // payments) -- see app/models/user.py's
        // DEFAULT_PUSH_NOTIFICATION_PREFERENCES.
        _SectionHeader('Push Notifications'),
        Card(
          // Screen 21 Modernization Notes: grouped settings sections use
          // subtle duration-fast expand transitions where sub-options
          // reveal -- here, the per-category channels appearing once
          // preferences load.
          child: AnimatedSize(
            duration: AppDurations.fast,
            curve: AppCurves.easeOutSmooth,
            child: _pushPreferences == null
                ? const ListTile(
                    key: ValueKey('push-unavailable'),
                    leading: Icon(Icons.notifications_outlined),
                    title: Text('Push preferences'),
                    subtitle: Text('Not available right now'),
                    enabled: false,
                  )
                : Column(
                    key: const ValueKey('push-loaded'),
                    children: [
                      _PreferenceSwitchRow(
                        icon: Icons.home_work_outlined,
                        title: 'Listings',
                        subtitle: 'Listing status changes',
                        value: _pushPreferences!['listings'] ?? true,
                        justSaved: _justSavedKey == 'push:listings',
                        onChanged: (v) => _togglePushPreference('listings', v),
                      ),
                      _PreferenceSwitchRow(
                        icon: Icons.chat_bubble_outline,
                        title: 'Chat',
                        subtitle: 'New messages',
                        value: _pushPreferences!['chat'] ?? true,
                        justSaved: _justSavedKey == 'push:chat',
                        onChanged: (v) => _togglePushPreference('chat', v),
                      ),
                      _PreferenceSwitchRow(
                        icon: Icons.payments_outlined,
                        title: 'Payments',
                        subtitle: 'Bookings and payment confirmations',
                        value: _pushPreferences!['payments'] ?? true,
                        justSaved: _justSavedKey == 'push:payments',
                        onChanged: (v) => _togglePushPreference('payments', v),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        // FEAT-024 AC: "User can manage email notification preferences per
        // category in settings, separate from push preferences." Email's
        // own category set (account, verification, payments) --
        // deliberately different from push's -- see
        // app/models/user.py's DEFAULT_EMAIL_NOTIFICATION_PREFERENCES.
        _SectionHeader('Email Notifications'),
        Card(
          child: AnimatedSize(
            duration: AppDurations.fast,
            curve: AppCurves.easeOutSmooth,
            child: _emailPreferences == null
                ? const ListTile(
                    key: ValueKey('email-unavailable'),
                    leading: Icon(Icons.email_outlined),
                    title: Text('Email preferences'),
                    subtitle: Text('Not available right now'),
                    enabled: false,
                  )
                : Column(
                    key: const ValueKey('email-loaded'),
                    children: [
                      _PreferenceSwitchRow(
                        icon: Icons.person_outline,
                        title: 'Account',
                        subtitle:
                            'Welcome, password reset, deletion confirmation',
                        value: _emailPreferences!['account'] ?? true,
                        justSaved: _justSavedKey == 'email:account',
                        onChanged: (v) => _toggleEmailPreference('account', v),
                      ),
                      _PreferenceSwitchRow(
                        icon: Icons.verified_outlined,
                        title: 'Verification',
                        subtitle: 'Host verification approved/rejected',
                        value: _emailPreferences!['verification'] ?? true,
                        justSaved: _justSavedKey == 'email:verification',
                        onChanged: (v) =>
                            _toggleEmailPreference('verification', v),
                      ),
                      _PreferenceSwitchRow(
                        icon: Icons.payments_outlined,
                        title: 'Payments',
                        subtitle: 'Booking, payment, and payout confirmations',
                        value: _emailPreferences!['payments'] ?? true,
                        justSaved: _justSavedKey == 'email:payments',
                        onChanged: (v) => _toggleEmailPreference('payments', v),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        // screens.md Screen 19 (Transaction History) Entry Points includes
        // "Account Settings" -- previously missing here entirely.
        Card(
          child: ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('Transaction History'),
            onTap: () => context.pushNamed(RouteNames.transactions),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        // FEAT-029: General In-App Support / Help -- entry point for a
        // conversation not tied to any specific listing.
        Card(
          child: ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Help & Support'),
            onTap: () => context.pushNamed(RouteNames.support),
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

/// A notification-preference toggle row. Wraps the `Switch` in [BadgePop]
/// (keyed to its value) for a badge-pop-style settle on flip, and shows a
/// brief duration-fast fading checkmark in place of a lingering spinner
/// once the auto-save completes (screens.md Screen 21 Modernization Notes).
class _PreferenceSwitchRow extends StatelessWidget {
  const _PreferenceSwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.justSaved,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool justSaved;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedOpacity(
            opacity: justSaved ? 1 : 0,
            duration: AppDurations.fast,
            child: Icon(Icons.check_circle, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: AppSpacing.xs),
          BadgePop(
            triggerKey: value,
            child: Switch(value: value, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
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
