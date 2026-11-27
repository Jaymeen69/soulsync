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
import '../widgets/social_connect_sheet.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _partnerCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _socialAccountCtrl = TextEditingController();
  String? _selectedSocialProvider;
  bool _isLoading = false;
  String? _errorMessage;
  bool _agreedToTerms = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _partnerCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _socialAccountCtrl.dispose();
    super.dispose();
  }

  void _handleBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RouteNames.login);
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreedToTerms) {
      setState(() => _errorMessage = 'Please agree to the Privacy Policy to continue.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authRepo = ref.read(authRepositoryProvider);
      final email = _emailCtrl.text.trim().toLowerCase();
      await authRepo.register(
        email: email,
        password: _passwordCtrl.text,
        displayName: _nameCtrl.text.trim(),
        partnerName: _partnerCtrl.text.trim().isEmpty ? 'Partner' : _partnerCtrl.text.trim(),
        socialProvider: _selectedSocialProvider,
        socialAccount: _socialAccountCtrl.text.trim(),
      );

      if (mounted) {
        // Enforce mandatory real email OTP verification before login/activation
        context.push(
          RouteNames.emailVerification,
          extra: {'email': email},
        );
      }
    } catch (e) {
      final raw = e.toString().replaceFirst('Exception: ', '');
      final friendly = (raw.contains('SocketException') ||
              raw.contains('Connection refused') ||
              raw.contains('TimeoutException'))
          ? 'Cannot reach SoulSync server (${AuthNotifier.apiBaseUrl}). Ensure your phone & server are on the same Wi-Fi or tap the server icon above.'
          : raw;
      setState(() => _errorMessage = friendly);
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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14, top: 8),
            child: IconButton(
              icon: Icon(Icons.dns_outlined, size: 20, color: context.ssTextSecondary),
              tooltip: 'Server Connection',
              onPressed: () => showServerUrlDialog(context),
            ),
          ),
        ],
      ),
      body: RomanticBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Header
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.romanticRose.withOpacity(0.35),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/images/app_logo.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      Text(
                        'Create Account 💞',
                        style: AppTypography.displayMedium.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Start your shared journey together',
                        style: AppTypography.bodyMedium.copyWith(
                          color: context.ssTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 24),

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

                            SoulSyncTextField(
                              label: 'Your Name',
                              hint: 'How your partner sees you',
                              controller: _nameCtrl,
                              validator: Validators.displayName,
                              prefixIcon: Icons.person_outline_rounded,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 16),

                            SoulSyncTextField(
                              label: 'Partner\'s Name (Optional)',
                              hint: 'Your partner\'s nickname or first name',
                              controller: _partnerCtrl,
                              prefixIcon: Icons.favorite_border_rounded,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 16),

                            SoulSyncTextField(
                              label: 'Email Address',
                              hint: 'your.name@example.com',
                              controller: _emailCtrl,
                              validator: Validators.email,
                              keyboardType: TextInputType.emailAddress,
                              prefixIcon: Icons.email_outlined,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 16),

                            SoulSyncTextField(
                              label: 'Password',
                              hint: 'Min 8 chars, 1 uppercase, 1 number, 1 special',
                              controller: _passwordCtrl,
                              obscureText: true,
                              validator: Validators.password,
                              prefixIcon: Icons.lock_outline_rounded,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 16),

                            SoulSyncTextField(
                              label: 'Confirm Password',
                              hint: 'Re-enter your password',
                              controller: _confirmPasswordCtrl,
                              obscureText: true,
                              validator: (v) => Validators.confirmPassword(v, _passwordCtrl.text),
                              prefixIcon: Icons.lock_clock_outlined,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 16),

                            // Optional Social Account Field (Google / Apple / Instagram / Other)
                            Text(
                              'Social Account (Optional)',
                              style: AppTypography.labelLarge.copyWith(
                                color: context.ssTextPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: kSocialProviders.map((p) {
                                final id = p['id'] as String;
                                final selected = _selectedSocialProvider == id;
                                return ChoiceChip(
                                  avatar: Icon(
                                    p['icon'] as IconData,
                                    size: 16,
                                    color: selected ? Colors.white : context.ssPrimary,
                                  ),
                                  label: Text(p['label'] as String),
                                  selected: selected,
                                  selectedColor: AppColors.primary,
                                  labelStyle: TextStyle(
                                    color: selected ? Colors.white : context.ssTextPrimary,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  backgroundColor: context.ssInputFill,
                                  onSelected: (val) => setState(() {
                                    _selectedSocialProvider = val ? id : null;
                                  }),
                                );
                              }).toList(),
                            ),
                            if (_selectedSocialProvider != null) ...[
                              const SizedBox(height: 12),
                              SoulSyncTextField(
                                label: '${_selectedSocialProvider![0].toUpperCase()}${_selectedSocialProvider!.substring(1)} Account',
                                hint: 'e.g. your.name@gmail.com or @handle',
                                controller: _socialAccountCtrl,
                                prefixIcon: Icons.alternate_email_rounded,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _register(),
                              ),
                            ],
                            const SizedBox(height: 16),

                            InkWell(
                              onTap: () => setState(() => _agreedToTerms = !_agreedToTerms),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: _agreedToTerms
                                      ? context.ssPrimary.withValues(alpha: 0.1)
                                      : context.ssInputFill,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: _agreedToTerms ? context.ssPrimary : context.ssBorder,
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Transform.scale(
                                      scale: 1.15,
                                      child: Checkbox(
                                        value: _agreedToTerms,
                                        activeColor: AppColors.primary,
                                        checkColor: Colors.white,
                                        side: BorderSide(color: context.ssPrimary, width: 2),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                                        onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'I agree to the SoulSync Privacy Policy and Terms of Couple Data Security.',
                                        style: AppTypography.bodySmall.copyWith(
                                          color: context.ssTextPrimary,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 22),

                            SoulSyncButton(
                              label: 'Create Account & Send OTP 💌',
                              onPressed: _register,
                              isLoading: _isLoading,
                            ),
                            const SizedBox(height: 18),
                            const SocialAuthButtons(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),

                      Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Already have an account? ',
                              style: AppTypography.bodyMedium.copyWith(color: context.ssTextSecondary),
                            ),
                            TextButton(
                              onPressed: () => context.go(RouteNames.login),
                              style: TextButton.styleFrom(foregroundColor: context.ssPrimary),
                              child: const Text(
                                'Sign In',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
