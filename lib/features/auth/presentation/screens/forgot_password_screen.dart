import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/router/route_names.dart';
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

  @override
  void dispose() {
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _newPwCtrl.dispose();
    _confirmPwCtrl.dispose();
    super.dispose();
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
        _statusMessage = 'A 6-digit password reset code has been sent to $email.';
      });
    } catch (e) {
      setState(() => _errorMessage = 'Unable to send reset code. Please try again.');
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
        _statusMessage = 'Code verified! Please create your new strong password.';
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
      appBar: AppBar(leading: const BackButton()),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_currentStep == ForgotPasswordStep.completed)
                _buildCompletedView()
              else ...[
                Text('Reset Password 🔑', style: AppTypography.displayMedium),
                const SizedBox(height: 6),
                Text(
                  _getStepSubtitle(),
                  style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),

                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.error.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_errorMessage!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
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
                    child: Text(_statusMessage!, style: const TextStyle(color: AppColors.primary, fontSize: 13)),
                  ),
                  const SizedBox(height: 20),
                ],

                if (_currentStep == ForgotPasswordStep.enterEmail) _buildEmailStep(),
                if (_currentStep == ForgotPasswordStep.enterOtp) _buildOtpStep(),
                if (_currentStep == ForgotPasswordStep.newPassword) _buildNewPasswordStep(),
              ],
            ],
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
            label: 'Send Verification Code',
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
          hint: 'e.g. 123456',
          controller: _otpCtrl,
          keyboardType: TextInputType.number,
          prefixIcon: Icons.pin_outlined,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _verifyOtp(),
        ),
        const SizedBox(height: 24),
        SoulSyncButton(
          label: 'Verify Code',
          onPressed: _verifyOtp,
          isLoading: _isLoading,
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() => _currentStep = ForgotPasswordStep.enterEmail),
          child: const Text('Change Email'),
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
            hint: 'Min 8 chars, 1 uppercase, 1 number, 1 special char',
            controller: _newPwCtrl,
            obscureText: true,
            validator: Validators.password,
            prefixIcon: Icons.lock_outline,
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
            label: 'Update Password & Finish',
            onPressed: _updatePassword,
            isLoading: _isLoading,
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 40),
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_rounded, size: 56, color: AppColors.success),
        ),
        const SizedBox(height: 24),
        Text('Password Reset Done! 🎉', style: AppTypography.headlineLarge, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Text(
          'Your password has been securely updated. You can now log in with your new credentials.',
          style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 36),
        SoulSyncButton(
          label: 'Proceed to Sign In',
          onPressed: () => context.go(RouteNames.login),
        ),
      ],
    );
  }
}
