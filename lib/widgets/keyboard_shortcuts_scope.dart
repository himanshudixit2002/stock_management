import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/motion.dart';
import '../config/routes.dart';
import '../config/theme.dart';

/// Web-only power-user keyboard shortcuts mounted at the app shell.
///
/// Listens at the [HardwareKeyboard] level (not via focus traversal) so it never
/// steals focus from inputs, and it explicitly ignores keys while a text field
/// is focused so typing is never hijacked. On non-web platforms it is a no-op
/// passthrough. Honors reduce-motion when presenting the overlay.
///
/// Wired shortcuts (only ones that genuinely work are advertised):
///   * `/`   → open global search
///   * `?`   → toggle this shortcuts panel
class KeyboardShortcutsScope extends StatefulWidget {
  final Widget child;
  const KeyboardShortcutsScope({super.key, required this.child});

  @override
  State<KeyboardShortcutsScope> createState() => _KeyboardShortcutsScopeState();
}

class _KeyboardShortcutsScopeState extends State<KeyboardShortcutsScope> {
  bool _overlayOpen = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      HardwareKeyboard.instance.addHandler(_onKey);
    }
  }

  @override
  void dispose() {
    if (kIsWeb) {
      HardwareKeyboard.instance.removeHandler(_onKey);
    }
    super.dispose();
  }

  /// True when the user is typing — never intercept keys in that case.
  bool get _isEditing {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (_isEditing) return false;
    final char = event.character;
    if (char == '?') {
      _toggleOverlay();
      return true;
    }
    if (char == '/') {
      _go(AppRoutes.globalSearch);
      return true;
    }
    return false;
  }

  void _go(String route) {
    if (!mounted) return;
    Navigator.of(context).pushNamed(route);
  }

  Future<void> _toggleOverlay() async {
    if (!mounted) return;
    if (_overlayOpen) {
      Navigator.of(context).maybePop();
      return;
    }
    _overlayOpen = true;
    final reduce = reduceMotion(context);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Keyboard shortcuts',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration:
          reduce ? Duration.zero : const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, _) => const _ShortcutsDialog(),
      transitionBuilder: (ctx, animation, _, child) {
        if (reduce) return child;
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      },
    );
    _overlayOpen = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ShortcutsDialog extends StatelessWidget {
  const _ShortcutsDialog();

  static const _shortcuts = <(String, String)>[
    ('/', 'Open search'),
    ('?', 'Show this shortcuts panel'),
    ('Esc', 'Close an open dialog or menu'),
    ('Tab / Shift+Tab', 'Move focus between controls'),
    ('Enter / Space', 'Activate the focused control'),
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.keyboard_rounded,
                    color: AppTheme.primaryColor,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Keyboard shortcuts',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPri(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              for (final (keys, desc) in _shortcuts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.primaryColor.withValues(alpha: 0.20),
                          ),
                        ),
                        child: Text(
                          keys,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          desc,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: AppTheme.textSec(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
