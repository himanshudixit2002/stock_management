import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/product_model.dart';
import '../../models/stock_transaction_model.dart';
import '../../providers/product_provider.dart';
import '../../providers/stock_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';
import '../../widgets/glass_panel.dart';
import '../../config/permissions.dart';

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
    final canEditProduct = user?.hasPermission(AppPermissions.editProducts) ?? false;
    final canDeleteProduct = user?.hasPermission(AppPermissions.deleteProducts) ?? false;
    final canManageProducts = canEditProduct || canDeleteProduct;
    final perms = user?.effectivePermissions ?? {};
    final productProvider = context.watch<ProductProvider>();
    final product =
        productProvider.allProducts.cast<ProductModel?>().firstWhere(
          (p) => p!.id == widget.product.id,
          orElse: () => null,
        ) ??
        widget.product;
    final stockColor = AppTheme.getStockColor(
      product.quantity,
      threshold: product.lowStockThreshold,
    );
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Details'),
        actions: [
          if (canManageProducts) ...[
            IconButton(
              icon: const Icon(Icons.edit_rounded),
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  AppRoutes.editProduct,
                  arguments: product,
                );
              },
              tooltip: 'Edit Product',
            ),
            PopupMenuButton<String>(
              tooltip: 'More options',
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (value) {
                switch (value) {
                  case 'duplicate':
                    _duplicateProduct(context, product);
                  case 'delete':
                    _confirmDelete(context, product);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'duplicate',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.content_copy_rounded),
                    title: Text('Duplicate Product'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.delete_rounded,
                      color: AppTheme.dangerColor,
                    ),
                    title: Text(
                      'Delete Product',
                      style: TextStyle(color: AppTheme.dangerColor),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
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
            constraints: BoxConstraints(
              maxWidth: Responsive.contentMaxWidth(context),
            ),
            child: SingleChildScrollView(
              physics: Responsive.scrollPhysics(context),
              padding: EdgeInsets.fromLTRB(
                Responsive.horizontalPadding(context),
                8,
                Responsive.horizontalPadding(context),
                24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product Header
                  GlassSectionCard(
                    child: Column(
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
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineMedium,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Hero(
                                tag: 'product_qty_${product.id}',
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: stockColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          AppTheme.getStockIcon(
                                            product.quantity,
                                            threshold:
                                                product.lowStockThreshold,
                                          ),
                                          size: 16,
                                          color: stockColor,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            product.stockStatus,
                                            style: TextStyle(
                                              color: stockColor,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
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
                                label:
                                    '${product.locations.length} location${product.locations.length > 1 ? 's' : ''}',
                                color: AppTheme.primaryColor,
                              ),
                            Consumer<SettingsProvider>(
                              builder: (context, settings, _) {
                                if (!settings.vendorsEnabled) {
                                  return const SizedBox.shrink();
                                }
                                final tags = <Widget>[];
                                if (product.preferredVendorName.isNotEmpty) {
                                  tags.add(
                                    _DetailTag(
                                      icon: Icons.local_shipping_rounded,
                                      label: product.preferredVendorName,
                                      color: AppTheme.indigoColor,
                                    ),
                                  );
                                }
                                if (product.lastVendorName.isNotEmpty &&
                                    product.lastVendorName !=
                                        product.preferredVendorName) {
                                  tags.add(
                                    _DetailTag(
                                      icon: Icons.update_rounded,
                                      label: 'Last: ${product.lastVendorName}',
                                      color: AppTheme.warningColor,
                                    ),
                                  );
                                }
                                if (tags.isEmpty) {
                                  return const SizedBox.shrink();
                                }
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

                  if (product.barcode.isNotEmpty &&
                      context.watch<SettingsProvider>().barcodeEnabled) ...[
                    const SizedBox(height: 16),
                    _BarcodeCard(
                      barcode: product.barcode,
                      productName: product.name,
                    ),
                  ],

                  const SizedBox(height: 16),

                  Builder(builder: (context) {
                    final infoGrid = GlassSectionCard(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.inventory_2_rounded,
                                size: 20,
                                color: AppTheme.textSec(context),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Total Stock',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: AppTheme.textSec(context),
                                  ),
                                ),
                              ),
                              TweenAnimationBuilder<int>(
                                tween: IntTween(begin: 0, end: product.quantity),
                                duration: const Duration(milliseconds: 400),
                                curve: Curves.easeOutCubic,
                                builder: (context, value, child) {
                                  return Text(
                                    '$value ${product.unit}',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: stockColor,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Divider(height: 1),
                          ),
                          _InfoRow(
                            icon: Icons.warning_amber_rounded,
                            label: 'Low Stock Alert',
                            value: '${product.lowStockThreshold} ${product.unit}',
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
                              if (!settings.pricingEnabled) {
                                return const SizedBox.shrink();
                              }
                              return Column(
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 10),
                                    child: Divider(height: 1),
                                  ),
                                  _InfoRow(
                                    icon: Icons.money_rounded,
                                    label: 'Cost Price',
                                    value:
                                        '${AppTheme.currencySymbol}${product.costPrice.toStringAsFixed(2)}',
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 10),
                                    child: Divider(height: 1),
                                  ),
                                  _InfoRow(
                                    icon: Icons.sell_rounded,
                                    label: 'Selling Price',
                                    value:
                                        '${AppTheme.currencySymbol}${product.sellingPrice.toStringAsFixed(2)}',
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
                                      value:
                                          '${AppTheme.currencySymbol}${product.profit.toStringAsFixed(2)}',
                                      valueColor: product.profit >= 0
                                          ? AppTheme.successColor
                                          : AppTheme.dangerColor,
                                    ),
                                  ],
                                  if (product.quantity > 0 &&
                                      product.sellingPrice > 0) ...[
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 10),
                                      child: Divider(height: 1),
                                    ),
                                    _InfoRow(
                                      icon: Icons.account_balance_wallet_rounded,
                                      label: 'Total Value',
                                      value:
                                          '${AppTheme.currencySymbol}${product.totalStockValue.toStringAsFixed(2)}',
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    );

                    final hasLocations = product.locationQuantities.isNotEmpty;
                    if (Responsive.isDesktop(context) && hasLocations) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: infoGrid),
                          const SizedBox(width: 16),
                          Expanded(
                            child: GlassSectionCard(
                              title: 'Stock by Location',
                              icon: Icons.location_on_rounded,
                              iconColor: AppTheme.primaryColor,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  ...product.locationQuantities.entries.map((entry) {
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        children: [
                                          Icon(Icons.location_on_outlined, size: 16, color: AppTheme.textTer(context)),
                                          const SizedBox(width: 8),
                                          Expanded(child: Text(entry.key, style: TextStyle(fontSize: 14, color: AppTheme.textPri(context)))),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: AppTheme.getStockColor(entry.value, threshold: product.lowStockThreshold).withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              '${entry.value} ${product.unit}',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.getStockColor(entry.value, threshold: product.lowStockThreshold),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    return infoGrid;
                  }),

                  // Location Breakdown (mobile/tablet)
                  if (product.locationQuantities.isNotEmpty && !Responsive.isDesktop(context)) ...[
                    const SizedBox(height: 16),
                    GlassSectionCard(
                      title: 'Stock by Location',
                      icon: Icons.location_on_rounded,
                      iconColor: AppTheme.primaryColor,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          ...product.locationQuantities.entries.map((entry) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.place_rounded,
                                    size: 16,
                                    color: AppTheme.textSec(context),
                                  ),
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
                                        threshold: product.lowStockThreshold,
                                      ),
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
                            onTap: () => Navigator.pushNamed(
                              context,
                              AppRoutes.stockIn,
                              arguments: product,
                            ),
                          ),
                        if (perms['canStockOut'] == true)
                          _ActionButton(
                            icon: Icons.outbox_rounded,
                            label: 'Stock Out',
                            color: AppTheme.primaryColor,
                            onTap: () => Navigator.pushNamed(
                              context,
                              AppRoutes.stockOut,
                              arguments: product,
                            ),
                          ),
                        if (perms['canTransfer'] == true)
                          _ActionButton(
                            icon: Icons.swap_horiz_rounded,
                            label: 'Transfer',
                            color: AppTheme.indigoColor,
                            onTap: () => Navigator.pushNamed(
                              context,
                              AppRoutes.stockTransfer,
                              arguments: product,
                            ),
                          ),
                        if (perms['canDamage'] == true)
                          _ActionButton(
                            icon: Icons.report_problem_rounded,
                            label: 'Damage',
                            color: AppTheme.dangerColor,
                            onTap: () => Navigator.pushNamed(
                              context,
                              AppRoutes.damageReport,
                              arguments: product,
                            ),
                          ),
                        if (perms['canAdjustStock'] == true)
                          _ActionButton(
                            icon: Icons.tune_rounded,
                            label: 'Adjust',
                            color: AppTheme.warningColor,
                            onTap: () => Navigator.pushNamed(
                              context,
                              AppRoutes.stockAdjustment,
                              arguments: product,
                            ),
                          ),
                      ];

                      if (actions.isEmpty) return const SizedBox.shrink();

                      if (constraints.maxWidth < 400) {
                        final itemWidth = (constraints.maxWidth - 8) / 2;
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: actions
                              .map((a) => SizedBox(width: itemWidth, child: a))
                              .toList(),
                        );
                      }

                      return Row(
                        children:
                            actions
                                .expand(
                                  (a) => [
                                    Expanded(child: a),
                                    const SizedBox(width: 8),
                                  ],
                                )
                                .toList()
                              ..removeLast(),
                      );
                    },
                  ),

                  const SizedBox(height: 28),

                  // Transaction History
                  Row(
                    children: [
                      Text(
                        'Stock History',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppRoutes.transactionHistory,
                        ),
                        child: Text(
                          'View All',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  StreamBuilder<List<StockTransactionModel>>(
                    stream: context
                        .read<StockProvider>()
                        .getProductTransactions(product.id),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      final transactions = snapshot.data ?? [];

                      if (transactions.isEmpty) {
                        return GlassSectionCard(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 36),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.history_rounded,
                                  size: 44,
                                  color: AppTheme.iconMute(context),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'No transactions yet',
                                  style: TextStyle(
                                    color: AppTheme.textTer(context),
                                  ),
                                ),
                              ],
                            ),
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
                            case TransactionType.adjustment:
                              typeColor = AppTheme.warningColor;
                              typeIcon = Icons.tune_rounded;
                              break;
                          }

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: GlassCard(
                              borderRadius: 14,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: typeColor.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        typeIcon,
                                        color: typeColor,
                                        size: 20,
                                      ),
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
                                              if (t.userName.isNotEmpty)
                                                'By ${t.userName}',
                                              if (t.location.isNotEmpty)
                                                t.location,
                                              dateFormat.format(t.date),
                                            ].join(' \u2022 '),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.textSec(context),
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
                                                color: AppTheme.textTer(
                                                  context,
                                                ),
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
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  // Audit info - who added/updated and when
                  GlassSectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.createdByName.isNotEmpty
                              ? 'Added by ${product.createdByName} on ${dateFormat.format(product.createdAt)}'
                              : 'Created: ${dateFormat.format(product.createdAt)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textTer(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          product.updatedByName.isNotEmpty
                              ? 'Last updated by ${product.updatedByName} on ${dateFormat.format(product.updatedAt)}'
                              : 'Updated: ${dateFormat.format(product.updatedAt)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textTer(context),
                          ),
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

  void _duplicateProduct(BuildContext context, ProductModel product) {
    final template = product.copyWith(
      id: '',
      name: '${product.name} (Copy)',
      quantity: 0,
      locationQuantities: {},
    );
    Navigator.pushNamed(context, AppRoutes.addProduct, arguments: template);
  }

  void _confirmDelete(BuildContext context, ProductModel product) {
    bool isDeleting = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Delete Product'),
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
                        showSuccessSnackBar(context, 'Product deleted');
                        Navigator.pop(context);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.dangerColor,
              ),
              child: isDeleting
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.surface(context),
                      ),
                    )
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

  const _DetailTag({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.textSec(context);
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
        Icon(icon, size: 20, color: AppTheme.textSec(context)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 14, color: AppTheme.textSec(context)),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: valueColor ?? AppTheme.textPri(context),
          ),
        ),
      ],
    );
  }
}

