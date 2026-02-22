import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  String cancelLabel = 'Cancel',
  IconData icon = Icons.warning_amber_rounded,
  Color iconColor = AppTheme.dangerColor,
  Color? confirmColor,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      content: Text(message,
          style: TextStyle(fontSize: 14, color: Colors.grey[600], height: 1.4)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        ElevatedButton(
          onPressed: () {
            HapticFeedback.heavyImpact();
            Navigator.pop(ctx, true);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: confirmColor ?? iconColor,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showErrorSnackBar(BuildContext context, String message, {VoidCallback? onRetry}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: AppTheme.dangerColor,
      behavior: SnackBarBehavior.floating,
      action: onRetry != null
          ? SnackBarAction(
              label: 'RETRY',
              textColor: Colors.white,
              onPressed: onRetry,
            )
          : null,
    ),
  );
}

void showSuccessSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: AppTheme.successColor,
      behavior: SnackBarBehavior.floating,
    ),
  );
}
