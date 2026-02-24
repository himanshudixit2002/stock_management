import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/product_model.dart';
import '../../models/stock_transaction_model.dart';
import '../../providers/product_provider.dart';
import '../../providers/stock_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../config/theme.dart';
import '../../utils/responsive.dart';

class ProductDetailScreen extends StatefulWidget {
  final ProductModel product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final canManageProducts = user?.hasPermission('canManageProducts') ?? false;
    final perms = user?.effectivePermissions ?? {};
    final productProvider = context.watch<ProductProvider>();
    final product = productProvider.allProducts.cast<ProductModel?>().firstWhere(
      (p) => p!.id == widget.product.id,
      orElse: () => null,
    ) ?? widget.product;
    final stockColor = AppTheme.getStockColor(product.quantity,
        threshold: product.lowStockThreshold);
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.info_rounded, color: AppTheme.primaryColor, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Product Details'),
          ],
        ),
        actions: [
          if (canManageProducts) ...[
            IconButton(
              icon: const Icon(Icons.edit_rounded),
              onPressed: () {
                Navigator.pushNamed(context, '/products/edit',
                    arguments: product);
              },
              tooltip: 'Edit Product',
            ),
            IconButton(
              icon: Icon(Icons.delete_rounded,
                  color: AppTheme.dangerColor.withValues(alpha: 0.8)),
              onPressed: () => _confirmDelete(context, product),
              tooltip: 'Delete Product',
            ),
          ],
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          final companyId = context.read<ProductProvider>().companyId;
          context.read<ProductProvider>().initialize(companyId: companyId);
          context.read<StockProvider>().initialize(companyId: companyId);
        },
        child: Center(
        child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: Responsive.contentMaxWidth(context)),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            Responsive.horizontalPadding(context), 8,
            Responsive.horizontalPadding(context), 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Hero(
                          tag: 'product-name-${widget.product.id}',
                          child: Material(
                            color: Colors.transparent,
                            child: Text(
                              product.name,
                              style:
                                  Theme.of(context).textTheme.headlineMedium,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: stockColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              AppTheme.getStockIcon(product.quantity,
                                  threshold:
                                      product.lowStockThreshold),
                              size: 16,
                              color: stockColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              product.stockStatus,
                              style: TextStyle(
                                color: stockColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Tags
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _DetailTag(
                        icon: Icons.category_rounded,
                        label: product.categoryName.isEmpty
                            ? 'No Category'
                            : product.categoryName,
                      ),
                      if (product.company.isNotEmpty)
                        _DetailTag(
                          icon: Icons.business_rounded,
                          label: product.company,
                          color: AppTheme.indigoColor,
                        ),
                      if (product.size.isNotEmpty)
                        _DetailTag(
                          icon: Icons.straighten_rounded,
                          label: product.size,
                          color: AppTheme.infoColor,
                        ),
                      if (product.locations.isNotEmpty)
                        _DetailTag(
                          icon: Icons.location_on_rounded,
                          label: '${product.locations.length} location${product.locations.length > 1 ? 's' : ''}',
                          color: AppTheme.primaryColor,
                        ),
                      Consumer<SettingsProvider>(
                        builder: (context, settings, _) {
                          if (!settings.vendorsEnabled) return const SizedBox.shrink();
                          final tags = <Widget>[];
                          if (product.preferredVendorName.isNotEmpty) {
                            tags.add(_DetailTag(
                              icon: Icons.local_shipping_rounded,
                              label: product.preferredVendorName,
                              color: AppTheme.indigoColor,
                            ));
                          }
                          if (product.lastVendorName.isNotEmpty &&
                              product.lastVendorName != product.preferredVendorName) {
                            tags.add(_DetailTag(
                              icon: Icons.update_rounded,
                              label: 'Last: ${product.lastVendorName}',
                              color: AppTheme.warningColor,
                            ));
                          }
                          if (tags.isEmpty) return const SizedBox.shrink();
                          return Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: tags,
                          );
                        },
                      ),
                    ],
                  ),
                  if (product.description.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      product.description,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Info Grid
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.dividerColor),
              ),
              child: Column(
                children: [
                  _InfoRow(
                    icon: Icons.inventory_2_rounded,
                    label: 'Total Stock',
                    value: '${product.quantity} ${product.unit}',
                    valueColor: stockColor,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1),
                  ),
                  _InfoRow(
                    icon: Icons.warning_amber_rounded,
                    label: 'Low Stock Alert',
                    value:
                        '${product.lowStockThreshold} ${product.unit}',
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1),
                  ),
                  _InfoRow(
                    icon: Icons.straighten_rounded,
                    label: 'Unit',
                    value: product.unit,
                  ),
                  Consumer<SettingsProvider>(
                    builder: (context, settings, _) {
                      if (!settings.pricingEnabled) return const SizedBox.shrink();
                      return Column(
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Divider(height: 1),
                          ),
                          _InfoRow(
                            icon: Icons.money_rounded,
                            label: 'Cost Price',
                            value: '\u20B9${product.costPrice.toStringAsFixed(2)}',
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Divider(height: 1),
                          ),
                          _InfoRow(
                            icon: Icons.sell_rounded,
                            label: 'Selling Price',
                            value: '\u20B9${product.sellingPrice.toStringAsFixed(2)}',
                            valueColor: AppTheme.successColor,
                          ),
                          if (product.profit != 0) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Divider(height: 1),
                            ),
                            _InfoRow(
                              icon: Icons.trending_up_rounded,
                              label: 'Profit / Unit',
                              value: '\u20B9${product.profit.toStringAsFixed(2)}',
                              valueColor: product.profit >= 0
                                  ? AppTheme.successColor
                                  : AppTheme.dangerColor,
                            ),
                          ],
                          if (product.quantity > 0 && product.sellingPrice > 0) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Divider(height: 1),
                            ),
                            _InfoRow(
                              icon: Icons.account_balance_wallet_rounded,
                              label: 'Total Value',
                              value: '\u20B9${product.totalStockValue.toStringAsFixed(2)}',
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),

            // Location Breakdown
            if (product.locationQuantities.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.dividerColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.location_on_rounded,
                            size: 20, color: AppTheme.primaryColor),
                        const SizedBox(width: 8),
                        const Text(
                          'Stock by Location',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...product.locationQuantities.entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(Icons.place_rounded,
                                size: 16,
                                color: AppTheme.textSecondary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                entry.key,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            Text(
                              '${entry.value} ${product.unit}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: AppTheme.getStockColor(
                                    entry.value,
                                    threshold:
                                        product.lowStockThreshold),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Quick Actions
            LayoutBuilder(
              builder: (context, constraints) {
                final actions = <Widget>[
                  if (perms['canStockIn'] == true)
                    _ActionButton(
                      icon: Icons.add_box_rounded,
                      label: 'Stock In',
                      color: AppTheme.successColor,
                      onTap: () => Navigator.pushNamed(context, '/stock/in', arguments: product),
                    ),
                  if (perms['canStockOut'] == true)
                    _ActionButton(
                      icon: Icons.outbox_rounded,
                      label: 'Stock Out',
                      color: AppTheme.primaryColor,
                      onTap: () => Navigator.pushNamed(context, '/stock/out', arguments: product),
                    ),
                  if (perms['canTransfer'] == true)
                    _ActionButton(
                      icon: Icons.swap_horiz_rounded,
                      label: 'Transfer',
                      color: AppTheme.indigoColor,
                      onTap: () => Navigator.pushNamed(context, '/stock/transfer', arguments: product),
                    ),
                  if (perms['canDamage'] == true)
                    _ActionButton(
                      icon: Icons.report_problem_rounded,
                      label: 'Damage',
                      color: AppTheme.dangerColor,
                      onTap: () => Navigator.pushNamed(context, '/stock/damage', arguments: product),
                    ),
                ];

                if (actions.isEmpty) return const SizedBox.shrink();

                if (constraints.maxWidth < 400) {
                  final itemWidth = (constraints.maxWidth - 8) / 2;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: actions.map((a) => SizedBox(width: itemWidth, child: a)).toList(),
                  );
                }

                return Row(
                  children: actions
                      .expand((a) => [Expanded(child: a), const SizedBox(width: 8)])
                      .toList()
                    ..removeLast(),
                );
              },
            ),

            const SizedBox(height: 28),

            // Transaction History
            Text(
              'Stock History',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),

            StreamBuilder<List<StockTransactionModel>>(
              stream: context
                  .read<StockProvider>()
                  .getProductTransactions(product.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                      child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ));
                }

                final transactions = snapshot.data ?? [];

                if (transactions.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor,
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: AppTheme.dividerColor),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.history_rounded,
                            size: 44, color: Colors.grey[350]),
                        const SizedBox(height: 8),
                        Text(
                          'No transactions yet',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  children: transactions.map((t) {
                    Color typeColor;
                    IconData typeIcon;

                    switch (t.type) {
                      case TransactionType.stockIn:
                        typeColor = AppTheme.successColor;
                        typeIcon = Icons.add_circle_rounded;
                        break;
                      case TransactionType.stockOut:
                        typeColor = AppTheme.primaryColor;
                        typeIcon = Icons.remove_circle_rounded;
                        break;
                      case TransactionType.damage:
                        typeColor = AppTheme.dangerColor;
                        typeIcon = Icons.report_problem_rounded;
                        break;
                      case TransactionType.transfer:
                        typeColor = AppTheme.indigoColor;
                        typeIcon = Icons.swap_horiz_rounded;
                        break;
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppTheme.dividerColor),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: typeColor
                                  .withValues(alpha: 0.12),
                              borderRadius:
                                  BorderRadius.circular(10),
                            ),
                            child: Icon(typeIcon,
                                color: typeColor, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.typeLabel,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    if (t.userName.isNotEmpty) 'By ${t.userName}',
                                    if (t.location.isNotEmpty) t.location,
                                    dateFormat.format(t.date),
                                  ].join(' \u2022 '),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color:
                                        AppTheme.textSecondary,
                                  ),
                                ),
                                if (t.vendorName.isNotEmpty)
                                  Text(
                                    'Vendor: ${t.vendorName}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.indigoColor,
                                    ),
                                  ),
                                if (t.reason.isNotEmpty)
                                  Text(
                                    t.reason,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            t.type == TransactionType.stockIn
                                ? '+${t.quantity}'
                                : t.type == TransactionType.transfer
                                    ? '${t.quantity}'
                                    : '-${t.quantity}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                              color: typeColor,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),

            const SizedBox(height: 20),

            // Audit info - who added/updated and when
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F7FA),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.createdByName.isNotEmpty
                        ? 'Added by ${product.createdByName} on ${dateFormat.format(product.createdAt)}'
                        : 'Created: ${dateFormat.format(product.createdAt)}',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    product.updatedByName.isNotEmpty
                        ? 'Last updated by ${product.updatedByName} on ${dateFormat.format(product.updatedAt)}'
                        : 'Updated: ${dateFormat.format(product.updatedAt)}',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
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

  void _confirmDelete(BuildContext context, ProductModel product) {
    bool isDeleting = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.dangerColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.delete_forever_rounded,
                  color: AppTheme.dangerColor, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Delete Product'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${product.name}"? This will also delete all stock history. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: isDeleting
                ? null
                : () async {
                    setDialogState(() => isDeleting = true);
                    HapticFeedback.heavyImpact();
                    final success = await context
                        .read<ProductProvider>()
                        .deleteProduct(product.id);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (success && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Product deleted'),
                          backgroundColor: AppTheme.successColor,
                          duration: Duration(seconds: 4),
                        ),
                      );
                      Navigator.pop(context);
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.dangerColor,
            ),
            child: isDeleting
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Delete'),
          ),
        ],
      ),
      ),
    );
  }
}

class _DetailTag extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _DetailTag({
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: c,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppTheme.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: valueColor ?? AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
