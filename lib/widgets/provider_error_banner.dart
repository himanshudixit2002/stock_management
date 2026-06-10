import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Dismissible strip for provider [errorMessage] with optional [onRetry].
class ProviderErrorBanner extends StatelessWidget {
  const ProviderErrorBanner({
    super.key,
    required this.message,
    this.onDismiss,
    this.onRetry,
    this.retryLabel = 'Retry',
  });

  final String message;
  final VoidCallback? onDismiss;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.dangerColor.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: AppTheme.dangerColor,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textPri(context),
                  height: 1.35,
                ),
              ),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: Text(retryLabel)),
            if (onDismiss != null)
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: onDismiss,
                tooltip: 'Dismiss',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
          ],
        ),
      ),
    );
  }
}
