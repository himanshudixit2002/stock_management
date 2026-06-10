import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../config/theme.dart';

class _CheckPainter extends CustomPainter {
  final double progress;
  final Color color;

  _CheckPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(size.width * 0.2, size.height * 0.5)
      ..lineTo(size.width * 0.45, size.height * 0.7)
      ..lineTo(size.width * 0.8, size.height * 0.3);

    final metrics = path.computeMetrics().first;
    final drawPath = metrics.extractPath(0, metrics.length * progress);
    canvas.drawPath(drawPath, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress;
}

Future<void> showSuccessOverlay(
  BuildContext context, {
  String message = 'Success!',
  Duration displayDuration = const Duration(milliseconds: 1200),
  bool popAfter = true,
  Object? popResult,
}) async {
  final overlay = Overlay.of(context);
  late final OverlayEntry entry;

  entry = OverlayEntry(
    builder: (ctx) => _SuccessOverlayWidget(
      message: message,
      onDone: () {
        entry.remove();
        if (popAfter && context.mounted) {
          Navigator.of(context).pop(popResult);
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
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final AnimationController _checkController;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;
  Timer? _dismissTimer;

  // Particle positions (angles in radians, relative to center)
  static final List<double> _particleAngles = [
    0,
    math.pi / 4,
    math.pi / 2,
    (3 * math.pi) / 4,
    math.pi,
    (5 * math.pi) / 4,
    (3 * math.pi) / 2,
    (7 * math.pi) / 4,
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );
    _controller.forward();
    _checkController.forward();

    _dismissTimer = Timer(widget.displayDuration, () {
      if (mounted) {
        _controller.reverse().then((_) => widget.onDone());
      }
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    _checkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: widget.message,
      child: FadeTransition(
        opacity: _opacity,
        child: Material(
          color: AppTheme.textPri(context).withValues(alpha: 0.26),
          child: Center(
            child: ScaleTransition(
              scale: _scale,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 36,
                  vertical: 28,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.surface(context),
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
                    AnimatedBuilder(
                      animation: Listenable.merge([
                        _controller,
                        _checkController,
                      ]),
                      builder: (context, _) {
                        return SizedBox(
                          width: 64,
                          height: 64,
                          child: Stack(
                            alignment: Alignment.center,
                            clipBehavior: Clip.none,
                            children: [
                              // Subtle particle effects
                              ..._particleAngles.asMap().entries.map((e) {
                                final delay = e.key * 0.08;
                                final t =
                                    ((_checkController.value - delay) /
                                            (1 - delay))
                                        .clamp(0.0, 1.0);
                                final scale = Curves.easeOut.transform(t);
                                final opacity = (1 - t) * 0.5;
                                final r = 22.0 + t * 8;
                                final dx = r * math.cos(e.value);
                                final dy = r * math.sin(e.value);
                                return Positioned(
                                  left: 32 + dx - 4,
                                  top: 32 + dy - 4,
                                  child: Opacity(
                                    opacity: opacity,
                                    child: Transform.scale(
                                      scale: scale,
                                      child: Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: AppTheme.successColor,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                              // Animated checkmark
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: AppTheme.successColor.withValues(
                                    alpha: 0.12,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: CustomPaint(
                                  painter: _CheckPainter(
                                    progress: _checkController.value,
                                    color: AppTheme.successColor,
                                  ),
                                  size: const Size(64, 64),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.message,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPri(context),
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
      ),
    );
  }
}
