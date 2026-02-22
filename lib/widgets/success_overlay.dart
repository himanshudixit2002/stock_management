import 'package:flutter/material.dart';
import '../config/theme.dart';

Future<void> showSuccessOverlay(
  BuildContext context, {
  String message = 'Success!',
  Duration displayDuration = const Duration(milliseconds: 1200),
  bool popAfter = true,
}) async {
  final overlay = Overlay.of(context);
  late final OverlayEntry entry;

  entry = OverlayEntry(
    builder: (ctx) => _SuccessOverlayWidget(
      message: message,
      onDone: () {
        entry.remove();
        if (popAfter && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      displayDuration: displayDuration,
    ),
  );

  overlay.insert(entry);
}

class _SuccessOverlayWidget extends StatefulWidget {
  final String message;
  final VoidCallback onDone;
  final Duration displayDuration;

  const _SuccessOverlayWidget({
    required this.message,
    required this.onDone,
    required this.displayDuration,
  });

  @override
  State<_SuccessOverlayWidget> createState() => _SuccessOverlayWidgetState();
}

class _SuccessOverlayWidgetState extends State<_SuccessOverlayWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );
    _controller.forward();

    Future.delayed(widget.displayDuration, () {
      if (mounted) {
        _controller.reverse().then((_) => widget.onDone());
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Material(
        color: Colors.black26,
        child: Center(
          child: ScaleTransition(
            scale: _scale,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppTheme.successColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: AppTheme.successColor,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.message,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                      decoration: TextDecoration.none,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
