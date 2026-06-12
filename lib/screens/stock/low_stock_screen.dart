import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../models/product_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/animated_list_item.dart';

class LowStockScreen extends StatelessWidget {
  const LowStockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final productProvider = context.watch<ProductProvider>();
    final analyticsProducts = productProvider.analyticsProducts;
    final lowStock =
        analyticsProducts
            .where((p) => p.quantity <= p.lowStockThreshold)
            .toList()
          ..sort((a, b) {
            final aRatio = a.lowStockThreshold > 0
                ? a.quantity / a.lowStockThreshold
                : 0.0;
            final bRatio = b.lowStockThreshold > 0
                ? b.quantity / b.lowStockThreshold
                : 0.0;
            return aRatio.compareTo(bRatio);
          });

    final outOfStock = lowStock.where((p) => p.isOutOfStock).length;
    final critical = lowStock.where((p) => !p.isOutOfStock).length;

    return AppScreenScaffold(
      icon: Icons.warning_amber_rounded,
      iconColor: AppTheme.warningColor,
      title: 'Low Stock Alerts',
      isLoading: productProvider.isLoadingAnalytics,
      body: lowStock.isEmpty
          ? const EmptyStateWidget(
              icon: Icons.check_circle_outline_rounded,
              title: 'All Stocked Up!',
              subtitle: 'All products are above their low stock threshold.',
            )
          : Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: Responsive.horizontalPadding(context),
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      _SummaryChip(
                        label: '$outOfStock Out of Stock',
                        color: AppTheme.dangerColor,
                      ),
                      const SizedBox(width: 8),
                      _SummaryChip(
                        label: '$critical Low Stock',
                        color: AppTheme.warningColor,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => productProvider.loadAnalytics(),
                    child: ListView.builder(
                      padding: EdgeInsets.symmetric(
                        horizontal: Responsive.horizontalPadding(context),
                      ),
                      itemCount: lowStock.length,
                      itemBuilder: (context, index) {
                        final product = lowStock[index];
                        return AnimatedListItem(
                          index: index,
                          child: _LowStockTile(product: product),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final Color color;
  const _SummaryChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _LowStockTile extends StatelessWidget {
  final ProductModel product;
  const _LowStockTile({required this.product});

  @override
  Widget build(BuildContext context) {
    final color = product.isOutOfStock
        ? AppTheme.dangerColor
        : AppTheme.warningColor;
    final ratio = product.lowStockThreshold > 0
        ? (product.quantity / product.lowStockThreshold).clamp(0.0, 1.0)
        : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        borderRadius: 20,
        onTap: () => Navigator.pushNamed(
          context,
          AppRoutes.productDetail,
          arguments: product,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      product.isOutOfStock
                          ? Icons.error_rounded
                          : Icons.warning_rounded,
                      color: color,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${product.quantity} / ${product.lowStockThreshold} ${product.unit}',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (context.watch<AuthProvider>().currentUser?.hasPermission(
                        AppPermissions.stockIn,
                      ) ??
                      false) ...[
                    const SizedBox(width: 8),
                    _ActionButton(
                      icon: Icons.add_rounded,
                      label: 'Stock In',
                      onTap: () => Navigator.pushNamed(
                        context,
                        AppRoutes.stockIn,
                        arguments: product,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  backgroundColor: color.withValues(alpha: 0.1),
                  color: color,
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.primaryColor.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppTheme.primaryColor),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
