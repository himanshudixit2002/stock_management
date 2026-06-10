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
      title: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      content: Text(
        message,
        style: TextStyle(
          fontSize: 14,
          color: AppTheme.textTer(context),
          height: 1.4,
        ),
      ),
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

void showErrorSnackBar(
  BuildContext context,
  String message, {
  VoidCallback? onRetry,
}) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: TextStyle(color: cs.onError)),
      backgroundColor: cs.error,
      behavior: SnackBarBehavior.floating,
      action: onRetry != null
          ? SnackBarAction(
              label: 'RETRY',
              textColor: cs.onError,
              onPressed: onRetry,
            )
          : null,
    ),
  );
}

void showSuccessSnackBar(BuildContext context, String message) {
  final successBg = AppTheme.isDark(context)
      ? AppTheme.successColor.withValues(alpha: 0.9)
      : AppTheme.successColor;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: successBg,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

void showInfoSnackBar(BuildContext context, String message) {
  final cs = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: TextStyle(color: cs.onInverseSurface)),
      backgroundColor: cs.inverseSurface,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

void showUndoSnackBar(
  BuildContext context,
  String message,
  VoidCallback onUndo,
) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      elevation: 0,
      backgroundColor: Colors.transparent,
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      clipBehavior: Clip.antiAlias,
      duration: const Duration(seconds: 5),
      behavior: SnackBarBehavior.floating,
      content: _UndoSnackBarContent(
        message: message,
        onUndoPressed: () {
          onUndo();
        },
      ),
    ),
  );
}

class _UndoSnackBarContent extends StatefulWidget {
  const _UndoSnackBarContent({
    required this.message,
    required this.onUndoPressed,
  });

  final String message;
  final VoidCallback onUndoPressed;

  @override
  State<_UndoSnackBarContent> createState() => _UndoSnackBarContentState();
}

class _UndoSnackBarContentState extends State<_UndoSnackBarContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _duration = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
        }
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onUndo() {
    _controller.stop();
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    widget.onUndoPressed();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final surface = AppTheme.card(context);
    final border = AppTheme.dividerC(context).withValues(alpha: 0.65);
    final progressColor = cs.primary;

    return Material(
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      color: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 22,
                  color: AppTheme.successColor.withValues(alpha: 0.95),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.message,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPri(context),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _onUndo,
                  style: TextButton.styleFrom(
                    foregroundColor: cs.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Undo',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = 1.0 - _controller.value;
              return ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  value: t.clamp(0.0, 1.0),
                  backgroundColor: AppTheme.dividerC(
                    context,
                  ).withValues(alpha: 0.35),
                  valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Shows a dialog with a single text field to add a named item (e.g. location, size).
/// [onAdd] is called with the trimmed name; return true if added successfully.
/// Returns the new name on success, null on cancel or if [onAdd] returns false.
Future<String?> showAddNameDialog(
  BuildContext context, {
  required String title,
  required String labelText,
  String hint = '',
  required Future<bool> Function(String) onAdd,
}) async {
  final nameController = TextEditingController();
  String? errorText;

  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: nameController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: labelText,
              hintText: hint,
              errorText: errorText,
            ),
            textCapitalization: TextCapitalization.words,
            onChanged: (_) {
              if (errorText != null) setDialogState(() => errorText = null);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  setDialogState(() => errorText = 'Enter a name');
                  return;
                }
                final ok = await onAdd(name);
                if (!ctx.mounted) return;
                if (ok) {
                  Navigator.pop(ctx, name);
                } else {
                  setDialogState(() => errorText = 'Already exists');
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    ),
  );
}
