import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/router/route_names.dart';
import '../../../../shared/widgets/soulsync_button.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const List<_OnboardingPage> _pages = [
    _OnboardingPage(
      icon: Icons.favorite_rounded,
      title: 'Stay Connected',
      description: 'Feel close to your partner no matter the distance. Share moments that matter most.',
      color: AppColors.pulseLove,
    ),
    _OnboardingPage(
      icon: Icons.auto_awesome_rounded,
      title: 'Private & Safe',
      description: 'Your couple space is completely private. Only you two can see what you share.',
      color: AppColors.primary,
    ),
    _OnboardingPage(
      icon: Icons.photo_library_rounded,
      title: 'Build Memories',
      description: 'Capture moments, share rituals, and celebrate your relationship milestones together.',
      color: AppColors.accent,
    ),
    _OnboardingPage(
      icon: Icons.link_rounded,
      title: 'Pair Privately',
      description: 'Exchange your 8-character invitation code to unlock your private space, daily streaks, and couple games.',
      color: Color(0xFFE94057),
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _showPermissionsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.security_rounded, color: AppColors.primary),
            SizedBox(width: 8),
            Text('App Permissions 🛡️', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('To provide an intimate, real-time experience, SoulSync uses:', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            SizedBox(height: 12),
            _PermissionItem(icon: Icons.notifications_active, title: 'Notifications', desc: 'Real-time love pulses, chat whispers, and daily questions.'),
            _PermissionItem(icon: Icons.mic, title: 'Microphone', desc: 'Sending cozy voice whispers to your partner.'),
            _PermissionItem(icon: Icons.photo_library, title: 'Photos & Vault', desc: 'Preserving relationship memories in your private vault.'),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              context.go(RouteNames.register);
            },
            child: const Text('Understand & Continue'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton(
                  onPressed: () => context.go(RouteNames.login),
                  child: const Text('Skip'),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  final p = _pages[index];
                  return _OnboardingPage(
                    icon: p.icon,
                    title: p.title,
                    description: p.description,
                    color: p.color,
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentPage == i ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: _currentPage == i ? AppColors.primary : AppColors.textHint,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_currentPage < _pages.length - 1)
                    SoulSyncButton(
                      label: 'Next',
                      onPressed: () => _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      ),
                    )
                  else ...[
                    SoulSyncButton(
                      label: 'Get Started',
                      onPressed: () => _showPermissionsDialog(context),
                    ),
                    const SizedBox(height: 12),
                    SoulSyncButton(
                      label: 'I already have an account',
                      variant: SoulSyncButtonVariant.outlined,
                      onPressed: () => context.go(RouteNames.login),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color color;

  void _showPermissionsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.security_rounded, color: AppColors.primary),
            SizedBox(width: 8),
            Text('App Permissions 🛡️', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('To provide an intimate, real-time experience, SoulSync uses:', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            SizedBox(height: 12),
            _PermissionItem(icon: Icons.notifications_active, title: 'Notifications', desc: 'Real-time love pulses, chat whispers, and daily questions.'),
            _PermissionItem(icon: Icons.mic, title: 'Microphone', desc: 'Sending cozy voice whispers to your partner.'),
            _PermissionItem(icon: Icons.photo_library, title: 'Photos & Vault', desc: 'Preserving relationship memories in your private vault.'),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              context.go(RouteNames.register);
            },
            child: const Text('Understand & Continue'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 72, color: color),
          ),
          const SizedBox(height: 40),
          Text(title, style: AppTypography.displayMedium, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Text(
            description,
            style: AppTypography.bodyLarge.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PermissionItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;

  const _PermissionItem({required this.icon, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primary.withOpacity(0.1),
            child: Icon(icon, size: 16, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary)),
                Text(desc, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
