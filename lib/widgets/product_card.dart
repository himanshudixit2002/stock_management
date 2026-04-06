import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/product_model.dart';
import '../providers/settings_provider.dart';
import '../providers/favorites_provider.dart';
import '../config/routes.dart';
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
  Offset? _longPressPosition;

  void _onTapDown(_) => setState(() => _scale = 0.97);
  void _onTapUp(_) => setState(() => _scale = 1.0);
  void _onTapCancel() => setState(() => _scale = 1.0);

  Future<void> _onLongPress() async {
    if (_longPressPosition == null) return;
    final overlay =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final product = widget.product;
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(_longPressPosition!.dx, _longPressPosition!.dy, 1, 1),
      Offset.zero & overlay.size,
    );
    final chosen = await showMenu<int>(
      context: context,
      position: position,
      items: [
        PopupMenuItem<int>(
          value: 0,
          child: Row(
            children: [
              const Icon(Icons.edit_rounded),
              const SizedBox(width: 12),
              const Text('Edit'),
            ],
          ),
        ),
        PopupMenuItem<int>(
          value: 1,
          child: Row(
            children: [
              const Icon(Icons.add_circle_rounded),
              const SizedBox(width: 12),
              const Text('Stock In'),
            ],
          ),
        ),
        PopupMenuItem<int>(
          value: 2,
          child: Row(
            children: [
              const Icon(Icons.remove_circle_rounded),
              const SizedBox(width: 12),
              const Text('Stock Out'),
            ],
          ),
        ),
        PopupMenuItem<int>(
          value: 3,
          child: Row(
            children: [
              Icon(
                context.read<FavoritesProvider>().isFavorite(product.id)
                    ? Icons.favorite
                    : Icons.favorite_border,
              ),
              const SizedBox(width: 12),
              Text(
                context.read<FavoritesProvider>().isFavorite(product.id)
                    ? 'Remove from Favorites'
                    : 'Add to Favorites',
              ),
            ],
          ),
        ),
      ],
    );
    if (!mounted) return;
    switch (chosen) {
      case 0:
        Navigator.pushNamed(context, AppRoutes.editProduct, arguments: product);
        break;
      case 1:
        Navigator.pushNamed(context, AppRoutes.stockIn, arguments: product);
        break;
      case 2:
        Navigator.pushNamed(context, AppRoutes.stockOut, arguments: product);
        break;
      case 3:
        context.read<FavoritesProvider>().toggle(product.id);
        break;
    }
  }

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

    return Dismissible(
      key: ValueKey(product.id),
      direction: DismissDirection.horizontal,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(
          color: AppTheme.successColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Icon(Icons.add_circle_rounded, color: Colors.white, size: 24),
            SizedBox(width: 8),
            Text(
              'Stock In',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'Stock Out',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.remove_circle_rounded, color: Colors.white, size: 24),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        HapticFeedback.mediumImpact();
        if (direction == DismissDirection.startToEnd) {
          Navigator.pushNamed(context, AppRoutes.stockIn, arguments: product);
        } else {
          Navigator.pushNamed(context, AppRoutes.stockOut, arguments: product);
        }
        return false;
      },
      child: Padding(
        padding: isGrid
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: GestureDetector(
          onTapDown: widget.onTap != null ? _onTapDown : null,
          onTapUp: widget.onTap != null ? _onTapUp : null,
          onTapCancel: widget.onTap != null ? _onTapCancel : null,
          onLongPressDown: (details) => _longPressPosition = details.globalPosition,
          onLongPress: _onLongPress,
          child: AnimatedScale(
            scale: _scale,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: GlassCard(
              onTap: widget.onTap,
              borderRadius: 16,
              child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isGrid ? 8 : 10,
                      vertical: isGrid ? 6 : 8,
                    ),
                    child: isGrid
                        ? _buildGridContent(product, stockColor, stockLabel)
                        : _buildListContent(product, stockColor, stockLabel),
                  ),
                ),
                if (widget.onTap != null)
                  Padding(
                    padding: EdgeInsets.only(right: isGrid ? 6 : 8),
                    child: Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: AppTheme.iconMute(context),
                      size: isGrid ? 12 : 16,
                  ),
                ),
              ],
            ),
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
              child: Hero(
                tag: 'product_name_${product.id}',
                child: Material(
                  type: MaterialType.transparency,
                  child: Text(
                    product.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPri(context),
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Hero(
              tag: 'product_qty_${product.id}',
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: stockColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${product.quantity} ${product.unit}',
                    style: TextStyle(
                      color: stockColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
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
                  color: AppTheme.textTer(context),
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
              child: Hero(
                tag: 'product_name_${product.id}',
                child: Material(
                  type: MaterialType.transparency,
                  child: Text(
                    product.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPri(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: stockColor,
                shape: BoxShape.circle,
              ),
            ),
            Hero(
              tag: 'product_qty_${product.id}',
              child: Material(
                type: MaterialType.transparency,
                child: StockBadge(product: product),
              ),
            ),
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
                color: AppTheme.textTer(context),
              ),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  product.categoryName,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textTer(context),
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
                    color: AppTheme.textTer(context),
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
            final parts = <InlineSpan>[];
            if (settings.pricingEnabled && product.sellingPrice > 0) {
              parts.add(TextSpan(
                text: '${AppTheme.currencySymbol}${product.sellingPrice.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.successColor,
                ),
              ));
            }
            if (settings.vendorsEnabled) {
              final vendorName = product.preferredVendorName.isNotEmpty
                  ? product.preferredVendorName
                  : product.lastVendorName;
              if (vendorName.isNotEmpty) {
                if (parts.isNotEmpty) {
                  parts.add(TextSpan(
                    text: '  \u00B7  ',
                    style: TextStyle(fontSize: 11, color: AppTheme.textTer(context)),
                  ));
                }
                parts.add(TextSpan(
                  text: vendorName,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.indigoColor,
                  ),
                ));
              }
            }
            if (parts.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text.rich(
                TextSpan(children: parts),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          },
        ),
        if (product.locationQuantities.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.inputFill(context),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 11,
                  color: AppTheme.textTer(context),
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
                      color: AppTheme.textTer(context),
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
                const SizedBox(width: 4),
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
        style: TextStyle(fontSize: 8, color: AppTheme.iconMute(context)),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
