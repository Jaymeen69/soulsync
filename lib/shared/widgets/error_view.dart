import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import 'soulsync_button.dart';

class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.icon = Icons.error_outline_rounded,
  });

  final String message;
  final VoidCallback? onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppColors.error.withValues(alpha: 0.8)),
            const SizedBox(height: 16),
            Text(
              message,
              style: AppTypography.bodyLarge
                  .copyWith(color: context.ssTextPrimary),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              SoulSyncButton(
                label: 'Try Again',
                onPressed: onRetry,
                width: 160,
                height: 44,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
