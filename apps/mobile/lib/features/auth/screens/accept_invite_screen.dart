/// FEAT-012 (Agency Team Inbox) invite acceptance -- reached from Screen 1's
/// "Have an invite link?" entry point. An agency admin invites a team
/// member via TeamManagementScreen -> POST /v1/agency/team/invite, which
/// emails a link of the form
/// `<mobile-app-invite-base-url>/accept-invite?token=...&uid=...` (see
/// app/api/v1/agency.py). No mobile deep-linking (Android App Links / iOS
/// Universal Links) is configured anywhere in this codebase yet -- that
/// requires hosting `assetlinks.json`/`apple-app-site-association` files
/// alongside real production domains, which is an infra/deploy concern out
/// of this feature's scope, not something to fabricate here. Instead, the
/// invitee pastes the link (or just the token/uid) directly into this
/// screen. Unlike Screen 1's Sign-Up/Login (FEAT-001, entirely Firebase
/// now), FEAT-012 team-member accounts are still backend-managed password
/// accounts (auth_provider "password") -- this invite/accept-password flow
/// is unaffected by that rewrite; see auth_service.py's module docstring.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../data/auth_repository.dart';

enum _ScreenState { idle, submitting, success, error, offline }

class AcceptInviteScreen extends StatefulWidget {
  const AcceptInviteScreen({
    super.key,
    required this.repository,
    required this.onAccepted,
  });

  final AuthRepository repository;

  /// Called after a successful accept-invite -- the caller (app_router.dart)
  /// is responsible for navigating to the signed-in home route, same as
  /// every other auth entry point.
  final void Function(AuthResult result) onAccepted;

  @override
  State<AcceptInviteScreen> createState() => _AcceptInviteScreenState();
}

class _AcceptInviteScreenState extends State<AcceptInviteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _linkOrTokenController = TextEditingController();
  final _uidController = TextEditingController();
  final _newPasswordController = TextEditingController();

  _ScreenState _state = _ScreenState.idle;
  String? _errorMessage;

  @override
  void dispose() {
    _linkOrTokenController.dispose();
    _uidController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  /// Accepts either the full pasted link (extracts `token`/`uid` query
  /// params) or a bare token typed alongside the separate uid field below --
  /// whichever the invitee has to hand.
  (String? token, String? uid) _parseLinkOrToken(String input) {
    final trimmed = input.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.queryParameters.containsKey('token')) {
      return (uri.queryParameters['token'], uri.queryParameters['uid']);
    }
    return (trimmed.isEmpty ? null : trimmed, null);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final (parsedToken, parsedUid) =
        _parseLinkOrToken(_linkOrTokenController.text);
    final uid = parsedUid ?? _uidController.text.trim();
    final token = parsedToken ?? '';

    if (uid.isEmpty || token.isEmpty) {
      setState(() {
        _state = _ScreenState.error;
        _errorMessage =
            'Paste the full invite link, or enter both the invite code and your account ID from the email.';
      });
      return;
    }

    setState(() {
      _state = _ScreenState.submitting;
      _errorMessage = null;
    });
    try {
      final result = await widget.repository.acceptInvite(
        userId: uid,
        inviteToken: token,
        newPassword: _newPasswordController.text,
      );
      if (!mounted) return;
      setState(() => _state = _ScreenState.success);
      widget.onAccepted(result);
    } catch (e) {
      final message = e is AuthException
          ? e.message
          : 'Something went wrong. Please try again.';
      setState(() {
        if (message == 'offline') {
          _state = _ScreenState.offline;
          _errorMessage =
              "You're offline. Check your connection and try again.";
        } else {
          _state = _ScreenState.error;
          _errorMessage = message;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final submitting = _state == _ScreenState.submitting;
    // The uid field is only needed when the invitee types a bare token
    // (rather than pasting the full link, which already carries uid).
    final needsManualUid = Uri.tryParse(_linkOrTokenController.text.trim())
            ?.queryParameters['uid'] ==
        null;

    return Scaffold(
      appBar: AppBar(title: const Text('Accept your invite')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (_state == _ScreenState.offline) ...[
              _InlineBanner(
                message: _errorMessage ??
                    "You're offline. Check your connection and try again.",
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (_state == _ScreenState.error && _errorMessage != null) ...[
              _InlineBanner(message: _errorMessage!),
              const SizedBox(height: AppSpacing.sm),
            ],
            const Text(
              'Paste the invite link from your email, then choose a password.',
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _linkOrTokenController,
              decoration: const InputDecoration(
                labelText: 'Invite link or code',
                hintText: 'https://... or the code from your email',
              ),
              enabled: !submitting,
              onChanged: (_) => setState(() {}),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Enter your invite link or code'
                  : null,
            ),
            if (needsManualUid) ...[
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _uidController,
                decoration: const InputDecoration(
                    labelText: 'Account ID (from the email)'),
                enabled: !submitting,
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _newPasswordController,
              decoration: const InputDecoration(labelText: 'Choose a password'),
              obscureText: true,
              enabled: !submitting,
              validator: (v) => (v == null || v.length < 8)
                  ? 'Password must be at least 8 characters'
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(
              onPressed: submitting ? null : _submit,
              child: submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Set password & sign in'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineBanner extends StatelessWidget {
  const _InlineBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline,
              color: Theme.of(context).colorScheme.error, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
