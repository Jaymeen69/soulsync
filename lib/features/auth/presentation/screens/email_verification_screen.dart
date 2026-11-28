import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/network/api_error_handler.dart';
import '../../../../core/router/route_names.dart';
import '../../../../shared/widgets/romantic_background.dart';
import '../../../../shared/widgets/romantic_glass_card.dart';
import '../../../../shared/widgets/soulsync_button.dart';
import '../providers/auth_provider.dart';

class EmailVerificationScreen extends ConsumerStatefulWidget {
  const EmailVerificationScreen({
    super.key,
    this.email,
  });

  final String? email;

  @override
  ConsumerState<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState
    extends ConsumerState<EmailVerificationScreen> {
  final List<TextEditingController> _otpControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isVerifying = false;
  bool _isResending = false;
  String? _errorMessage;
  String? _successMessage;

  int _resendCountdown = 60;
  int _expiryCountdown = 300; // 5 minutes
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimers(resetExpiry: true);
  }

  void _startTimers({bool resetExpiry = false}) {
    setState(() {
      _resendCountdown = 60;
      if (resetExpiry) _expiryCountdown = 300;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_resendCountdown > 0) _resendCountdown--;
        if (_expiryCountdown > 0) _expiryCountdown--;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String _getOtp() => _otpControllers.map((c) => c.text.trim()).join();

  String _formatClock(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _handlePasteOrInput(int index, String val) {
    final digits = val.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 1) {
      for (int i = 0; i < 6; i++) {
        _otpControllers[i].text = i < digits.length ? digits[i] : '';
      }
      final nextIdx = digits.length.clamp(0, 5);
      _focusNodes[nextIdx].requestFocus();
      if (digits.length >= 6) {
        _verifyOtp();
      }
      return;
    }

    if (digits.isNotEmpty) {
      _otpControllers[index].text = digits[0];
      _otpControllers[index].selection =
          const TextSelection.collapsed(offset: 1);
      if (index < 5) {
        _focusNodes[index + 1].requestFocus();
      }
    } else if (index > 0) {
      _focusNodes[index - 1].requestFocus();
    }

    if (_getOtp().length == 6) {
      _verifyOtp();
    }
  }

  void _handleBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RouteNames.login);
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _getOtp();
    if (otp.length < 6) {
      setState(() => _errorMessage =
          'Please enter the complete 6-digit verification code.');
      return;
    }

    final targetEmail =
        widget.email ?? ref.read(currentUserProvider)?.email ?? '';
    if (targetEmail.isEmpty) {
      setState(() => _errorMessage =
          'Email address not found. Please register again.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await ref.read(authRepositoryProvider).verifyOtp(
            email: targetEmail,
            otp: otp,
          );

      if (mounted) {
        setState(() {
          _successMessage =
              'Email verified and account activated! 🎉 Redirecting to Sign In...';
        });
        await Future.delayed(const Duration(milliseconds: 1200));
        if (mounted) {
          context.go(RouteNames.login);
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = ApiErrorHandler.friendlyMessage(e);
      });
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _resend() async {
    if (_resendCountdown > 0 || _isResending) return;
    final targetEmail =
        widget.email ?? ref.read(currentUserProvider)?.email ?? '';
    if (targetEmail.isEmpty) return;

    setState(() {
      _isResending = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await ref.read(authRepositoryProvider).resendOtp(targetEmail);
      if (mounted) {
        for (final c in _otpControllers) {
          c.clear();
        }
        _focusNodes[0].requestFocus();
        setState(() {
          _successMessage =
              'A new 6-digit verification code has been emailed to $targetEmail.';
        });
        _startTimers(resetExpiry: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = ApiErrorHandler.friendlyMessage(
              e,
              fallback: ApiErrorHandler.otpSendFailedMsg,
            ));
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayEmail =
        widget.email ?? ref.watch(currentUserProvider)?.email ?? 'your email';

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
              icon: Icon(Icons.arrow_back_ios_new_rounded,
                  size: 18, color: context.ssPrimary),
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
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.romanticRose.withValues(alpha: 0.35),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.mark_email_read_rounded,
                          size: 42, color: Colors.white),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Verify Your Email 🔒',
                      style: AppTypography.displayMedium.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Check your inbox at $displayEmail for the 6-digit SoulSync code.',
                      style: AppTypography.bodyMedium
                          .copyWith(color: context.ssTextSecondary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _expiryCountdown == 0
                            ? AppColors.error.withValues(alpha: 0.12)
                            : context.ssSurfaceVariant,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _expiryCountdown == 0
                            ? 'Code expired — please resend a fresh code'
                            : 'Code valid for ${_formatClock(_expiryCountdown)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _expiryCountdown == 0
                              ? AppColors.error
                              : context.ssPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    RomanticGlassCard(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        children: [
                          if (_errorMessage != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color:
                                        AppColors.error.withValues(alpha: 0.25)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline,
                                      color: AppColors.error, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(_errorMessage!,
                                        style: const TextStyle(
                                            color: AppColors.error,
                                            fontSize: 13)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (_successMessage != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: AppColors.success
                                        .withValues(alpha: 0.25)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.check_circle_rounded,
                                      color: AppColors.success, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(_successMessage!,
                                        style: const TextStyle(
                                            color: AppColors.success,
                                            fontSize: 13)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: List.generate(6, (index) {
                              return SizedBox(
                                width: 44,
                                height: 54,
                                child: TextField(
                                  controller: _otpControllers[index],
                                  focusNode: _focusNodes[index],
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: context.ssPrimary),
                                  decoration: InputDecoration(
                                    counterText: '',
                                    filled: true,
                                    fillColor: context.ssInputFill,
                                    contentPadding: EdgeInsets.zero,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide(
                                          color: context.ssBorder, width: 1.5),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide(
                                          color: context.ssBorder, width: 1.5),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide(
                                          color: context.ssPrimary, width: 2),
                                    ),
                                  ),
                                  onChanged: (val) =>
                                      _handlePasteOrInput(index, val),
                                ),
                              );
                            }),
                          ),
                          const SizedBox(height: 24),
                          SoulSyncButton(
                            label: 'Verify OTP & Activate Account 💞',
                            onPressed: _verifyOtp,
                            isLoading: _isVerifying,
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _resendCountdown > 0
                                    ? 'Resend code in ${_resendCountdown}s'
                                    : 'Didn\'t receive the email? ',
                                style: AppTypography.bodySmall
                                    .copyWith(color: context.ssTextSecondary),
                              ),
                              if (_resendCountdown == 0)
                                TextButton(
                                  onPressed: _isResending ? null : _resend,
                                  child: Text(
                                    _isResending ? 'Sending...' : 'Resend OTP',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () => context.go(RouteNames.login),
                      style: TextButton.styleFrom(
                          foregroundColor: context.ssPrimary),
                      child: const Text('Back to Sign In',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
