/// screens.md Screen 1: Sign-Up / Login (Google / Firebase) -- redesigned
/// per the product owner's explicit "make this beautiful" request. Full-
/// bleed gradient hero (wordmark lockup + tagline -- the onboarding-tier
/// illustration originally specced above the wordmark was removed per
/// later product feedback, kept simpler) with a floating, overlapping
/// card underneath holding: "Continue with Google" (the single most
/// prominent action, unaffected by Sign Up / Sign In mode -- Google
/// resolves new-vs-returning identity itself), a divider, an explicit
/// Sign Up / Sign In mode toggle, a Phone/Email method toggle, that
/// method's fields, and a mode-aware Continue button. Implements every
/// documented state: Default, Google Sign-In In Progress, Phone: Entering
/// Number, Phone: OTP Sent, OTP Expired, Email: Entering Details,
/// Submitting, Validation Error, Auth Error, Account Deactivated, Offline.
///
/// Sign Up vs. Sign In is an explicit, user-picked mode (not inferred by
/// "try login, fall back to create") for Email; a mismatched pick on
/// Phone (e.g. Sign In tapped for a brand-new number) is caught after
/// the fact by AuthRepository's `_enforcePhoneIntent`, since Firebase's
/// OTP flow has no separate create/sign-in step to gate up front. Google
/// keeps its original single-tap, mode-agnostic behavior throughout.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/badge_pop.dart';
import '../../../core/widgets/de_duke_logo.dart';
import '../../../core/widgets/tap_scale.dart';
import '../data/auth_repository.dart';

enum _Method { email, phone }

/// Explicit Sign Up / Sign In intent, user-picked via `_ModeToggle` --
/// replaces the old implicit "try login, create on failure" behavior for
/// Email, and is enforced after the fact for Phone (see this file's
/// module docstring and AuthRepository's `_enforcePhoneIntent`).
enum _Mode { signUp, signIn }

enum _Phase {
  idle,
  submitting,
  googleInProgress,
  error,
  offline,
  accountDeactivated,
}

