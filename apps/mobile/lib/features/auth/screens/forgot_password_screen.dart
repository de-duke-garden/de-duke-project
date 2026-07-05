/// Password reset sub-flow, reached from Screen 1's "Forgot password?" link.
/// Not a dedicated screens.md entry (Screen 1 references it only as an exit
/// point), so this is a lightweight two-step flow: request a reset link,
/// then (once the user has a reset_token, e.g. from an emailed link) set a
/// new password.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../data/auth_repository.dart';

enum _Step { requestReset, setNewPassword }

enum _ScreenState { idle, submitting, success, error, offline }

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, required this.repository});

  final AuthRepository repository;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _resetTokenController = TextEditingController();
  final _newPasswordController = TextEditingController();

  _Step _step = _Step.requestReset;
  _ScreenState _state = _ScreenState.idle;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _resetTokenController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _requestReset() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _state = _ScreenState.submitting;
      _errorMessage = null;
    });
    try {
      await widget.repository
          .requestPasswordReset(email: _emailController.text.trim());
      if (!mounted) return;
      setState(() {
        _step = _Step.setNewPassword;
        _state = _ScreenState.idle;
      });
    } catch (e) {
      _handleError(e);
    }
  }

  Future<void> _submitNewPassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _state = _ScreenState.submitting;
      _errorMessage = null;
    });
    try {
      await widget.repository.resetPassword(
        resetToken: _resetTokenController.text.trim(),
        newPassword: _newPasswordController.text,
      );
      if (!mounted) return;
      setState(() => _state = _ScreenState.success);
    } catch (e) {
      _handleError(e);
    }
  }

  void _handleError(Object error) {
    final message = error is AuthException
        ? error.message
        : 'Something went wrong. Please try again.';
    setState(() {
      if (message == 'offline') {
        _state = _ScreenState.offline;
        _errorMessage = "You're offline. Check your connection and try again.";
      } else {
        _state = _ScreenState.error;
        _errorMessage = message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final submitting = _state == _ScreenState.submitting;

    if (_state == _ScreenState.success) {
      return Scaffold(
        appBar: AppBar(title: const Text('Password reset')),
        body: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle_outline, size: 48),
              const SizedBox(height: AppSpacing.md),
              const Text('Your password has been reset. You can now log in.'),
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back to login'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (_state == _ScreenState.offline)
              _InlineBanner(
                  message: _errorMessage ??
                      "You're offline. Check your connection and try again."),
            if (_state == _ScreenState.error && _errorMessage != null)
              _InlineBanner(message: _errorMessage!),
            if (_step == _Step.requestReset) ...[
              const Text(
                  'Enter the email associated with your account. If it exists, we will send you a reset link.'),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                enabled: !submitting,
                validator: (v) => (v == null || !v.contains('@'))
                    ? 'Enter a valid email'
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              ElevatedButton(
                onPressed: submitting ? null : _requestReset,
                child: submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Send reset link'),
              ),
            ] else ...[
              const Text(
                  'Enter the reset code from your email and choose a new password.'),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _resetTokenController,
                decoration: const InputDecoration(labelText: 'Reset code'),
                enabled: !submitting,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter the reset code'
                    : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _newPasswordController,
                decoration: const InputDecoration(labelText: 'New password'),
                obscureText: true,
                enabled: !submitting,
                validator: (v) => (v == null || v.length < 8)
                    ? 'Password must be at least 8 characters'
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              ElevatedButton(
                onPressed: submitting ? null : _submitNewPassword,
                child: submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Reset password'),
              ),
            ],
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
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
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
