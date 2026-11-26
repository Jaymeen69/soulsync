import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// An attractive glassmorphic romantic container with soft glowing borders
/// and theme-adaptive surface/text contrast.
class RomanticGlassCard extends StatelessWidget {
  const RomanticGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.borderRadius = 28,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final isDark = context.ssIsDark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: context.ssSurface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : const Color(0xFFEADBFA),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : const Color(0xFF6C3EBC))
                .withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: const Color(0xFFFF4B72)
                .withValues(alpha: isDark ? 0.06 : 0.05),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
