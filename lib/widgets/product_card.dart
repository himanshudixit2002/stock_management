import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product_model.dart';
import '../providers/settings_provider.dart';
import '../config/theme.dart';

class ProductCard extends StatefulWidget {
  final ProductModel product;
  final VoidCallback? onTap;
  final VoidCallback? onStockIn;
  final VoidCallback? onStockOut;
  final bool useGridPadding;

  const ProductCard({
    super.key,
    required this.product,
    this.onTap,
    this.onStockIn,
    this.onStockOut,
    this.useGridPadding = false,
  });

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  double _scale = 1.0;

  void _onTapDown(_) => setState(() => _scale = 0.97);
  void _onTapUp(_) => setState(() => _scale = 1.0);
  void _onTapCancel() => setState(() => _scale = 1.0);

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final stockColor = AppTheme.getStockColor(product.quantity,
        threshold: product.lowStockThreshold);
    final stockLabel = AppTheme.getStockLabel(product.quantity,
        threshold: product.lowStockThreshold);
    final stockIcon = AppTheme.getStockIcon(product.quantity,
        threshold: product.lowStockThreshold);

    return Padding(
      padding: widget.useGridPadding
          ? const EdgeInsets.all(0)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: GestureDetector(
        onTapDown: widget.onTap != null ? _onTapDown : null,
        onTapUp: widget.onTap != null ? _onTapUp : null,
        onTapCancel: widget.onTap != null ? _onTapCancel : null,
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Material(
            color: AppTheme.surfaceColor,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: AppTheme.cardShadow,
                ),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        decoration: BoxDecoration(
                          color: stockColor,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(16),
                            bottomLeft: Radius.circular(16),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Hero(
                                      tag: 'product-name-${product.id}',
                                      child: Material(
                                        color: Colors.transparent,
                                        child: Text(
                                          product.name,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.textPrimary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: stockColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '${product.quantity} ${product.unit}',
                                      style: TextStyle(
                                        color: stockColor,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              // Stock status badge
                              Row(
                                children: [
                                  Icon(stockIcon, size: 14, color: stockColor),
                                  const SizedBox(width: 4),
                                  Text(
                                    stockLabel,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: stockColor,
                                    ),
                                  ),
                                  if (product.categoryName.isNotEmpty) ...[
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6),
                                      child: Text(
                                        '\u2022',
                                        style: TextStyle(
                                          fontSize: 8,
                                          color: Colors.grey[400],
                                        ),
                                      ),
                                    ),
                                    Icon(Icons.category_outlined,
                                        size: 12, color: Colors.grey[500]),
                                    const SizedBox(width: 3),
                                    Flexible(
                                      child: Text(
                                        product.categoryName,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[500],
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                  if (product.company.isNotEmpty || product.size.isNotEmpty) ...[
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6),
                                      child: Text(
                                        '\u2022',
                                        style: TextStyle(
                                          fontSize: 8,
                                          color: Colors.grey[400],
                                        ),
                                      ),
                                    ),
                                    Flexible(
                                      child: Text(
                                        [
                                          if (product.company.isNotEmpty) product.company,
                                          if (product.size.isNotEmpty) product.size,
                                        ].join(' | '),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[500],
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              // Pricing (shown only when enabled)
                              Consumer<SettingsProvider>(
                                builder: (context, settings, _) {
                                  if (!settings.pricingEnabled || product.sellingPrice <= 0) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        Icon(Icons.sell_outlined, size: 12, color: AppTheme.successColor),
                                        const SizedBox(width: 4),
                                        Text(
                                          '\u20B9${product.sellingPrice.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.successColor,
                                          ),
                                        ),
                                        if (product.costPrice > 0) ...[
                                          const SizedBox(width: 8),
                                          Text(
                                            'Cost: \u20B9${product.costPrice.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey[500],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                },
                              ),
                              // Vendor info (shown only when vendors enabled)
                              Consumer<SettingsProvider>(
                                builder: (context, settings, _) {
                                  if (!settings.vendorsEnabled) return const SizedBox.shrink();
                                  final vendorName = product.preferredVendorName.isNotEmpty
                                      ? product.preferredVendorName
                                      : product.lastVendorName;
                                  if (vendorName.isEmpty) return const SizedBox.shrink();
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        Icon(Icons.local_shipping_outlined,
                                            size: 12, color: AppTheme.indigoColor),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            vendorName,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                              color: AppTheme.indigoColor,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              // Location info
                              if (product.locationQuantities.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.inputFillColor,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.location_on_outlined,
                                          size: 13, color: Colors.grey[500]),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          product.locationQuantities.length <= 2
                                              ? product.locationQuantities.entries
                                                  .map((e) => '${e.key}: ${e.value}')
                                                  .join(' \u2022 ')
                                              : '${product.locationQuantities.length} locations',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.grey[600],
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (widget.onStockIn != null || widget.onStockOut != null) ...[
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    if (widget.onStockIn != null)
                                      _MiniActionButton(
                                        icon: Icons.add_rounded,
                                        label: 'In',
                                        color: AppTheme.successColor,
                                        onTap: widget.onStockIn!,
                                      ),
                                    if (widget.onStockIn != null && widget.onStockOut != null)
                                      const SizedBox(width: 8),
                                    if (widget.onStockOut != null)
                                      _MiniActionButton(
                                        icon: Icons.remove_rounded,
                                        label: 'Out',
                                        color: AppTheme.dangerColor,
                                        onTap: widget.onStockOut!,
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (widget.onTap != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: Colors.grey[350],
                            size: 16,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MiniActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
