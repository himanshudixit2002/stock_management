import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../config/theme.dart';
import '../../models/vendor_model.dart';
import '../../models/stock_transaction_model.dart';
import '../../models/product_model.dart';
import '../../providers/vendor_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/stock_provider.dart';
import '../../utils/responsive.dart';
import '../../utils/dialogs.dart';
// Vendor routes registered in app.dart onGenerateRoute

class VendorDetailScreen extends StatefulWidget {
  final VendorModel vendor;
  const VendorDetailScreen({super.key, required this.vendor});

  @override
  State<VendorDetailScreen> createState() => _VendorDetailScreenState();
}

class _VendorDetailScreenState extends State<VendorDetailScreen> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    final vendorProvider = context.watch<VendorProvider>();
    final productProvider = context.watch<ProductProvider>();
    final stockProvider = context.watch<StockProvider>();

    final vendor = vendorProvider.getVendorById(widget.vendor.id) ?? widget.vendor;
    final allProducts = productProvider.allProducts;
    final allTransactions = stockProvider.allTransactions;

    final scorecard = vendorProvider.vendorScorecard(vendor.id, allTransactions);
    final linkedProducts = allProducts
        .where((p) => p.preferredVendorId == vendor.id)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(vendor.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            onPressed: () => Navigator.pushNamed(context, '/vendors/edit', arguments: vendor),
          ),
          IconButton(
            icon: const Icon(Icons.delete_rounded),
            onPressed: () => _confirmDelete(context, vendor),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: Responsive.contentMaxWidth(context)),
        child: ListView(
        padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
        children: [
          _buildInfoCard(vendor),
          const SizedBox(height: 16),
          _buildScorecardSection(scorecard),
          const SizedBox(height: 16),
          _buildLinkedProductsSection(linkedProducts, allProducts, vendor),
          const SizedBox(height: 16),
          _buildPurchaseOrderSection(vendor, allProducts),
          const SizedBox(height: 16),
          _buildRecentTransactionsSection(vendor.id),
        ],
      ),
      ),
      ),
    );
  }

  Widget _buildInfoCard(VendorModel vendor) {
    return Container(
      decoration: AppTheme.cardDecoration,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppTheme.indigoColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.local_shipping_rounded,
                    color: AppTheme.indigoColor, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(vendor.name,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: vendor.isActive
                                ? AppTheme.successColor.withValues(alpha: 0.1)
                                : Colors.grey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            vendor.isActive ? 'Active' : 'Inactive',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: vendor.isActive
                                  ? AppTheme.successColor
                                  : Colors.grey,
                            ),
                          ),
                        ),
                        if (vendor.rating > 0) ...[
                          const SizedBox(width: 8),
                          ...List.generate(5, (i) {
                            return Icon(
                              i < vendor.rating.round()
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 16,
                              color: i < vendor.rating.round()
                                  ? AppTheme.warningColor
                                  : Colors.grey[300],
                            );
                          }),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (vendor.contactName.isNotEmpty)
            _infoRow(Icons.person_outline_rounded, 'Contact', vendor.contactName),
          if (vendor.email.isNotEmpty)
            _infoRow(Icons.email_outlined, 'Email', vendor.email),
          if (vendor.phone.isNotEmpty)
            _infoRow(Icons.phone_outlined, 'Phone', vendor.phone),
          if (vendor.address.isNotEmpty)
            _infoRow(Icons.location_on_outlined, 'Address', vendor.address),
          if (vendor.leadTimeDays > 0)
            _infoRow(Icons.schedule_rounded, 'Lead Time',
                '${vendor.leadTimeDays} days'),
          if (vendor.notes.isNotEmpty)
            _infoRow(Icons.notes_rounded, 'Notes', vendor.notes),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey[500]),
          const SizedBox(width: 10),
          SizedBox(
            width: 70,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: Colors.grey[500])),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildScorecardSection(Map<String, dynamic> scorecard) {
    final totalTxns = scorecard['totalTransactions'] as int;
    final totalQty = scorecard['totalQuantity'] as int;
    final lastDate = scorecard['lastTransactionDate'] as DateTime?;

    return Container(
      decoration: AppTheme.cardDecoration,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics_rounded,
                  color: AppTheme.indigoColor, size: 20),
              const SizedBox(width: 8),
              const Text('Scorecard',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 360) {
                return Column(
                  children: [
                    _scorecardContent('Transactions', totalTxns.toString(), AppTheme.infoColor),
                    const SizedBox(height: 8),
                    _scorecardContent('Units Supplied', totalQty.toString(), AppTheme.successColor),
                    const SizedBox(height: 8),
                    _scorecardContent(
                      'Last Delivery',
                      lastDate != null ? DateFormat('MMM d').format(lastDate) : 'N/A',
                      AppTheme.warningColor,
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  _scorecardTile('Transactions', totalTxns.toString(), AppTheme.infoColor),
                  const SizedBox(width: 12),
                  _scorecardTile('Units Supplied', totalQty.toString(), AppTheme.successColor),
                  const SizedBox(width: 12),
                  _scorecardTile(
                    'Last Delivery',
                    lastDate != null ? DateFormat('MMM d').format(lastDate) : 'N/A',
                    AppTheme.warningColor,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _scorecardTile(String label, String value, Color color) {
    return Expanded(
      child: _scorecardContent(label, value, color),
    );
  }

  Widget _scorecardContent(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildLinkedProductsSection(
    List<ProductModel> linkedProducts,
    List<ProductModel> allProducts,
    VendorModel vendor,
  ) {
    return Container(
      decoration: AppTheme.cardDecoration,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_rounded,
                  color: AppTheme.primaryColor, size: 20),
              const SizedBox(width: 8),
              Text('Linked Products (${linkedProducts.length})',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton.icon(
                onPressed: () =>
                    _showBulkAssignSheet(context, allProducts, vendor),
                icon: const Icon(Icons.link_rounded, size: 16),
                label: const Text('Assign', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (linkedProducts.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('No products linked to this vendor',
                    style: TextStyle(fontSize: 13, color: Colors.grey[500])),
              ),
            )
          else
            ...linkedProducts.take(10).map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: p.isOutOfStock
                              ? AppTheme.dangerColor
                              : p.isLowStock
                                  ? AppTheme.warningColor
                                  : AppTheme.successColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(p.name,
                            style: const TextStyle(fontSize: 13)),
                      ),
                      Text('${p.quantity} ${p.unit}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                )),
          if (linkedProducts.length > 10)
            Center(
              child: Text(
                '+${linkedProducts.length - 10} more',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPurchaseOrderSection(
    VendorModel vendor,
    List<ProductModel> allProducts,
  ) {
    final vendorProvider = context.read<VendorProvider>();
    final poItems = vendorProvider.generatePurchaseOrderDraft(vendor.id, allProducts);

    return Container(
      decoration: AppTheme.cardDecoration,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded,
                  color: AppTheme.warningColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Purchase Order Draft (${poItems.length})',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              if (poItems.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _exportPurchaseOrder(vendor, poItems),
                  icon: const Icon(Icons.file_download_outlined, size: 16),
                  label: const Text('Export', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (poItems.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('No low stock items for this vendor',
                    style: TextStyle(fontSize: 13, color: Colors.grey[500])),
              ),
            )
          else
            ...poItems.take(10).map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppTheme.warningColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(item['productName'] as String,
                            style: const TextStyle(fontSize: 13)),
                      ),
                      Text(
                        '${item['currentQty']}/${item['threshold']} ${item['unit']}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.warningColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Order ${item['suggestedOrderQty']}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.warningColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  Future<void> _exportPurchaseOrder(
    VendorModel vendor,
    List<Map<String, dynamic>> items,
  ) async {
    try {
      final buffer = StringBuffer();
      buffer.writeln('Purchase Order Draft - ${vendor.name}');
      buffer.writeln('Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}');
      buffer.writeln('');
      buffer.writeln('Product,Current Qty,Threshold,Suggested Order,Unit');
      for (final item in items) {
        buffer.writeln(
            '${item['productName']},${item['currentQty']},${item['threshold']},${item['suggestedOrderQty']},${item['unit']}');
      }

      final dir = await getTemporaryDirectory();
      if (!mounted) return;
      final file = File(
          '${dir.path}/PO_${vendor.name.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv');
      await file.writeAsString(buffer.toString());
      if (!mounted) return;

      await Share.shareXFiles([XFile(file.path)],
          text: 'Purchase Order Draft for ${vendor.name}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export: $e'),
            backgroundColor: AppTheme.dangerColor,
          ),
        );
      }
    }
  }

  Widget _buildRecentTransactionsSection(String vendorId) {
    return Container(
      decoration: AppTheme.cardDecoration,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.receipt_long_rounded,
                  color: AppTheme.warningColor, size: 20),
              SizedBox(width: 8),
              Text('Recent Transactions',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          StreamBuilder<List<StockTransactionModel>>(
            stream: context.read<VendorProvider>().getVendorTransactions(vendorId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ));
              }
              final txns = snapshot.data ?? [];
              if (txns.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('No transactions yet',
                        style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                  ),
                );
              }
              return Column(
                children: txns.take(15).map((t) {
                  final isIn = t.type == TransactionType.stockIn;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          isIn
                              ? Icons.arrow_downward_rounded
                              : Icons.arrow_upward_rounded,
                          size: 16,
                          color: isIn
                              ? AppTheme.successColor
                              : AppTheme.dangerColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(t.productName,
                              style: const TextStyle(fontSize: 13)),
                        ),
                        Text('${t.quantity}',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isIn
                                    ? AppTheme.successColor
                                    : AppTheme.dangerColor)),
                        const SizedBox(width: 8),
                        Text(DateFormat('MMM d').format(t.date),
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500])),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showBulkAssignSheet(
    BuildContext parentCtx,
    List<ProductModel> allProducts,
    VendorModel vendor,
  ) {
    final selectedIds = <String>{};
    for (final p in allProducts) {
      if (p.preferredVendorId == vendor.id) {
        selectedIds.add(p.id);
      }
    }

    showModalBottomSheet(
      context: parentCtx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (_, controller) {
                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.link_rounded,
                              color: AppTheme.indigoColor),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Assign Products to ${vendor.name}',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final toAssign = selectedIds.toList();
                              Navigator.pop(ctx);
                              if (toAssign.isNotEmpty) {
                                final ok = await parentCtx
                                    .read<VendorProvider>()
                                    .bulkAssignVendor(
                                      productIds: toAssign,
                                      vendorId: vendor.id,
                                      vendorName: vendor.name,
                                    );
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(ok
                                          ? '${toAssign.length} products assigned'
                                          : 'Failed to assign products'),
                                      backgroundColor: ok
                                          ? AppTheme.successColor
                                          : AppTheme.dangerColor,
                                    ),
                                  );
                                }
                              }
                            },
                            child: Text('Save (${selectedIds.length})'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        controller: controller,
                        itemCount: allProducts.length,
                        itemBuilder: (_, i) {
                          final p = allProducts[i];
                          final isSelected = selectedIds.contains(p.id);
                          return CheckboxListTile(
                            title: Text(p.name,
                                style: const TextStyle(fontSize: 14)),
                            subtitle: Text(
                              [p.categoryName, if (p.company.isNotEmpty) p.company].join(' | '),
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[500]),
                            ),
                            value: isSelected,
                            onChanged: (v) {
                              setSheetState(() {
                                if (v == true) {
                                  selectedIds.add(p.id);
                                } else {
                                  selectedIds.remove(p.id);
                                }
                              });
                            },
                            dense: true,
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _confirmDelete(BuildContext ctx, VendorModel vendor) async {
    if (_isProcessing) return;
    final confirmed = await showConfirmDialog(
      ctx,
      title: 'Delete Vendor',
      message: 'Are you sure you want to delete "${vendor.name}"? This cannot be undone.',
      confirmLabel: 'Delete',
      icon: Icons.delete_forever_rounded,
    );
    if (!confirmed || !mounted) return;
    setState(() => _isProcessing = true);
    final ok = await context.read<VendorProvider>().deleteVendor(vendor.id);
    if (!mounted) return;
    setState(() => _isProcessing = false);
    if (ok) {
      Navigator.pop(context);
      showSuccessSnackBar(context, 'Vendor deleted');
    } else {
      showErrorSnackBar(
        context,
        context.read<VendorProvider>().errorMessage ?? 'Failed to delete',
      );
    }
  }
}
