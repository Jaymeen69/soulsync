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

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _isLoading = false;
  bool _sent = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(authRepositoryProvider).resetPassword(_emailCtrl.text);
      if (mounted) setState(() => _sent = true);
    } catch (_) {
      // Don't reveal if email exists — always show success message for security
      if (mounted) setState(() => _sent = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const BackButton()),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _sent ? _SentView(email: _emailCtrl.text, onBack: () => context.go(RouteNames.login)) : Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reset password', style: AppTypography.headlineLarge),
                const SizedBox(height: 8),
                Text('Enter your email and we\'ll send a reset link.', style: AppTypography.bodyMedium),
                const SizedBox(height: 32),
                SoulSyncTextField(
                  label: 'Email',
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  prefixIcon: Icons.email_outlined,
                  validator: Validators.email,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _send(),
                ),
                const SizedBox(height: 24),
                SoulSyncButton(label: 'Send Reset Link', onPressed: _send, isLoading: _isLoading),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SentView extends StatelessWidget {
  const _SentView({required this.email, required this.onBack});
  final String email;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle_rounded, size: 80, color: AppColors.success),
        const SizedBox(height: 24),
        Text('Check your inbox', style: AppTypography.headlineLarge, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Text('If $email is registered, you\'ll receive a reset link shortly.', style: AppTypography.bodyMedium, textAlign: TextAlign.center),
        const SizedBox(height: 40),
        SoulSyncButton(label: 'Back to Sign In', onPressed: onBack, variant: SoulSyncButtonVariant.outlined),
      ],
    );
  }
}
