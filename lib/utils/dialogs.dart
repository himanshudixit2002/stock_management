import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/motion.dart';
import '../config/theme.dart';
import '../widgets/animations.dart';

/// Rounded corner radius shared by all app dialogs (Playful Professional spec).
const double _kDialogRadius = 20;

/// Presents [builder] as a modal dialog with the app's playful entrance:
/// a spring scale + fade ([kSpringCurve]) and, on web, a backdrop blur that
/// fades in with the dialog. Honors reduce-motion (instant, no blur churn).
///
/// This is an internal presentation helper only — callers keep using the
/// public [showConfirmDialog] / [showAddNameDialog] APIs, whose return types
/// and awaited results are unchanged.
Future<T?> _showAppDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final reduce = reduceMotion(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: reduce
        ? Duration.zero
        : const Duration(milliseconds: 260),
    pageBuilder: (ctx, _, _) => builder(ctx),
    transitionBuilder: (ctx, animation, _, child) {
      if (reduce) return child;
      final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      final scale = CurvedAnimation(
        parent: animation,
        curve: kSpringCurve,
        reverseCurve: Curves.easeIn,
      );
      Widget result = FadeTransition(
        opacity: fade,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(scale),
          child: child,
        ),
      );
      if (kIsWeb) {
        final sigma = 6.0 * animation.value;
        result = BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: result,
        );
      }
      return result;
    },
  );
}

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
  final result = await _showAppDialog<bool>(
    context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_kDialogRadius),
      ),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedIconBadge(icon: icon, color: iconColor, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
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

/// Themed, floating snackbar content with a leading status [icon].
Widget _snackContent(IconData icon, String message, Color fg) {
  return Row(
    children: [
      Icon(icon, color: fg, size: 20),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          message,
          style: TextStyle(color: fg, fontWeight: FontWeight.w500),
        ),
      ),
    ],
  );
}

RoundedRectangleBorder get _snackShape =>
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

void showErrorSnackBar(
  BuildContext context,
  String message, {
  VoidCallback? onRetry,
}) {
  final cs = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: _snackContent(Icons.error_outline_rounded, message, cs.onError),
      backgroundColor: cs.error,
      behavior: SnackBarBehavior.floating,
      shape: _snackShape,
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
      content: _snackContent(
        Icons.check_circle_rounded,
        message,
        Colors.white,
      ),
      backgroundColor: successBg,
      behavior: SnackBarBehavior.floating,
      shape: _snackShape,
    ),
  );
}

void showInfoSnackBar(BuildContext context, String message) {
  final cs = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: _snackContent(
        Icons.info_outline_rounded,
        message,
        cs.onInverseSurface,
      ),
      backgroundColor: cs.inverseSurface,
      behavior: SnackBarBehavior.floating,
      shape: _snackShape,
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
              // Under reduce-motion, show a static full bar (no churn); the
              // countdown still drives auto-dismiss via the status listener.
              final t = reduceMotion(context)
                  ? 1.0
                  : (1.0 - _controller.value);
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

  return _showAppDialog<String>(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_kDialogRadius),
          ),
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
