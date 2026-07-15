/// screens.md Screen 21's "Link a sign-in method" bottom sheet (FEAT-040).
/// Same three methods as Screen 1 (Google, Phone/OTP, Email/Password), but
/// each one attaches the result to the CALLER'S EXISTING session
/// (AuthRepository's `linking: true` variants) rather than starting a new
/// one. Deliberately its own lightweight sheet rather than reusing the
/// full AuthScreen widget -- this is a much smaller surface (no hero, no
/// "Have an invite link?", no offline/account-deactivated states, since
/// the caller is already a fully signed-in user).
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../auth/data/auth_repository.dart';

/// Shows the sheet and returns `true` if a link attempt succeeded (caller
/// should refresh its profile), `false`/`null` otherwise (cancelled or
/// the sheet was dismissed without a successful link).
Future<bool?> showLinkSignInSheet(
  BuildContext context, {
  required AuthRepository repository,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _LinkSignInSheet(repository: repository),
  );
}

enum _Method { picker, phoneNumber, phoneOtp, email }

class _LinkSignInSheet extends StatefulWidget {
  const _LinkSignInSheet({required this.repository});
  final AuthRepository repository;

  @override
  State<_LinkSignInSheet> createState() => _LinkSignInSheetState();
}

class _LinkSignInSheetState extends State<_LinkSignInSheet> {
  _Method _method = _Method.picker;
  bool _submitting = false;
  String? _error;
  String? _verificationId;

  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String get _fullPhoneNumber {
    final raw = _phoneController.text.trim();
    if (raw.startsWith('+')) return raw;
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final normalized = digits.startsWith('0') ? digits.substring(1) : digits;
    return '+234$normalized';
  }

  void _handleResult(AuthResult result) {
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  void _handleError(Object error) {
    if (!mounted) return;
    final message =
        error is AuthException ? error.message : 'Something went wrong.';
    setState(() {
      _submitting = false;
      // A cancelled Google picker just returns to the method choices,
      // same non-error treatment as Screen 1's identical edge case.
      if (message == 'cancelled') {
        _method = _Method.picker;
        _error = null;
      } else {
        _error = message == 'offline'
            ? "You're offline. Check your connection and try again."
            : message;
      }
    });
  }

  Future<void> _linkGoogle() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      _handleResult(await widget.repository.linkGoogleIdentity());
    } catch (e) {
      _handleError(e);
    }
  }

  Future<void> _sendPhoneCode() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    await widget.repository.requestPhoneCode(
      phoneNumber: _fullPhoneNumber,
      linking: true,
      onCodeSent: (verificationId) {
        if (!mounted) return;
        setState(() {
          _verificationId = verificationId;
          _method = _Method.phoneOtp;
          _submitting = false;
        });
      },
      onAutoVerified: _handleResult,
      onFailed: _handleError,
    );
  }

  Future<void> _verifyPhoneCode() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      _handleResult(await widget.repository.verifyPhoneCode(
        verificationId: _verificationId!,
        smsCode: _otpController.text.trim(),
        linking: true,
      ));
    } catch (e) {
      _handleError(e);
    }
  }

  Future<void> _linkEmail() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      _handleResult(await widget.repository.linkEmailIdentity(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      ));
    } catch (e) {
      _handleError(e);
    }
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
          Text('Link a sign-in method',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (_method == _Method.picker) ..._buildPicker(),
          if (_method == _Method.phoneNumber) ..._buildPhoneNumber(),
          if (_method == _Method.phoneOtp) ..._buildPhoneOtp(),
          if (_method == _Method.email) ..._buildEmail(),
        ],
      ),
    );
  }

  List<Widget> _buildPicker() => [
        ElevatedButton.icon(
          onPressed: _submitting ? null : _linkGoogle,
          icon: const Icon(Icons.g_mobiledata),
          label: const Text('Continue with Google'),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: _submitting
              ? null
              : () => setState(() => _method = _Method.phoneNumber),
          icon: const Icon(Icons.phone_outlined),
          label: const Text('Link a phone number'),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: _submitting
              ? null
              : () => setState(() => _method = _Method.email),
          icon: const Icon(Icons.mail_outline),
          label: const Text('Link an email'),
        ),
      ];

  List<Widget> _buildPhoneNumber() => [
        TextField(
          controller: _phoneController,
          decoration: const InputDecoration(
              labelText: 'Phone number', prefixText: '+234 '),
          keyboardType: TextInputType.phone,
          enabled: !_submitting,
        ),
        const SizedBox(height: AppSpacing.sm),
        ElevatedButton(
          onPressed: _submitting ? null : _sendPhoneCode,
          child: _submitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Send code'),
        ),
      ];

  List<Widget> _buildPhoneOtp() => [
        Text('Enter the code sent to ${_phoneController.text.trim()}.'),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _otpController,
          decoration: const InputDecoration(labelText: 'Verification code'),
          keyboardType: TextInputType.number,
          enabled: !_submitting,
        ),
        const SizedBox(height: AppSpacing.sm),
        ElevatedButton(
          onPressed: _submitting ? null : _verifyPhoneCode,
          child: _submitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Verify code'),
        ),
      ];

  List<Widget> _buildEmail() => [
        TextField(
          controller: _emailController,
          decoration: const InputDecoration(labelText: 'Email'),
          keyboardType: TextInputType.emailAddress,
          enabled: !_submitting,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _passwordController,
          decoration: const InputDecoration(labelText: 'Password'),
          obscureText: true,
          enabled: !_submitting,
        ),
        const SizedBox(height: AppSpacing.sm),
        ElevatedButton(
          onPressed: _submitting ? null : _linkEmail,
          child: _submitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Link account'),
        ),
      ];
}
