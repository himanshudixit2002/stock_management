import 'package:flutter/material.dart';
import '../config/motion.dart';
import '../config/theme.dart';
import '../models/product_model.dart';

class StockBadge extends StatefulWidget {
  final ProductModel product;
  final bool showQuantity;

  const StockBadge({
    super.key,
    required this.product,
    this.showQuantity = true,
  });

  @override
  State<StockBadge> createState() => _StockBadgeState();
}

class _StockBadgeState extends State<StockBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: kPulseDuration,
  );

  /// Pulse only when stock is low or out (quantity at/under the threshold).
  bool get _shouldPulse =>
      widget.product.quantity <= widget.product.lowStockThreshold;

  void _syncPulse() {
    if (_shouldPulse && !reduceMotion(context)) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant StockBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final color = AppTheme.getStockColor(
      product.quantity,
      threshold: product.lowStockThreshold,
    );
    final label = AppTheme.getStockLabel(
      product.quantity,
      threshold: product.lowStockThreshold,
    );

    Widget badge(double t) {
      // Gentle color pulse: lerp the gradient/border alpha when low/out.
      final fillTop = 0.16 + 0.10 * t;
      final fillBottom = 0.08 + 0.05 * t;
      final borderAlpha = 0.30 + 0.25 * t;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: fillTop),
              color.withValues(alpha: fillBottom),
            ],
          ),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: borderAlpha)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppTheme.getStockIcon(
                product.quantity,
                threshold: product.lowStockThreshold,
              ),
              size: 10,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              widget.showQuantity
                  ? '${product.formatQuantity(product.availableQuantity)}/${product.formatQuantity(product.quantity)}'
                  : label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      );
    }

    final content = (_shouldPulse && !reduceMotion(context))
        ? AnimatedBuilder(
            animation: _controller,
            builder: (_, __) =>
                badge(Curves.easeInOut.transform(_controller.value)),
          )
        : badge(0);

    return Semantics(
      label:
          '$label: ${product.formatQuantity(product.availableQuantity)} available of ${product.formatQuantity(product.quantity)}',
      child: content,
    );
  }
}
