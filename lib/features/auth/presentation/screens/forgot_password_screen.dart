import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/router/route_names.dart';
import '../../../../shared/widgets/romantic_background.dart';
import '../../../../shared/widgets/romantic_glass_card.dart';
import '../../../../shared/widgets/soulsync_button.dart';
import '../../../../shared/widgets/soulsync_text_field.dart';
import '../../../../shared/utils/validators.dart';
import '../providers/auth_provider.dart';

enum ForgotPasswordStep { enterEmail, enterOtp, newPassword, completed }

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailFormKey = GlobalKey<FormState>();
  final _pwFormKey = GlobalKey<FormState>();

  final _emailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _newPwCtrl = TextEditingController();
  final _confirmPwCtrl = TextEditingController();

  ForgotPasswordStep _currentStep = ForgotPasswordStep.enterEmail;
  bool _isLoading = false;
  String? _errorMessage;
  String? _statusMessage;
  int _resendCooldown = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _newPwCtrl.dispose();
    _confirmPwCtrl.dispose();
    super.dispose();
  }

  void _startResendCooldown() {
    setState(() => _resendCooldown = 60);
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_resendCooldown > 0) {
        setState(() => _resendCooldown--);
      } else {
        t.cancel();
      }
    });
  }

  void _handleBack() {
    if (_currentStep == ForgotPasswordStep.enterOtp) {
      setState(() {
        _currentStep = ForgotPasswordStep.enterEmail;
        _errorMessage = null;
      });
    } else if (_currentStep == ForgotPasswordStep.newPassword) {
      setState(() {
        _currentStep = ForgotPasswordStep.enterOtp;
        _errorMessage = null;
      });
    } else {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(RouteNames.login);
      }
    }
  }

  // Step 1: Send Reset OTP
  Future<void> _sendResetOtp() async {
    if (!_emailFormKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final email = _emailCtrl.text.trim().toLowerCase();
      await ref.read(authRepositoryProvider).forgotPassword(email);

      setState(() {
        _currentStep = ForgotPasswordStep.enterOtp;
        _statusMessage = 'If an account exists for $email, a 6-digit password reset code has been sent (valid 5 min).';
      });
      _startResendCooldown();
    } catch (e) {
      setState(() => _errorMessage = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Step 2: Verify OTP
  Future<void> _verifyOtp() async {
    final otp = _otpCtrl.text.trim();
    if (otp.length < 6) {
      setState(() => _errorMessage = 'Please enter the complete 6-digit code.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final email = _emailCtrl.text.trim().toLowerCase();
      await ref.read(authRepositoryProvider).verifyResetOtp(email: email, otp: otp);
      setState(() {
        _currentStep = ForgotPasswordStep.newPassword;
        _statusMessage = 'Code verified! Please create your new password.';
      });
    } catch (e) {
      setState(() => _errorMessage = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Step 3: Set New Password
  Future<void> _updatePassword() async {
    if (!_pwFormKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final email = _emailCtrl.text.trim().toLowerCase();
      await ref.read(authRepositoryProvider).resetPassword(
            email: email,
            otp: _otpCtrl.text.trim(),
            newPassword: _newPwCtrl.text,
          );
      setState(() {
        _currentStep = ForgotPasswordStep.completed;
      });
    } catch (e) {
      setState(() => _errorMessage = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 14, top: 8),
          child: Container(
            decoration: BoxDecoration(
              color: context.ssSurface.withValues(alpha: 0.94),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: context.ssPrimary.withValues(alpha: 0.14),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: context.ssPrimary),
              tooltip: 'Back',
              onPressed: _handleBack,
            ),
          ),
        ),
      ),
      body: RomanticBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (_currentStep == ForgotPasswordStep.completed)
                      _buildCompletedView()
                    else ...[
                      // Romantic Icon Header
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppColors.romanticGradient,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.romanticRose.withOpacity(0.35),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.lock_reset_rounded, size: 38, color: Colors.white),
                      ),
                      const SizedBox(height: 20),

                      Text(
                        'Reset Password 🔑',
                        style: AppTypography.displayMedium.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _getStepSubtitle(),
                        style: AppTypography.bodyMedium.copyWith(
                          color: context.ssTextSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),

                      // Glassmorphic Card
                      RomanticGlassCard(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_errorMessage != null) ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.error.withOpacity(0.25)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!,
                                        style: const TextStyle(color: AppColors.error, fontSize: 13, height: 1.3),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            if (_statusMessage != null) ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.mail_outline_rounded, color: AppColors.primary, size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _statusMessage!,
                                        style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                            ],

                            if (_currentStep == ForgotPasswordStep.enterEmail) _buildEmailStep(),
                            if (_currentStep == ForgotPasswordStep.enterOtp) _buildOtpStep(),
                            if (_currentStep == ForgotPasswordStep.newPassword) _buildNewPasswordStep(),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getStepSubtitle() {
    switch (_currentStep) {
      case ForgotPasswordStep.enterEmail:
        return 'Enter your registered email and we\'ll send a 6-digit reset code.';
      case ForgotPasswordStep.enterOtp:
        return 'Check your inbox and enter the 6-digit security code.';
      case ForgotPasswordStep.newPassword:
        return 'Create a strong, secure password matching complexity policy.';
      case ForgotPasswordStep.completed:
        return 'Password reset successful!';
    }
  }

  Widget _buildEmailStep() {
    return Form(
      key: _emailFormKey,
      child: Column(
        children: [
          SoulSyncTextField(
            label: 'Registered Email',
            hint: 'your.email@example.com',
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            prefixIcon: Icons.email_outlined,
            validator: Validators.email,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _sendResetOtp(),
          ),
          const SizedBox(height: 24),
          SoulSyncButton(
            label: 'Send Verification Code 💌',
            onPressed: _sendResetOtp,
            isLoading: _isLoading,
          ),
        ],
      ),
    );
  }

  Widget _buildOtpStep() {
    return Column(
      children: [
        SoulSyncTextField(
          label: '6-Digit Reset Code',
          hint: 'Enter the code from your email',
          controller: _otpCtrl,
          keyboardType: TextInputType.number,
          prefixIcon: Icons.pin_outlined,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _verifyOtp(),
        ),
        const SizedBox(height: 24),
        SoulSyncButton(
          label: 'Verify Code ✨',
          onPressed: _verifyOtp,
          isLoading: _isLoading,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () => setState(() => _currentStep = ForgotPasswordStep.enterEmail),
              child: const Text('Change Email'),
            ),
            TextButton(
              onPressed: (_resendCooldown > 0 || _isLoading) ? null : _sendResetOtp,
              child: Text(_resendCooldown > 0 ? 'Resend (${_resendCooldown}s)' : 'Resend Code'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNewPasswordStep() {
    return Form(
      key: _pwFormKey,
      child: Column(
        children: [
          SoulSyncTextField(
            label: 'New Password',
            hint: 'Min 8 chars, 1 uppercase, 1 number, 1 special',
            controller: _newPwCtrl,
            obscureText: true,
            validator: Validators.password,
            prefixIcon: Icons.lock_outline_rounded,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          SoulSyncTextField(
            label: 'Confirm New Password',
            hint: 'Re-enter your new password',
            controller: _confirmPwCtrl,
            obscureText: true,
            validator: (v) => Validators.confirmPassword(v, _newPwCtrl.text),
            prefixIcon: Icons.lock_clock_outlined,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _updatePassword(),
          ),
          const SizedBox(height: 24),
          SoulSyncButton(
            label: 'Update Password & Finish 💞',
            onPressed: _updatePassword,
            isLoading: _isLoading,
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedView() {
    return RomanticGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded, size: 52, color: AppColors.success),
          ),
          const SizedBox(height: 20),
          Text('Password Reset Done! 🎉', style: AppTypography.headlineLarge, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(
            'Your password has been securely updated. You can now log in with your new credentials.',
            style: AppTypography.bodyMedium.copyWith(color: context.ssTextSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          SoulSyncButton(
            label: 'Proceed to Sign In 💞',
            onPressed: () => context.go(RouteNames.login),
          ),
        ],
      ),
    );
  }
}
