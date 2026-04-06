import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/product_model.dart';
import '../../models/purchase_order_model.dart';
import '../../models/stock_transaction_model.dart';
import '../../models/vendor_model.dart';
import '../../providers/product_provider.dart';
import '../../providers/stock_provider.dart';
import '../../providers/vendor_provider.dart';
import '../../providers/purchase_order_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/success_overlay.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';

class _ReorderItem {
  final ProductModel product;
  final double avgDailyUsage;
  final int daysUntilStockout;
  final int suggestedQty;
  bool selected = false;

  _ReorderItem({
    required this.product,
    required this.avgDailyUsage,
    required this.daysUntilStockout,
    required this.suggestedQty,
  });
}

class ReorderSuggestionsScreen extends StatefulWidget {
  const ReorderSuggestionsScreen({super.key});

  @override
  State<ReorderSuggestionsScreen> createState() =>
      _ReorderSuggestionsScreenState();
}

class _ReorderSuggestionsScreenState extends State<ReorderSuggestionsScreen> {
  String? _categoryFilter;
  bool _creatingPO = false;
  final Set<String> _selectedIds = {};
  final Map<String, int> _editedQty = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ProductProvider>().loadAnalytics();
    });
  }

  List<_ReorderItem> _compute(
    List<ProductModel> products,
    List<StockTransactionModel> transactions,
  ) {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));

    final stockOutByProduct = <String, int>{};
    for (final t in transactions) {
      if (t.type == TransactionType.stockOut &&
          t.date.isAfter(thirtyDaysAgo)) {
        stockOutByProduct[t.productId] =
            (stockOutByProduct[t.productId] ?? 0) + t.quantity;
      }
    }

    final items = <_ReorderItem>[];
    for (final p in products) {
      if (p.quantity > p.lowStockThreshold) continue;

      final totalOut = stockOutByProduct[p.id] ?? 0;
      final avgDaily = totalOut / 30.0;
      final daysLeft = avgDaily > 0 ? (p.quantity / avgDaily).floor() : 999;
      final suggestedQty =
          (p.lowStockThreshold * 2 - p.quantity).clamp(1, 99999);

      items.add(_ReorderItem(
        product: p,
        avgDailyUsage: avgDaily,
        daysUntilStockout: daysLeft,
        suggestedQty: suggestedQty,
      ));
    }

    items.sort((a, b) => a.daysUntilStockout.compareTo(b.daysUntilStockout));
    return items;
  }

  int _getQty(_ReorderItem item) =>
      _editedQty[item.product.id] ?? item.suggestedQty;

  void _showEditQtyDialog(_ReorderItem item) {
    final controller =
        TextEditingController(text: _getQty(item).toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reorder Qty: ${item.product.name}',
            style: const TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Quantity',
            hintText: 'Suggested: ${item.suggestedQty}',
          ),
          onSubmitted: (_) {
            final val = int.tryParse(controller.text.trim());
            if (val != null && val > 0) {
              setState(() => _editedQty[item.product.id] = val);
            }
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _editedQty.remove(item.product.id));
              Navigator.pop(ctx);
            },
            child: const Text('Reset'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = int.tryParse(controller.text.trim());
              if (val != null && val > 0) {
                setState(() => _editedQty[item.product.id] = val);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }

  Future<void> _createPO(List<_ReorderItem> selected) async {
    final vendors = context.read<VendorProvider>().activeVendors;

    if (vendors.isEmpty) {
      showInfoSnackBar(context, 'Add at least one vendor in Settings first.');
      return;
    }

    final vendorResult = await showModalBottomSheet<Map<String, String>>(
      context: context,
      constraints: Responsive.sheetConstraints(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _VendorPickerSheet(vendors: vendors),
    );
    if (vendorResult == null || !mounted) return;

    final currencyFormat = NumberFormat.currency(
        symbol: AppTheme.currencySymbol, decimalDigits: 2);
    final totalAmount = selected.fold<double>(
      0,
      (sum, i) => sum + _getQty(i) * i.product.costPrice,
    );

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      constraints: Responsive.sheetConstraints(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ConfirmPOSheet(
        vendorName: vendorResult['name']!,
        itemCount: selected.length,
        totalAmount: currencyFormat.format(totalAmount),
        items: selected
            .map((i) =>
                '${i.product.name}  x${_getQty(i)}  @ ${currencyFormat.format(i.product.costPrice)}')
            .toList(),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _creatingPO = true);

    final user = context.read<AuthProvider>().currentUser;
    final now = DateTime.now();
    final poItems = selected
        .map((item) => POItem(
              productId: item.product.id,
              productName: item.product.name,
              quantity: _getQty(item),
              receivedQuantity: 0,
              unitPrice: item.product.costPrice,
            ))
        .toList();

    final order = PurchaseOrderModel(
      id: '',
      vendorId: vendorResult['id']!,
      vendorName: vendorResult['name']!,
      status: POStatus.draft,
      items: poItems,
      totalAmount: totalAmount,
      expectedDate: now.add(const Duration(days: 7)),
      notes: 'Auto-generated from reorder suggestions',
      createdBy: user?.uid ?? '',
      createdByName: user?.name ?? '',
      createdAt: now,
      updatedAt: now,
    );

    final poId = await context.read<PurchaseOrderProvider>().addOrder(order);

    if (!mounted) return;
    setState(() {
      _creatingPO = false;
      if (poId != null) {
        _selectedIds.clear();
        _editedQty.clear();
      }
    });

    if (poId != null) {
      showSuccessOverlay(
        context,
        message: 'Draft PO created with ${selected.length} item(s)',
        popAfter: false,
      );
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) {
        Navigator.pushNamed(
          context,
          AppRoutes.purchaseOrderDetail,
          arguments: poId,
        );
      }
    } else {
      showErrorSnackBar(context, context.read<PurchaseOrderProvider>().errorMessage ?? 'Failed to create PO');
    }
  }

  Color _urgencyColor(int days) {
    if (days <= 3) return AppTheme.dangerColor;
    if (days <= 7) return AppTheme.warningColor;
    if (days <= 14) return const Color(0xFFFB8C00);
    return AppTheme.primaryColor;
  }

  @override
  Widget build(BuildContext context) {
    final productProvider = context.watch<ProductProvider>();
    final products = productProvider.analyticsProducts;
    final isLoading = productProvider.isLoadingAnalytics;
    final transactions = context.watch<StockProvider>().allTransactions;
    final items = _compute(products, transactions);

    final filtered = _categoryFilter == null
        ? items
        : items
            .where((i) => i.product.categoryName == _categoryFilter)
            .toList();

    final categories = <String>{};
    for (final item in items) {
      if (item.product.categoryName.isNotEmpty) {
        categories.add(item.product.categoryName);
      }
    }
    final sortedCategories = categories.toList()..sort();

    for (final item in items) {
      item.selected = _selectedIds.contains(item.product.id);
    }

    final visibleSelected = filtered.where((i) => i.selected).toList();
    final visibleSelectedCount = visibleSelected.length;
    final allVisibleSelected =
        filtered.isNotEmpty && filtered.every((i) => i.selected);

    return Container(
      decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const AppBarTitleRow(
            icon: Icons.shopping_cart_checkout_rounded,
            color: AppTheme.warningColor,
            title: 'Reorder Suggestions',
          ),
        ),
        bottomNavigationBar: visibleSelectedCount > 0
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton.icon(
                    onPressed: _creatingPO
                        ? null
                        : () => _createPO(visibleSelected),
                    icon: _creatingPO
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.receipt_long_rounded),
                    label: Text(
                      _creatingPO
                          ? 'Creating...'
                          : 'Create PO ($visibleSelectedCount items)',
                    ),
                  ),
                ),
              )
            : null,
        body: _buildBody(
          isLoading: isLoading,
          items: items,
          filtered: filtered,
          sortedCategories: sortedCategories,
          allVisibleSelected: allVisibleSelected,
        ),
      ),
    );
  }

  Widget _buildBody({
    required bool isLoading,
    required List<_ReorderItem> items,
    required List<_ReorderItem> filtered,
    required List<String> sortedCategories,
    required bool allVisibleSelected,
  }) {
    if (isLoading && items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(strokeWidth: 2.5),
            SizedBox(height: 16),
            Text('Loading product data...'),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (sortedCategories.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('All'),
                    selected: _categoryFilter == null,
                    onSelected: (_) =>
                        setState(() => _categoryFilter = null),
                    selectedColor: AppTheme.primaryColor,
                    labelStyle: TextStyle(
                      color: _categoryFilter == null
                          ? Colors.white
                          : AppTheme.textPri(context),
                      fontWeight: FontWeight.w500,
                    ),
                    checkmarkColor: Colors.white,
                  ),
                ),
                ...sortedCategories.map((cat) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(cat),
                        selected: _categoryFilter == cat,
                        onSelected: (_) =>
                            setState(() => _categoryFilter = cat),
                        selectedColor: AppTheme.primaryColor,
                        labelStyle: TextStyle(
                          color: _categoryFilter == cat
                              ? Colors.white
                              : AppTheme.textPri(context),
                          fontWeight: FontWeight.w500,
                        ),
                        checkmarkColor: Colors.white,
                      ),
                    )),
              ],
            ),
          ),
        if (filtered.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text(
                  '${filtered.length} item${filtered.length == 1 ? '' : 's'} need reorder',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSec(context),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      if (allVisibleSelected) {
                        for (final i in filtered) {
                          _selectedIds.remove(i.product.id);
                        }
                      } else {
                        for (final i in filtered) {
                          _selectedIds.add(i.product.id);
                        }
                      }
                    });
                  },
                  icon: Icon(
                    allVisibleSelected
                        ? Icons.deselect_rounded
                        : Icons.select_all_rounded,
                    size: 18,
                  ),
                  label: Text(
                    allVisibleSelected ? 'Deselect All' : 'Select All',
                    style: const TextStyle(fontSize: 13),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: filtered.isEmpty
              ? const EmptyStateWidget(
                  icon: Icons.check_circle_outline_rounded,
                  title: 'No Reorders Needed',
                  subtitle:
                      'All products are above their low stock threshold.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    final color = _urgencyColor(item.daysUntilStockout);
                    final qty = _getQty(item);
                    final isEdited =
                        _editedQty.containsKey(item.product.id);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GlassCard(
                        onTap: () => setState(() {
                          if (_selectedIds.contains(item.product.id)) {
                            _selectedIds.remove(item.product.id);
                          } else {
                            _selectedIds.add(item.product.id);
                          }
                        }),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(color: color, width: 4),
                            ),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Checkbox(
                                    value: item.selected,
                                    onChanged: (v) => setState(() {
                                      if (v == true) {
                                        _selectedIds.add(item.product.id);
                                      } else {
                                        _selectedIds
                                            .remove(item.product.id);
                                      }
                                    }),
                                    activeColor: AppTheme.primaryColor,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.product.name,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                            color:
                                                AppTheme.textPri(context),
                                          ),
                                        ),
                                        if (item.product.categoryName
                                            .isNotEmpty)
                                          Text(
                                            item.product.categoryName,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color:
                                                  AppTheme.textSec(context),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          color.withValues(alpha: 0.12),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      item.daysUntilStockout >= 999
                                          ? 'No usage'
                                          : '${item.daysUntilStockout}d left',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: color,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  _StatChip(
                                    label: 'Stock',
                                    value: '${item.product.quantity}',
                                    color: AppTheme.textPri(context),
                                  ),
                                  const SizedBox(width: 8),
                                  _StatChip(
                                    label: 'Threshold',
                                    value:
                                        '${item.product.lowStockThreshold}',
                                    color: AppTheme.warningColor,
                                  ),
                                  const SizedBox(width: 8),
                                  _StatChip(
                                    label: 'Avg/Day',
                                    value: item.avgDailyUsage
                                        .toStringAsFixed(1),
                                    color: AppTheme.infoColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: InkWell(
                                      onTap: () =>
                                          _showEditQtyDialog(item),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                      child: Container(
                                        padding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isEdited
                                              ? AppTheme.primaryColor
                                                  .withValues(alpha: 0.1)
                                              : null,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                            color: AppTheme.primaryColor
                                                .withValues(alpha: 0.3),
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .center,
                                              mainAxisSize:
                                                  MainAxisSize.min,
                                              children: [
                                                Text(
                                                  '$qty',
                                                  style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight:
                                                        FontWeight.w700,
                                                    color: AppTheme
                                                        .primaryColor,
                                                  ),
                                                ),
                                                const SizedBox(width: 2),
                                                Icon(
                                                  Icons.edit_rounded,
                                                  size: 12,
                                                  color: AppTheme
                                                      .primaryColor,
                                                ),
                                              ],
                                            ),
                                            Text(
                                              'Reorder',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color:
                                                    AppTheme.textSec(
                                                        context),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Confirmation sheet shown before creating the PO
// ---------------------------------------------------------------------------
class _ConfirmPOSheet extends StatelessWidget {
  final String vendorName;
  final int itemCount;
  final String totalAmount;
  final List<String> items;

  const _ConfirmPOSheet({
    required this.vendorName,
    required this.itemCount,
    required this.totalAmount,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.dividerC(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Confirm Purchase Order',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Divider(height: 1, color: AppTheme.dividerC(context)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Icon(Icons.local_shipping_rounded,
                    size: 18, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                Text('Vendor: ',
                    style: TextStyle(
                        color: AppTheme.textSec(context), fontSize: 13)),
                Expanded(
                  child: Text(vendorName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Icon(Icons.inventory_2_rounded,
                    size: 18, color: AppTheme.infoColor),
                const SizedBox(width: 8),
                Text('$itemCount item${itemCount == 1 ? '' : 's'}',
                    style: TextStyle(
                        color: AppTheme.textSec(context), fontSize: 13)),
                const Spacer(),
                Text('Total: $totalAmount',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
              ],
            ),
          ),
          if (items.isNotEmpty)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.25,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                itemCount: items.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: AppTheme.dividerC(context)),
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    items[i],
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textSec(context)),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Create Draft PO'),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Vendor picker sheet
// ---------------------------------------------------------------------------
class _VendorPickerSheet extends StatelessWidget {
  final List<VendorModel> vendors;
  const _VendorPickerSheet({required this.vendors});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.dividerC(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Select Vendor for PO',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Divider(height: 1, color: AppTheme.dividerC(context)),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.4,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: vendors.length,
              itemBuilder: (context, index) {
                final v = vendors[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        AppTheme.primaryColor.withValues(alpha: 0.1),
                    child: Text(
                      v.name.isNotEmpty ? v.name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(v.name),
                  subtitle: v.contactName.isNotEmpty
                      ? Text(v.contactName,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSec(context),
                          ))
                      : null,
                  onTap: () => Navigator.pop<Map<String, String>>(
                    context,
                    <String, String>{'id': v.id, 'name': v.name},
                  ),
                );
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stat chip
// ---------------------------------------------------------------------------
class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: AppTheme.textSec(context),
            ),
          ),
        ],
      ),
    );
  }
}