const _resendCooldownSeconds = 30;

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.repository});

  final AuthRepository repository;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  _Method _method = _Method.email;
  // Sign In is the more common return-visit case, so it's the default;
  // a brand-new user just taps the Sign Up segment before entering
  // anything (screens.md Screen 1 Modernization Notes).
  _Mode _mode = _Mode.signIn;
  _Phase _phase = _Phase.idle;
  String? _errorMessage;

  bool _otpSent = false;
  String? _verificationId;
  Timer? _resendTimer;
  int _resendSecondsLeft = 0;

  /// screens.md Screen 1 Modernization Notes: hero illustration/wordmark
  /// fades/settles in at `duration-slow` on first paint.
  double _heroOpacity = 0;

  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _heroOpacity = 1);
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  bool get _submitting =>
      _phase == _Phase.submitting || _phase == _Phase.googleInProgress;

  /// +234-prefixed per the Phone field component spec -- accepts either a
  /// bare local number (leading 0 stripped) or one already typed with a
  /// country code.
  String get _fullPhoneNumber {
    final raw = _phoneController.text.trim();
    if (raw.startsWith('+')) return raw;
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final normalized = digits.startsWith('0') ? digits.substring(1) : digits;
    return '+234$normalized';
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _resendSecondsLeft = _resendCooldownSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendSecondsLeft -= 1;
        if (_resendSecondsLeft <= 0) timer.cancel();
      });
    });
  }

  /// FEAT-003 (Role Selection): user_flow.md Flow 2 -- "On success, new
  /// users navigate to Role Selection; returning users navigate to Home
  /// Feed." `result.isNewUser` is the field the backend actually threads
  /// through for this (see AuthResult's docstring on why `role` alone
  /// can't be trusted for this decision).
  void _onAuthSuccess(AuthResult result) {
    if (!mounted) return;
    context.goNamed(result.isNewUser ? RouteNames.authRole : RouteNames.home);
  }

  void _handleAuthException(Object error) {
    if (!mounted) return;
    final message = error is AuthException
        ? error.message
        : 'Something went wrong. Please try again.';
    final deactivated = error is AuthException && error.isAccountDeactivated;
    setState(() {
      if (deactivated) {
        _phase = _Phase.accountDeactivated;
        _errorMessage = message;
      } else if (message == 'offline') {
        _phase = _Phase.offline;
        _errorMessage = "You're offline. Check your connection and try again.";
      } else {
        _phase = _Phase.error;
        _errorMessage = message;
      }
    });
  }

  Future<void> _run(Future<AuthResult> Function() action) async {
    setState(() {
      _phase = _Phase.submitting;
      _errorMessage = null;
    });
    try {
      _onAuthSuccess(await action());
    } catch (e) {
      _handleAuthException(e);
    }
  }

  Future<void> _handleGoogle() async {
    setState(() {
      _phase = _Phase.googleInProgress;
      _errorMessage = null;
    });
    try {
      _onAuthSuccess(await widget.repository.signInWithGoogle());
      return;
    } catch (e) {
      if (e is AuthException && e.message == 'cancelled') {
        if (mounted) setState(() => _phase = _Phase.idle);
        return;
      }
      // screens.md Edge Case: Google Sign-In can succeed at the Firebase
      // layer while the backend exchange fails -- retry the exchange
      // once, automatically, without re-prompting the account picker,
      // before falling back to a normal Auth Error state.
      try {
        final retried = await widget.repository.retryPendingExchange();
        if (retried != null) {
          _onAuthSuccess(retried);
          return;
        }
      } catch (retryError) {
        _handleAuthException(retryError);
        return;
      }
      _handleAuthException(e);
    }
  }

  Future<void> _handleEmailContinue() async {
    if (!_formKey.currentState!.validate()) return;
    await _run(() => _mode == _Mode.signUp
        ? widget.repository.registerWithEmail(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            fullName: _fullNameController.text.trim(),
          )
        : widget.repository.signInWithEmail(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          ));
  }

  // Phone/OTP has no Sign Up/Sign In toggle of its own (the mode toggle is
  // Email-only, per this screen's Modernization Notes) -- Firebase's phone
  // verification flow is inherently unified anyway (see AuthRepository's
  // module docstring), so it's left to behave as it always did: verifying
  // a code resolves to a session, new or existing, without the user
  // picking an explicit intent first.
  Future<void> _handlePhoneContinue() async {
    if (!_formKey.currentState!.validate()) return;
    if (_otpSent) {
      await _run(() => widget.repository.verifyPhoneCode(
            verificationId: _verificationId!,
            smsCode: _otpController.text.trim(),
          ));
      return;
    }
    setState(() {
      _phase = _Phase.submitting;
      _errorMessage = null;
    });
    await widget.repository.requestPhoneCode(
      phoneNumber: _fullPhoneNumber,
      onCodeSent: (verificationId) {
        if (!mounted) return;
        _verificationId = verificationId;
        setState(() {
          _otpSent = true;
          _phase = _Phase.idle;
        });
        _startResendCountdown();
      },
      onAutoVerified: _onAuthSuccess,
      onFailed: _handleAuthException,
    );
  }

  Future<void> _handleForgotPassword() async {
    if (_emailController.text.trim().isEmpty ||
        !_emailController.text.contains('@')) {
      setState(() {
        _phase = _Phase.error;
        _errorMessage =
            'Enter your email above first, then tap "Forgot password?" again.';
      });
      return;
    }
    try {
      await widget.repository
          .sendFirebasePasswordResetEmail(_emailController.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'If an account exists for ${_emailController.text.trim()}, a reset link is on its way.')),
      );
    } catch (e) {
      _handleAuthException(e);
    }
  }

  void _switchMethod(_Method method) {
    if (_method == method) return;
    setState(() {
      _method = method;
      _phase = _Phase.idle;
      _errorMessage = null;
      _otpSent = false;
      _verificationId = null;
      _resendTimer?.cancel();
      // Clear the other method's fields to avoid submitting mixed state
      // (screens.md Screen 1 Edge Case).
      if (method == _Method.email) {
        _phoneController.clear();
        _otpController.clear();
      } else {
        _fullNameController.clear();
        _emailController.clear();
        _passwordController.clear();
      }
    });
  }

  void _switchMode(_Mode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _phase = _Phase.idle;
      _errorMessage = null;
      if (mode == _Mode.signIn) _fullNameController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
      body: SafeArea(
        top: false,
        bottom: false,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HeroSection(opacity: _heroOpacity, isDark: isDark),
                Transform.translate(
                  offset: const Offset(0, -AppSpacing.lg),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: _AuthCard(
                      isDark: isDark,
                      phase: _phase,
                      errorMessage: _errorMessage,
                      mode: _mode,
                      method: _method,
                      otpSent: _otpSent,
                      submitting: _submitting,
                      resendSecondsLeft: _resendSecondsLeft,
                      fullNameController: _fullNameController,
                      emailController: _emailController,
                      passwordController: _passwordController,
                      phoneController: _phoneController,
                      otpController: _otpController,
                      onGoogle: _submitting ? null : _handleGoogle,
                      onSwitchMode: _submitting ? null : _switchMode,
                      onSwitchMethod: _submitting ? null : _switchMethod,
                      onContinue: _submitting
                          ? null
                          : (_method == _Method.email
                              ? _handleEmailContinue
                              : _handlePhoneContinue),
                      onResend: (_resendSecondsLeft > 0 || _submitting)
                          ? null
                          : _handlePhoneContinue,
                      onForgotPassword:
                          _submitting ? null : _handleForgotPassword,
                      onHaveInviteLink: _submitting
                          ? null
                          : () =>
                              context.pushNamed(RouteNames.authAcceptInvite),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                      AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
                  child: Text(
                    'By continuing you agree to our Terms of Service and Privacy Policy.',
                    style: AppTypography.bodySmall.copyWith(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-bleed `surface` -> `primary-light` gradient at ~135° (branding.md
/// Hero/Featured Card formula, scaled to this screen's most prominent
/// placement), holding the onboarding-tier illustration + wordmark
/// lockup + tagline.
class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.opacity, required this.isDark});

  final double opacity;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.xxl, AppSpacing.lg, AppSpacing.xxl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [AppColors.surfaceDark, AppColors.primaryLightDark]
              : [AppColors.surface, AppColors.primaryLight],
        ),
      ),
      child: AnimatedOpacity(
        opacity: opacity,
        duration: AppDurations.slow,
        curve: AppCurves.easeOutSmooth,
        child: Column(
          children: [
            const DeDukeLogoLockup(markSize: 44),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Verified property. Real conversations. Deals that close.',
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one deliberately "premium" element on this screen (per branding.md's
/// "exactly one element per screen is allowed to feel more elevated"
/// principle) -- floating card, `shadow-lg`, overlapping the hero's bottom
/// edge.
class _AuthCard extends StatelessWidget {
  const _AuthCard({
    required this.isDark,
    required this.phase,
    required this.errorMessage,
    required this.mode,
    required this.method,
    required this.otpSent,
    required this.submitting,
    required this.resendSecondsLeft,
    required this.fullNameController,
    required this.emailController,
    required this.passwordController,
    required this.phoneController,
    required this.otpController,
    required this.onGoogle,
    required this.onSwitchMode,
    required this.onSwitchMethod,
    required this.onContinue,
    required this.onResend,
    required this.onForgotPassword,
    required this.onHaveInviteLink,
  });

  final bool isDark;
  final _Phase phase;
  final String? errorMessage;
  final _Mode mode;
  final _Method method;
  final bool otpSent;
  final bool submitting;
  final int resendSecondsLeft;
  final TextEditingController fullNameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController phoneController;
  final TextEditingController otpController;
  final VoidCallback? onGoogle;
  final void Function(_Mode)? onSwitchMode;
  final void Function(_Method)? onSwitchMethod;
  final VoidCallback? onContinue;
  final VoidCallback? onResend;
  final VoidCallback? onForgotPassword;
  final VoidCallback? onHaveInviteLink;

  @override
  Widget build(BuildContext context) {
    final borderColor = (isDark ? AppColors.borderDark : AppColors.border)
        .withValues(alpha: 0.6);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: borderColor),
        boxShadow: AppShadows.of(AppShadows.lg, AppShadows.lgDark, isDark),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (phase == _Phase.offline)
            _Banner(
              icon: Icons.wifi_off,
              message: errorMessage ??
                  "You're offline. Check your connection and try again.",
              isDark: isDark,
            ),
          if (phase == _Phase.error && errorMessage != null)
            _Banner(
                icon: Icons.error_outline,
                message: errorMessage!,
                isDark: isDark),
          if (phase == _Phase.accountDeactivated && errorMessage != null)
            _Banner(
              icon: Icons.block,
              message: errorMessage!,
              isDark: isDark,
              retryable: false,
            ),
          // -- "Continue with Google" -- first and most prominent action,
          // ahead of the Phone/Email method toggle. Mode-agnostic: Google
          // OAuth resolves new-vs-returning identity on its own, so there's
          // no Sign Up/Sign In toggle above it (see this file's module
          // docstring).
          TapScale(
            emphasis: true,
            onTap: onGoogle,
            child: OutlinedButton.icon(
              onPressed: onGoogle,
              icon: phase == _Phase.googleInProgress
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const _GoogleGlyph(),
              label: const Text('Continue with Google'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _DividerRow(isDark: isDark),
          const SizedBox(height: AppSpacing.md),
          _MethodToggle(
              method: method, isDark: isDark, onSwitch: onSwitchMethod),
          const SizedBox(height: AppSpacing.md),
          // AnimatedSwitcher alone only crossfades -- the surrounding
          // Column still jumps straight to the new child's height the
          // instant it swaps (e.g. Email's Sign Up fields -> Phone's single
          // field), which is exactly the visible "jump" this wrapping
          // AnimatedSize fixes: it animates the height change over the same
          // duration/curve as the fade, so the card smoothly grows/shrinks
          // instead of snapping.
          AnimatedSize(
            duration: AppDurations.normal,
            curve: AppCurves.easeOutSmooth,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: AppDurations.normal,
              switchInCurve: AppCurves.easeOutSmooth,
              child: method == _Method.email
                  ? Column(
                      key: const ValueKey('email'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Sign Up / Sign In is Email-only -- Phone/OTP has
                        // no separate create-vs-sign-in primitive to gate
                        // on (see AuthRepository's module docstring), so
                        // this toggle is hidden entirely when Phone is
                        // selected rather than shown-but-inert.
                        _ModeToggle(
                            mode: mode, isDark: isDark, onSwitch: onSwitchMode),
                        const SizedBox(height: AppSpacing.md),
                        _EmailFields(
                          mode: mode,
                          fullNameController: fullNameController,
                          emailController: emailController,
                          passwordController: passwordController,
                          enabled: !submitting,
                          // Resetting a password only makes sense for an
                          // account that already exists -- hidden entirely
                          // in Sign Up mode rather than offered against an
                          // email that may not even have an account yet.
                          showForgotPassword: mode == _Mode.signIn,
                          onForgotPassword: onForgotPassword,
                        ),
                      ],
                    )
                  : _PhoneFields(
                      key: ValueKey('phone-$otpSent'),
                      phoneController: phoneController,
                      otpController: otpController,
                      otpSent: otpSent,
                      enabled: !submitting,
                      resendSecondsLeft: resendSecondsLeft,
                      onResend: onResend,
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TapScale(
            emphasis: true,
            onTap: onContinue,
            child: ElevatedButton(
              onPressed: onContinue,
              child: submitting && phase != _Phase.googleInProgress
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(_continueLabel()),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: TapScale(
              onTap: onHaveInviteLink,
              child: TextButton(
                onPressed: onHaveInviteLink,
                child: const Text('Have an invite link?'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _continueLabel() {
    if (method == _Method.phone) {
      // Firebase's OTP flow has no separate "create" step of its own to
      // label distinctly (see this file's module docstring) -- the
      // Send/Verify code labels stay the same regardless of mode.
      return otpSent ? 'Verify code' : 'Send code';
    }
    return mode == _Mode.signUp ? 'Create account' : 'Sign in';
  }
}

/// Explicit Sign Up / Sign In intent selector -- the primary toggle this
/// screen's redesign added (see module docstring): everything below it,
/// including "Continue with Google," reflects this choice, except Google
/// itself doesn't need to branch on it (OAuth resolves new-vs-returning
/// identity on its own).
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.isDark, this.onSwitch});

  final _Mode mode;
  final bool isDark;
  final void Function(_Mode)? onSwitch;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_Mode>(
      segments: const [
        ButtonSegment(value: _Mode.signIn, label: Text('Sign In')),
        ButtonSegment(value: _Mode.signUp, label: Text('Sign Up')),
      ],
      selected: {mode},
      onSelectionChanged:
          onSwitch == null ? null : (selection) => onSwitch!(selection.first),
      showSelectedIcon: false,
    );
  }
}

class _DividerRow extends StatelessWidget {
  const _DividerRow({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final color = isDark ? AppColors.borderDark : AppColors.border;
    return Row(
      children: [
        Expanded(child: Divider(color: color)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Text(
            'or',
            style: AppTypography.caption.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(child: Divider(color: color)),
      ],
    );
  }
}

class _MethodToggle extends StatelessWidget {
  const _MethodToggle(
      {required this.method, required this.isDark, this.onSwitch});

  final _Method method;
  final bool isDark;
  final void Function(_Method)? onSwitch;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_Method>(
      segments: const [
        ButtonSegment(
            value: _Method.phone,
            icon: Icon(Icons.phone_outlined),
            label: Text('Phone')),
        ButtonSegment(
            value: _Method.email,
            icon: Icon(Icons.mail_outline),
            label: Text('Email')),
      ],
      selected: {method},
      onSelectionChanged:
          onSwitch == null ? null : (selection) => onSwitch!(selection.first),
      showSelectedIcon: false,
    );
  }
}

class _EmailFields extends StatelessWidget {
  const _EmailFields({
    required this.mode,
    required this.fullNameController,
    required this.emailController,
    required this.passwordController,
    required this.enabled,
    this.showForgotPassword = true,
    this.onForgotPassword,
  });

  final _Mode mode;
  final TextEditingController fullNameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool enabled;
  final bool showForgotPassword;
  final VoidCallback? onForgotPassword;

  bool get _isSignUp => mode == _Mode.signUp;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Only Sign Up needs a name to introduce a brand-new account with
        // -- Sign In resolves an existing account, whose name is already
        // on file.
        if (_isSignUp) ...[
          TextFormField(
            controller: fullNameController,
            decoration: const InputDecoration(labelText: 'Full name'),
            textCapitalization: TextCapitalization.words,
            enabled: enabled,
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Enter your full name'
                : null,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        TextFormField(
          controller: emailController,
          decoration: const InputDecoration(labelText: 'Email'),
          keyboardType: TextInputType.emailAddress,
          enabled: enabled,
          validator: (v) =>
              (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: passwordController,
          decoration: const InputDecoration(labelText: 'Password'),
          obscureText: true,
          enabled: enabled,
          validator: (v) => (v == null || v.length < 6)
              ? 'Password must be at least 6 characters'
              : null,
        ),
        if (showForgotPassword)
          Align(
            alignment: Alignment.centerRight,
            child: TapScale(
              onTap: onForgotPassword,
              child: TextButton(
                onPressed: onForgotPassword,
                child: const Text('Forgot password?'),
              ),
            ),
          ),
      ],
    );
  }
}

class _PhoneFields extends StatelessWidget {
  const _PhoneFields({
    super.key,
    required this.phoneController,
    required this.otpController,
    required this.otpSent,
    required this.enabled,
    required this.resendSecondsLeft,
    this.onResend,
  });

  final TextEditingController phoneController;
  final TextEditingController otpController;
  final bool otpSent;
  final bool enabled;
  final int resendSecondsLeft;
  final VoidCallback? onResend;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextFormField(
          controller: phoneController,
          decoration: const InputDecoration(
            labelText: 'Phone number',
            prefixText: '+234 ',
          ),
          keyboardType: TextInputType.phone,
          enabled: enabled && !otpSent,
          validator: (v) => (v == null || v.trim().length < 7)
              ? 'Enter a valid phone number'
              : null,
        ),
        if (otpSent) ...[
          const SizedBox(height: AppSpacing.sm),
          BadgePop(
            triggerKey: 'otp-entry',
            child: TextFormField(
              controller: otpController,
              decoration: const InputDecoration(labelText: 'Verification code'),
              keyboardType: TextInputType.number,
              enabled: enabled,
              maxLength: 6,
              validator: (v) => (v == null || v.trim().length < 4)
                  ? 'Enter the code you received'
                  : null,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TapScale(
              onTap: onResend,
              child: TextButton(
                onPressed: onResend,
                child: Text(resendSecondsLeft > 0
                    ? 'Resend code in ${resendSecondsLeft}s'
                    : 'Resend code'),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.message,
    required this.isDark,
    this.retryable = true,
  });

  final IconData icon;
  final String message;
  final bool isDark;
  final bool retryable;

  @override
  Widget build(BuildContext context) {
    final color = retryable
        ? AppColors.error
        : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondary);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: AppSizing.iconMd),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySmall.copyWith(
                color:
                    isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Simplified Google "G" glyph -- no bundled Google logo asset exists in
/// this project yet (`assets/images/` only ships the De-Duke mark), so this
/// renders Google's 4-color ring + crossbar directly rather than pulling in
/// a new asset/package for one icon.
class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph({this.size = 18});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _GoogleGPainter()));
  }
}

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final strokeWidth = size.width * 0.24;
    final rect = Rect.fromCircle(
        center: center, radius: size.width / 2 - strokeWidth / 2);

    void arc(double startDeg, double sweepDeg, Color color) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawArc(rect, startDeg * math.pi / 180, sweepDeg * math.pi / 180,
          false, paint);
    }

    arc(-100, 80, const Color(0xFF4285F4));
    arc(-10, 80, const Color(0xFF34A853));
    arc(80, 80, const Color(0xFFFBBC05));
    arc(170, 80, const Color(0xFFEA4335));

    final barPaint = Paint()..color = const Color(0xFF4285F4);
    canvas.drawRect(
      Rect.fromLTWH(
        center.dx - strokeWidth * 0.1,
        center.dy - strokeWidth / 2,
        size.width / 2 - strokeWidth * 0.4,
        strokeWidth,
      ),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GoogleGPainter oldDelegate) => false;
}
