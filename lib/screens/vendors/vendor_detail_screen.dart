import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/file_helper.dart' as file_helper;
import '../../models/vendor_model.dart';
import '../../widgets/glass_panel.dart';
import '../../models/stock_transaction_model.dart';
import '../../models/product_model.dart';
import '../../providers/vendor_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/stock_provider.dart';
import '../../providers/billing_provider.dart';
import '../../providers/billing_settings_provider.dart';
import '../../models/invoice_model.dart';
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ProductProvider>().loadAnalytics();
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final vendorProvider = context.watch<VendorProvider>();
    final productProvider = context.watch<ProductProvider>();
    final stockProvider = context.watch<StockProvider>();

    final vendor =
        vendorProvider.getVendorById(widget.vendor.id) ?? widget.vendor;
    final allProducts = productProvider.analyticsProducts;
    final isLoadingProducts = productProvider.isLoadingAnalytics;
    final allTransactions = stockProvider.allTransactions;

    final scorecard = vendorProvider.vendorScorecard(
      vendor.id,
      allTransactions,
    );
    final linkedProducts = allProducts
        .where((p) => p.preferredVendorId == vendor.id)
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: Text(vendor.name),
        actions: [
          if (user?.hasPermission(AppPermissions.editVendors) ?? false)
            IconButton(
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => Navigator.pushNamed(
                context,
                AppRoutes.editVendor,
                arguments: vendor,
              ),
            ),
          if (user?.hasPermission(AppPermissions.deleteVendors) ?? false)
            IconButton(
              icon: const Icon(Icons.delete_rounded),
              onPressed: () => _confirmDelete(context, vendor),
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Responsive.contentMaxWidth(context),
            ),
            child: isLoadingProducts && allProducts.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(strokeWidth: 2.5),
                        SizedBox(height: 16),
                        Text('Loading product data...'),
                      ],
                    ),
                  )
                : ListView(
                    padding: EdgeInsets.all(
                      Responsive.horizontalPadding(context),
                    ),
                    children: [
                      Builder(builder: (context) {
                        final section1 = Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildInfoCard(vendor),
                            const SizedBox(height: 16),
                            _buildScorecardSection(scorecard),
                          ],
                        );
                        final section2 = Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildLinkedProductsSection(
                              linkedProducts,
                              allProducts,
                              vendor,
                            ),
                            const SizedBox(height: 16),
                            _buildPurchaseOrderSection(vendor, allProducts),
                          ],
                        );
                        if (Responsive.isDesktop(context)) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: section1),
                              const SizedBox(width: 16),
                              Expanded(child: section2),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            section1,
                            const SizedBox(height: 16),
                            section2,
                          ],
                        );
                      }),
                      if (context
                          .watch<BillingSettingsProvider>()
                          .billingEnabled) ...[
                        const SizedBox(height: 16),
                        _buildBillingSection(vendor),
                      ],
                      const SizedBox(height: 16),
                      _buildRecentTransactionsSection(vendor.id),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(VendorModel vendor) {
    return GlassPanel(
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      useContentVariant: true,
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
                child: const Icon(
                  Icons.local_shipping_rounded,
                  color: AppTheme.indigoColor,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vendor.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: vendor.isActive
                                ? AppTheme.successColor.withValues(alpha: 0.1)
                                : AppTheme.textMute(
                                    context,
                                  ).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            vendor.isActive ? 'Active' : 'Inactive',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: vendor.isActive
                                  ? AppTheme.successColor
                                  : AppTheme.textMute(context),
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
                                  : AppTheme.emptyIcon(context),
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
            _infoRow(
              Icons.person_outline_rounded,
              'Contact',
              vendor.contactName,
            ),
          if (vendor.email.isNotEmpty)
            _infoRow(Icons.email_outlined, 'Email', vendor.email),
          if (vendor.phone.isNotEmpty)
            _infoRow(Icons.phone_outlined, 'Phone', vendor.phone),
          if (vendor.address.isNotEmpty)
            _infoRow(Icons.location_on_outlined, 'Address', vendor.address),
          if (vendor.leadTimeDays > 0)
            _infoRow(
              Icons.schedule_rounded,
              'Lead Time',
              '${vendor.leadTimeDays} days',
            ),
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
          Icon(icon, size: 18, color: AppTheme.textTer(context)),
          const SizedBox(width: 10),
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: AppTheme.textTer(context)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScorecardSection(Map<String, dynamic> scorecard) {
    final totalTxns = scorecard['totalTransactions'] as int;
    final totalQty = scorecard['totalQuantity'] as int;
    final lastDate = scorecard['lastTransactionDate'] as DateTime?;

    return GlassPanel(
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      useContentVariant: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.analytics_rounded,
                color: AppTheme.indigoColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Scorecard',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 360) {
                return Column(
                  children: [
                    _scorecardContent(
                      'Transactions',
                      totalTxns.toString(),
                      AppTheme.infoColor,
                    ),
                    const SizedBox(height: 8),
                    _scorecardContent(
                      'Units Supplied',
                      totalQty.toString(),
                      AppTheme.successColor,
                    ),
                    const SizedBox(height: 8),
                    _scorecardContent(
                      'Last Delivery',
                      lastDate != null
                          ? DateFormat('MMM d').format(lastDate)
                          : 'N/A',
                      AppTheme.warningColor,
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  _scorecardTile(
                    'Transactions',
                    totalTxns.toString(),
                    AppTheme.infoColor,
                  ),
                  const SizedBox(width: 12),
                  _scorecardTile(
                    'Units Supplied',
                    totalQty.toString(),
                    AppTheme.successColor,
                  ),
                  const SizedBox(width: 12),
                  _scorecardTile(
                    'Last Delivery',
                    lastDate != null
                        ? DateFormat('MMM d').format(lastDate)
                        : 'N/A',
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
    return Expanded(child: _scorecardContent(label, value, color));
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
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: AppTheme.textTer(context)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildLinkedProductsSection(
    List<ProductModel> linkedProducts,
    List<ProductModel> allProducts,
    VendorModel vendor,
  ) {
    return GlassPanel(
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      useContentVariant: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.inventory_2_rounded,
                color: AppTheme.primaryColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Linked Products (${linkedProducts.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () =>
                    _showBulkAssignSheet(context, allProducts, vendor),
                icon: const Icon(Icons.link_rounded, size: 16),
                label: const Text('Assign', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (linkedProducts.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No products linked to this vendor',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textTer(context),
                  ),
                ),
              ),
            )
          else
            ...linkedProducts
                .take(10)
                .map(
                  (p) => Padding(
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
                          child: Text(
                            p.name,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Text(
                          '${p.quantity} ${p.unit}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textTer(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          if (linkedProducts.length > 10)
            Center(
              child: Text(
                '+${linkedProducts.length - 10} more',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textTer(context),
                ),
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
    final poItems = vendorProvider.generatePurchaseOrderDraft(
      vendor.id,
      allProducts,
    );

    return GlassPanel(
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      useContentVariant: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.receipt_long_rounded,
                color: AppTheme.warningColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Purchase Order Draft (${poItems.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (poItems.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _exportPurchaseOrder(vendor, poItems),
                  icon: const Icon(Icons.file_download_outlined, size: 16),
                  label: const Text('Export', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (poItems.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No low stock items for this vendor',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textTer(context),
                  ),
                ),
              ),
            )
          else
            ...poItems
                .take(10)
                .map(
                  (item) => Padding(
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
                          child: Text(
                            item['productName'] as String,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Text(
                          '${item['currentQty']}/${item['threshold']} ${item['unit']}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textTer(context),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
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
                  ),
                ),
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
      buffer.writeln(
        'Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
      );
      buffer.writeln('');
      buffer.writeln('Product,Current Qty,Threshold,Suggested Order,Unit');
      for (final item in items) {
        buffer.writeln(
          '${item['productName']},${item['currentQty']},${item['threshold']},${item['suggestedOrderQty']},${item['unit']}',
        );
      }

      final fileName =
          'PO_${vendor.name.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
      final bytes = utf8.encode(buffer.toString());
      if (!mounted) return;

      await file_helper.saveAndShareFile(fileName, bytes);
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

  Widget _buildBillingSection(VendorModel vendor) {
    final billing = context.watch<BillingProvider>();
    final bs = context.watch<BillingSettingsProvider>().settings;
    final sym = bs.currencySymbol.isNotEmpty ? bs.currencySymbol : '₹';
    final numFmt = NumberFormat('#,##0.00');
    final dateFmt = DateFormat('dd MMM yyyy');
    final outstanding = billing.vendorOutstanding(vendor.id);
    final vendorInvoices = billing.invoicesForVendor(vendor.id);
    final recent = vendorInvoices.take(5).toList();

    return GlassPanel(
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      useContentVariant: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.receipt_long_rounded,
                size: 18,
                color: AppTheme.warningColor,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Bills',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: outstanding > 0
                      ? AppTheme.dangerColor.withValues(alpha: 0.1)
                      : AppTheme.successColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Due: $sym${numFmt.format(outstanding)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: outstanding > 0
                        ? AppTheme.dangerColor
                        : AppTheme.successColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (recent.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No bills yet',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textTer(context),
                ),
              ),
            )
          else
            ...recent.map(
              (inv) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.pushNamed(
                      context,
                      AppRoutes.invoiceDetail,
                      arguments: inv.id,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  inv.invoiceNumber,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  '${dateFmt.format(inv.invoiceDate)} · ${inv.statusLabel}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textTer(context),
                                  ),
                                ),
                                if (inv.amountDue > 0 &&
                                    !inv.isPaid &&
                                    !inv.isCancelled)
                                  Text(
                                    'Due: $sym${numFmt.format(inv.amountDue)}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.dangerColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '$sym${numFmt.format(inv.grandTotal)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: AppTheme.textTer(context),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.pushNamed(context, AppRoutes.vendorStatement),
                  icon: const Icon(Icons.description_rounded, size: 16),
                  label: const Text(
                    'Statement',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pushNamed(
                    context,
                    AppRoutes.createInvoice,
                    arguments: <String, dynamic>{
                      'type': InvoiceType.purchase,
                      'vendorId': vendor.id,
                      'vendorName': vendor.name,
                    },
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text(
                    'Create Bill',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentTransactionsSection(String vendorId) {
    return GlassPanel(
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      useContentVariant: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.receipt_long_rounded,
                color: AppTheme.warningColor,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Recent Transactions',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          StreamBuilder<List<StockTransactionModel>>(
            stream: context.read<VendorProvider>().getVendorTransactions(
              vendorId,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              final txns = snapshot.data ?? [];
              if (txns.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No transactions yet',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textTer(context),
                      ),
                    ),
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
                          child: Text(
                            t.productName,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Text(
                          '${t.quantity}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isIn
                                ? AppTheme.successColor
                                : AppTheme.dangerColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('MMM d').format(t.date),
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textTer(context),
                          ),
                        ),
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
    final originalIds = <String>{};
    final selectedIds = <String>{};
    for (final p in allProducts) {
      if (p.preferredVendorId == vendor.id) {
        originalIds.add(p.id);
        selectedIds.add(p.id);
      }
    }
    String search = '';

    showModalBottomSheet(
      context: parentCtx,
      constraints: Responsive.sheetConstraints(parentCtx),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final filtered = search.isEmpty
                ? allProducts
                : allProducts
                      .where(
                        (p) =>
                            p.name.toLowerCase().contains(
                              search.toLowerCase(),
                            ) ||
                            p.categoryName.toLowerCase().contains(
                              search.toLowerCase(),
                            ),
                      )
                      .toList();

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
                          const Icon(
                            Icons.link_rounded,
                            color: AppTheme.indigoColor,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Assign Products to ${vendor.name}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              Navigator.pop(ctx);

                              final toAssign = selectedIds
                                  .difference(originalIds)
                                  .toList();
                              final toUnassign = originalIds
                                  .difference(selectedIds)
                                  .toList();
                              final unchanged =
                                  toAssign.isEmpty && toUnassign.isEmpty;

                              if (unchanged) return;

                              bool ok = true;
                              if (toAssign.isNotEmpty) {
                                ok = await parentCtx
                                    .read<VendorProvider>()
                                    .bulkAssignVendor(
                                      productIds: toAssign,
                                      vendorId: vendor.id,
                                      vendorName: vendor.name,
                                    );
                              }
                              if (toUnassign.isNotEmpty && ok) {
                                ok = await parentCtx
                                    .read<VendorProvider>()
                                    .bulkAssignVendor(
                                      productIds: toUnassign,
                                      vendorId: '',
                                      vendorName: '',
                                    );
                              }

                              if (mounted) {
                                parentCtx.read<ProductProvider>()
                                  ..invalidateAnalytics()
                                  ..loadAnalytics();

                                final total =
                                    toAssign.length + toUnassign.length;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      ok
                                          ? '$total product${total == 1 ? '' : 's'} updated'
                                          : 'Failed to update products',
                                    ),
                                    backgroundColor: ok
                                        ? AppTheme.successColor
                                        : AppTheme.dangerColor,
                                  ),
                                );
                              }
                            },
                            child: Text('Save (${selectedIds.length})'),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Search products...',
                          prefixIcon: Icon(Icons.search_rounded),
                          isDense: true,
                        ),
                        onChanged: (v) => setSheetState(() => search = v),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        controller: controller,
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final p = filtered[i];
                          final isSelected = selectedIds.contains(p.id);
                          return CheckboxListTile(
                            title: Text(
                              p.name,
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: Text(
                              [
                                p.categoryName,
                                if (p.company.isNotEmpty) p.company,
                                '${p.quantity} ${p.unit}',
                              ].join(' | '),
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textTer(context),
                              ),
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
      message:
          'Are you sure you want to delete "${vendor.name}"? This cannot be undone.',
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
