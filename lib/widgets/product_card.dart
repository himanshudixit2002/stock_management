import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product_model.dart';
import '../providers/settings_provider.dart';
import '../config/theme.dart';
import 'glass_panel.dart';
import 'stock_badge.dart';

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
    final isGrid = widget.useGridPadding;
    final stockColor = AppTheme.getStockColor(
      product.quantity,
      threshold: product.lowStockThreshold,
    );
    final stockLabel = AppTheme.getStockLabel(
      product.quantity,
      threshold: product.lowStockThreshold,
    );

    return Padding(
      padding: isGrid
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: GestureDetector(
        onTapDown: widget.onTap != null ? _onTapDown : null,
        onTapUp: widget.onTap != null ? _onTapUp : null,
        onTapCancel: widget.onTap != null ? _onTapCancel : null,
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: GlassCard(
            onTap: widget.onTap,
            borderRadius: 20,
            child: Row(
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: stockColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      bottomLeft: Radius.circular(20),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isGrid ? 10 : 14,
                      vertical: isGrid ? 8 : 12,
                    ),
                    child: isGrid
                        ? _buildGridContent(product, stockColor, stockLabel)
                        : _buildListContent(product, stockColor, stockLabel),
                  ),
                ),
                if (widget.onTap != null)
                  Padding(
                    padding: EdgeInsets.only(right: isGrid ? 6 : 10),
                    child: Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: AppTheme.iconMuted,
                      size: isGrid ? 12 : 16,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGridContent(
    ProductModel product,
    Color stockColor,
    String stockLabel,
  ) {
    final meta = <String>[
      stockLabel,
      if (product.categoryName.isNotEmpty) product.categoryName,
      if (product.company.isNotEmpty) product.company,
      if (product.size.isNotEmpty) product.size,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                product.name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                  height: 1.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: stockColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${product.quantity} ${product.unit}',
                style: TextStyle(
                  color: stockColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: stockColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                meta.join('  \u2022  '),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textTertiary,
                  height: 1.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildListContent(
    ProductModel product,
    Color stockColor,
    String stockLabel,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                product.name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            StockBadge(product: product),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            if (product.categoryName.isNotEmpty) ...[
              _dot(),
              Icon(
                Icons.category_outlined,
                size: 11,
                color: AppTheme.textTertiary,
              ),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  product.categoryName,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            if (product.company.isNotEmpty || product.size.isNotEmpty) ...[
              _dot(),
              Flexible(
                child: Text(
                  [
                    if (product.company.isNotEmpty) product.company,
                    if (product.size.isNotEmpty) product.size,
                  ].join(' | '),
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        Consumer<SettingsProvider>(
          builder: (context, settings, _) {
            if (!settings.pricingEnabled || product.sellingPrice <= 0) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.sell_outlined,
                    size: 11,
                    color: AppTheme.successColor,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${AppTheme.currencySymbol}${product.sellingPrice.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.successColor,
                    ),
                  ),
                  if (product.costPrice > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      'Cost: ${AppTheme.currencySymbol}${product.costPrice.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        Consumer<SettingsProvider>(
          builder: (context, settings, _) {
            if (!settings.vendorsEnabled) return const SizedBox.shrink();
            final vendorName = product.preferredVendorName.isNotEmpty
                ? product.preferredVendorName
                : product.lastVendorName;
            if (vendorName.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                children: [
                  const Icon(
                    Icons.local_shipping_outlined,
                    size: 11,
                    color: AppTheme.indigoColor,
                  ),
                  const SizedBox(width: 3),
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
        if (product.locationQuantities.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.inputFillColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 11,
                  color: AppTheme.textTertiary,
                ),
                const SizedBox(width: 3),
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
                      color: AppTheme.textTertiary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (widget.onStockIn != null || widget.onStockOut != null) ...[
          const SizedBox(height: 6),
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
                const SizedBox(width: 6),
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
    );
  }

  Widget _dot() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Text(
        '\u2022',
        style: TextStyle(fontSize: 8, color: AppTheme.iconMuted),
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
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
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