class _BarcodeCard extends StatefulWidget {
  final String barcode;
  final String productName;
  const _BarcodeCard({required this.barcode, required this.productName});

  @override
  State<_BarcodeCard> createState() => _BarcodeCardState();
}

class _BarcodeCardState extends State<_BarcodeCard> {
  final _repaintKey = GlobalKey();
  bool _saving = false;

  Future<void> _saveAndShare() async {
    setState(() => _saving = true);
    try {
      final boundary =
          _repaintKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/barcode_${widget.barcode}.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: '${widget.productName} — Barcode: ${widget.barcode}',
        sharePositionOrigin: box != null
            ? box.localToGlobal(Offset.zero) & box.size
            : null,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save barcode: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.qr_code_rounded,
                size: 18,
                color: AppTheme.textSec(context),
              ),
              const SizedBox(width: 8),
              Text(
                'Barcode',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSec(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          RepaintBoundary(
            key: _repaintKey,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  SizedBox(
                    height: 50,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(widget.barcode.length * 3, (i) {
                        final isThick = i % 3 == 0;
                        return Container(
                          width: isThick ? 2.5 : 1.0,
                          margin: const EdgeInsets.symmetric(horizontal: 0.8),
                          color: Colors.black.withValues(
                            alpha: i % 5 == 0 ? 0.9 : 0.6,
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.barcode,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 3,
                      fontFamily: 'monospace',
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: widget.barcode));
                    HapticFeedback.selectionClick();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Barcode copied to clipboard'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _saveAndShare,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.download_rounded, size: 16),
                  label: Text(_saving ? 'Saving...' : 'Save'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
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
            Icon(icon, color: AppTheme.surface(context), size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: AppTheme.surface(context),
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
