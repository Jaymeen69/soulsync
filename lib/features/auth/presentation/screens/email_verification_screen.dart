import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/router/route_names.dart';
import '../../../../shared/widgets/soulsync_button.dart';
import '../providers/auth_provider.dart';

class EmailVerificationScreen extends ConsumerStatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  ConsumerState<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends ConsumerState<EmailVerificationScreen> {
  bool _isResending = false;
  String? _message;

  Future<void> _resend() async {
    final user = ref.read(currentUserProvider);
    if (user?.email == null) return;
    setState(() { _isResending = true; _message = null; });
    try {
      await ref.read(authRepositoryProvider).resendVerificationEmail(user!.email!);
      setState(() => _message = 'Verification email sent! Check your inbox.');
    } catch (e) {
      setState(() => _message = 'Failed to resend. Please try again.');
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mark_email_unread_rounded, size: 52, color: AppColors.primary),
              ),
              const SizedBox(height: 32),
              Text('Verify your email', style: AppTypography.headlineLarge, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                'We sent a verification link to\n${user?.email ?? 'your email'}',
                style: AppTypography.bodyLarge.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Click the link in that email to continue.',
                style: AppTypography.bodyMedium,
                textAlign: TextAlign.center,
              ),
              if (_message != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_message!, style: TextStyle(color: AppColors.success), textAlign: TextAlign.center),
                ),
              ],
              const SizedBox(height: 40),
              SoulSyncButton(label: 'Resend Email', onPressed: _resend, isLoading: _isResending, variant: SoulSyncButtonVariant.outlined),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.go(RouteNames.login),
                child: const Text('Back to Sign In'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
