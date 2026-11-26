import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/router/route_names.dart';

class MainScaffold extends StatelessWidget {
  const MainScaffold({super.key, required this.child});

  final Widget child;

  static const List<_NavItem> _navItems = [
    _NavItem(label: 'Home', icon: Icons.home_outlined, activeIcon: Icons.home_rounded, route: RouteNames.home),
    _NavItem(label: 'Connect', icon: Icons.favorite_outline_rounded, activeIcon: Icons.favorite_rounded, route: RouteNames.connect),
    _NavItem(label: 'Together', icon: Icons.people_outline_rounded, activeIcon: Icons.people_rounded, route: RouteNames.together),
    _NavItem(label: 'Memories', icon: Icons.photo_library_outlined, activeIcon: Icons.photo_library_rounded, route: RouteNames.memories),
    _NavItem(label: 'Profile', icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded, route: RouteNames.profile),
  ];

  int _currentIndex(String location) {
    if (location.startsWith(RouteNames.connect)) return 1;
    if (location.startsWith(RouteNames.together)) return 2;
    if (location.startsWith(RouteNames.memories)) return 3;
    if (location.startsWith(RouteNames.profile)) return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _currentIndex(location);

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: context.ssSurface,
          border: Border(top: BorderSide(color: context.ssBorder.withValues(alpha: 0.6))),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: context.ssIsDark ? 0.2 : 0.08),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(_navItems.length, (index) {
                final item = _navItems[index];
                final isActive = currentIndex == index;
                return _NavButton(
                  item: item,
                  isActive: isActive,
                  onTap: () => context.go(item.route),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.route,
  });
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String route;
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  final _NavItem item;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeColor = context.ssPrimary;
    final inactiveColor = context.ssTextSecondary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: isActive
            ? BoxDecoration(
                color: activeColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? item.activeIcon : item.icon,
              color: isActive ? activeColor : inactiveColor,
              size: 24,
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                color: isActive ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
