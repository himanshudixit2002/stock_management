import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/product_model.dart';

class StockBadge extends StatelessWidget {
  final ProductModel product;
  final bool showQuantity;

  const StockBadge({
    super.key,
    required this.product,
    this.showQuantity = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.getStockColor(
      product.quantity,
      threshold: product.lowStockThreshold,
    );
    final label = AppTheme.getStockLabel(
      product.quantity,
      threshold: product.lowStockThreshold,
    );

    return Semantics(
      label: '$label: ${product.quantity} ${product.unit}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
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
              showQuantity ? '${product.quantity} ${product.unit}' : label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
