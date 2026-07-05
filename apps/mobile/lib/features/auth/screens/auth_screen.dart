/// screens.md Screen 1: Sign-Up / Login -- single screen with a Sign Up /
/// Log In tab toggle, email-or-phone identifier, and all documented states
/// (Default, Submitting, Validation Error, Auth Error, OTP Expired, Offline).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../data/auth_repository.dart';

enum _ScreenState { idle, submitting, otpSent, error, offline }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.repository, this.initialTabIndex = 0});

  final AuthRepository repository;
  /// 0 = Sign Up tab, 1 = Log In tab -- lets /auth/signup and /auth/login
  /// deep-link into the right tab of this single combined screen.
  final int initialTabIndex;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _usePhone = false;
  bool _otpRequested = false;

  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();

  _ScreenState _state = _ScreenState.idle;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _otpRequested = false;
          _state = _ScreenState.idle;
          _errorMessage = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  bool get _isSignUpTab => _tabController.index == 0;

  void _togglePhone() {
    setState(() {
      _usePhone = !_usePhone;
      _otpRequested = false;
      _state = _ScreenState.idle;
      _errorMessage = null;
      // Clear the other identifier field to avoid submitting mixed state
      // (screens.md Screen 1 edge case).
      if (_usePhone) {
        _emailController.clear();
        _passwordController.clear();
      } else {
        _phoneController.clear();
        _otpController.clear();
      }
    });
  }

  void _handleAuthException(Object error) {
    final message = error is AuthException ? error.message : 'Something went wrong. Please try again.';
    setState(() {
      if (message == 'offline') {
        _state = _ScreenState.offline;
        _errorMessage = "You're offline. Check your connection and try again.";
      } else if (message == 'otp_expired') {
        _state = _ScreenState.error;
        _errorMessage = 'That code has expired.';
      } else {
        _state = _ScreenState.error;
        _errorMessage = message;
      }
    });
  }

  void _onRoleRouted(AuthResult result) {
    // TODO(FEAT-003, P1, not yet built): route through Role Selection for
    // new sign-ups. Until that screen exists, every successful auth lands
    // on Home -- returning users with an existing role/verification status
    // will still reach the right destination once Home's own routing
    // logic (host/agency dashboard vs seeker feed) is implemented there.
    if (!mounted) return;
    context.go('/home');
  }

  Future<void> _submitEmailSignUp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _state = _ScreenState.submitting;
      _errorMessage = null;
    });
    try {
      final result = await widget.repository.registerWithEmail(
        fullName: _fullNameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      _onRoleRouted(result);
    } catch (e) {
      _handleAuthException(e);
    }
  }

  Future<void> _submitPhoneSignUpRequestOtp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _state = _ScreenState.submitting;
      _errorMessage = null;
    });
    try {
      await widget.repository.requestPhoneSignupOtp(
        fullName: _fullNameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
      );
      setState(() {
        _otpRequested = true;
        _state = _ScreenState.otpSent;
      });
    } catch (e) {
      _handleAuthException(e);
    }
  }

  Future<void> _submitPhoneSignUpVerifyOtp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _state = _ScreenState.submitting;
      _errorMessage = null;
    });
    try {
      final result = await widget.repository.verifyPhoneSignupOtp(
        phoneNumber: _phoneController.text.trim(),
        otpCode: _otpController.text.trim(),
      );
      _onRoleRouted(result);
    } catch (e) {
      _handleAuthException(e);
    }
  }

  Future<void> _submitEmailLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _state = _ScreenState.submitting;
      _errorMessage = null;
    });
    try {
      final result = await widget.repository.loginWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      _onRoleRouted(result);
    } catch (e) {
      _handleAuthException(e);
    }
  }

  Future<void> _submitPhoneLoginRequestOtp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _state = _ScreenState.submitting;
      _errorMessage = null;
    });
    try {
      await widget.repository.requestLoginOtp(phoneNumber: _phoneController.text.trim());
      setState(() {
        _otpRequested = true;
        _state = _ScreenState.otpSent;
      });
    } catch (e) {
      _handleAuthException(e);
    }
  }

  Future<void> _submitPhoneLoginVerifyOtp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _state = _ScreenState.submitting;
      _errorMessage = null;
    });
    try {
      final result = await widget.repository.loginWithPhoneOtp(
        phoneNumber: _phoneController.text.trim(),
        otpCode: _otpController.text.trim(),
      );
      _onRoleRouted(result);
    } catch (e) {
      _handleAuthException(e);
    }
  }

  void _handlePrimaryAction() {
    if (_isSignUpTab) {
      if (_usePhone) {
        _otpRequested ? _submitPhoneSignUpVerifyOtp() : _submitPhoneSignUpRequestOtp();
      } else {
        _submitEmailSignUp();
      }
    } else {
      if (_usePhone) {
        _otpRequested ? _submitPhoneLoginVerifyOtp() : _submitPhoneLoginRequestOtp();
      } else {
        _submitEmailLogin();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final submitting = _state == _ScreenState.submitting;

    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              const SizedBox(height: AppSpacing.xl),
              Text('De-Duke', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Verified property. Real conversations. Deals that close.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              TabBar(
                controller: _tabController,
                tabs: const [Tab(text: 'Sign Up'), Tab(text: 'Log In')],
              ),
              const SizedBox(height: AppSpacing.lg),

              if (_state == _ScreenState.offline)
                _Banner(
                  icon: Icons.wifi_off,
                  message: _errorMessage ?? "You're offline. Check your connection and try again.",
                ),
              if (_state == _ScreenState.error && _errorMessage != null)
                _Banner(icon: Icons.error_outline, message: _errorMessage!),
              if (_state == _ScreenState.otpSent && _otpRequested)
                _Banner(
                  icon: Icons.sms_outlined,
                  message: 'Enter the code we sent to ${_phoneController.text.trim()}.',
                  isInfo: true,
                ),

              if (_isSignUpTab)
                TextFormField(
                  controller: _fullNameController,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  enabled: !submitting,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your full name' : null,
                ),
              if (_isSignUpTab) const SizedBox(height: AppSpacing.sm),

              if (!_usePhone)
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  enabled: !submitting,
                  validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                )
              else
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(labelText: 'Phone number'),
                  keyboardType: TextInputType.phone,
                  enabled: !submitting && !_otpRequested,
                  validator: (v) =>
                      (v == null || v.trim().length < 8) ? 'Enter a valid phone number' : null,
                ),
              const SizedBox(height: AppSpacing.sm),

              if (!_usePhone)
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                  enabled: !submitting,
                  validator: (v) =>
                      (v == null || v.length < 8) ? 'Password must be at least 8 characters' : null,
                ),
              if (_usePhone && _otpRequested)
                TextFormField(
                  controller: _otpController,
                  decoration: const InputDecoration(labelText: 'Verification code'),
                  keyboardType: TextInputType.number,
                  enabled: !submitting,
                  validator: (v) =>
                      (v == null || v.trim().length < 4) ? 'Enter the code you received' : null,
                ),
              const SizedBox(height: AppSpacing.md),

              ElevatedButton(
                onPressed: submitting ? null : _handlePrimaryAction,
                child: submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_primaryButtonLabel()),
              ),
              const SizedBox(height: AppSpacing.sm),

              TextButton(
                onPressed: submitting ? null : _togglePhone,
                child: Text(_usePhone ? 'Use email instead' : 'Use phone number instead'),
              ),

              if (!_isSignUpTab)
                TextButton(
                  onPressed: submitting ? null : () => context.push('/auth/forgot-password'),
                  child: const Text('Forgot password?'),
                ),

              const SizedBox(height: AppSpacing.lg),
              Text(
                'By continuing you agree to our Terms of Service and Privacy Policy.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _primaryButtonLabel() {
    if (_usePhone && _otpRequested) return 'Verify code';
    if (_usePhone) return 'Send code';
    return _isSignUpTab ? 'Create account' : 'Log in';
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.message, this.isInfo = false});

  final IconData icon;
  final String message;
  final bool isInfo;

  @override
  Widget build(BuildContext context) {
    final color = isInfo ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
