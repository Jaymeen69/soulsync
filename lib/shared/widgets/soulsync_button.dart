import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';

enum SoulSyncButtonVariant { primary, secondary, outlined, ghost }

class SoulSyncButton extends StatelessWidget {
  const SoulSyncButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = SoulSyncButtonVariant.primary,
    this.isLoading = false,
    this.icon,
    this.width,
    this.height = 54,
  });

  final String label;
  final VoidCallback? onPressed;
  final SoulSyncButtonVariant variant;
  final bool isLoading;
  final IconData? icon;
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final child = isLoading
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20),
                const SizedBox(width: 8),
              ],
              Text(label, style: AppTypography.labelLarge),
            ],
          );

    Widget button;
    switch (variant) {
      case SoulSyncButtonVariant.primary:
        button = ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          child: child,
        );
      case SoulSyncButtonVariant.secondary:
        button = ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
          ),
          child: child,
        );
      case SoulSyncButtonVariant.outlined:
        button = OutlinedButton(
          onPressed: isLoading ? null : onPressed,
          child: child,
        );
      case SoulSyncButtonVariant.ghost:
        button = TextButton(
          onPressed: isLoading ? null : onPressed,
          child: child,
        );
    }

    return SizedBox(
      width: width ?? double.infinity,
      height: height,
      child: button,
    );
  }
}
