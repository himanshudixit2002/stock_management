import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/permissions.dart';
import '../../widgets/permission_gate.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/purchase_order_model.dart';
import '../../providers/purchase_order_provider.dart';
import '../../providers/vendor_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';
import '../../utils/unit_conversion.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/product_picker.dart';
import '../../widgets/searchable_picker.dart';
import '../../widgets/success_overlay.dart';

class CreatePurchaseOrderScreen extends StatefulWidget {
  const CreatePurchaseOrderScreen({super.key});

  @override
  State<CreatePurchaseOrderScreen> createState() =>
      _CreatePurchaseOrderScreenState();
}

class _ItemRow {
  String? productId;
  String productName = '';
  String baseUnit = 'pcs';
  String packUnit = 'box';
  int unitsPerPack = 1;
  final TextEditingController qtyController = TextEditingController(); // packs
  final TextEditingController pieceController = TextEditingController();
  final TextEditingController priceController = TextEditingController();

  int get baseQuantity => toBaseQuantity(
    packs: int.tryParse(qtyController.text) ?? 0,
    pieces: int.tryParse(pieceController.text) ?? 0,
    unitsPerPack: unitsPerPack,
  );

  void dispose() {
    qtyController.dispose();
    pieceController.dispose();
    priceController.dispose();
  }
}

class _CreatePurchaseOrderScreenState extends State<CreatePurchaseOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedVendorId;
  String _selectedVendorName = '';
  final _notesController = TextEditingController();
  DateTime _expectedDate = DateTime.now().add(const Duration(days: 7));
  final List<_ItemRow> _items = [_ItemRow()];
  bool _isLoading = false;

  double get _totalAmount {
    double total = 0;
    for (final item in _items) {
      final qty = item.baseQuantity;
      final price = double.tryParse(item.priceController.text) ?? 0;
      total += qty * price;
    }
    return total;
  }

  @override
  void dispose() {
    _notesController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _expectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) setState(() => _expectedDate = date);
  }

  void _addItem() => setState(() => _items.add(_ItemRow()));

  void _removeItem(int index) {
    if (_items.length <= 1) return;
    setState(() {
      _items[index].dispose();
      _items.removeAt(index);
    });
  }

  Future<void> _saveOrder({required bool asDraft}) async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedVendorId == null) {
      showErrorSnackBar(context, 'Please select a vendor');
      return;
    }

    final validItems = _items.where((i) => i.productId != null).toList();
    if (validItems.isEmpty) {
      showErrorSnackBar(context, 'Add at least one item');
      return;
    }

    setState(() => _isLoading = true);
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    final now = DateTime.now();
    final poItems = validItems
        .map(
          (i) => POItem(
            productId: i.productId!,
            productName: i.productName,
            quantity: i.baseQuantity,
            unitPrice: double.tryParse(i.priceController.text) ?? 0,
          ),
        )
        .toList();

    final order = PurchaseOrderModel(
      id: '',
      vendorId: _selectedVendorId!,
      vendorName: _selectedVendorName,
      status: asDraft ? POStatus.draft : POStatus.sent,
      items: poItems,
      totalAmount: _totalAmount,
      expectedDate: _expectedDate,
      notes: _notesController.text.trim(),
      createdBy: user.uid,
      createdByName: user.name,
      createdAt: now,
      updatedAt: now,
    );

    final id = await context.read<PurchaseOrderProvider>().addOrder(order);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (id != null) {
      HapticFeedback.mediumImpact();
      showSuccessOverlay(
        context,
        message: asDraft ? 'Draft saved' : 'Purchase order sent',
      );
      Navigator.pop(context);
    } else {
      showErrorSnackBar(
        context,
        context.read<PurchaseOrderProvider>().errorMessage ??
            'Failed to create order',
      );
    }
  }

  Future<void> _showProductPicker(int itemIndex) async {
    final products = context.read<ProductProvider>().allProducts;
    final p = await showProductPicker(
      context: context,
      products: products,
      selectedProductId: _items[itemIndex].productId,
    );
    if (p == null || !mounted) return;
    setState(() {
      _items[itemIndex].productId = p.id;
      _items[itemIndex].productName = p.name;
      _items[itemIndex].baseUnit = p.baseUnit;
      _items[itemIndex].packUnit = p.unitsPerPack > 1 ? p.packUnit : p.baseUnit;
      _items[itemIndex].unitsPerPack = p.unitsPerPack;
      if (_items[itemIndex].priceController.text.isEmpty) {
        double price = p.costPrice;
        if (_selectedVendorId != null &&
            p.vendorPrices.containsKey(_selectedVendorId)) {
          price = p.vendorPrices[_selectedVendorId!] ?? price;
        }
        if (price > 0) {
          _items[itemIndex].priceController.text = price.toStringAsFixed(2);
        }
      }
    });
  }

  void _aiAutoFillLowStock() {
    final productProvider = context.read<ProductProvider>();
    final lowStockProducts = productProvider.lowStockProducts;

    if (lowStockProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🤖 AI Audit: All products are at healthy stock levels! No items low.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      for (final item in _items) {
        item.dispose();
      }
      _items.clear();

      for (final p in lowStockProducts) {
        final row = _ItemRow();
        row.productId = p.id;
        row.productName = p.name;
        row.baseUnit = p.baseUnit;
        row.unitsPerPack = p.unitsPerPack > 0 ? p.unitsPerPack : 1;
        
        final neededBase = (p.lowStockThreshold * 2 - p.quantity).clamp(5, 500);
        final packs = (neededBase / row.unitsPerPack).ceil();

        row.qtyController.text = packs.toString();
        row.pieceController.text = '0';
        row.priceController.text = p.costPrice.toStringAsFixed(2);
        
        _items.add(row);
      }

      if (_items.isEmpty) {
        _items.add(_ItemRow());
      }
    });

    HapticFeedback.heavyImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🤖 AI RAG Auto-Filled ${_items.length} low stock items with optimal reorder quantities!'),
        backgroundColor: AppTheme.primaryColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.createPurchaseOrders,
      featureName: 'Create Purchase Order',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {

    final vendors = context.watch<VendorProvider>().activeVendors;
    final dateFormat = DateFormat('dd MMM yyyy');
    final currencyFormat = NumberFormat.currency(
      symbol: AppTheme.currencySymbol,
      decimalDigits: 2,
    );

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: const AppBarTitleRow(
          icon: Icons.add_shopping_cart_rounded,
          color: AppTheme.primaryColor,
          title: 'Create Purchase Order',
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Responsive.formMaxWidth(context),
            ),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
                children: [
                  GlassPanel(
                    borderRadius: 20,
                    padding: const EdgeInsets.all(20),
                    useContentVariant: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order Details',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPri(context),
                          ),
                        ),
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: () async {
                            final result = await showSearchablePicker(
                              context: context,
                              title: 'Vendor',
                              selectedValue: _selectedVendorId,
                              addNewLabel: 'Create new vendor',
                              addNewValue: '__create_new__',
                              items: vendors
                                  .map(
                                    (v) => PickerItem(
                                      value: v.id,
                                      label: v.name,
                                      icon: Icons.local_shipping_rounded,
                                      iconColor: AppTheme.primaryColor,
                                    ),
                                  )
                                  .toList(),
                            );
                            if (result == '__create_new__') {
                              final navResult = await Navigator.pushNamed(
                                context,
                                AppRoutes.addVendor,
                              );
                              if (navResult is String &&
                                  navResult.isNotEmpty &&
                                  mounted) {
                                final v = context
                                    .read<VendorProvider>()
                                    .getVendorById(navResult);
                                setState(() {
                                  _selectedVendorId = navResult;
                                  _selectedVendorName = v?.name ?? '';
                                });
                              }
                              return;
                            }
                            if (result != null && mounted) {
                              final v = context
                                  .read<VendorProvider>()
                                  .getVendorById(result);
                              setState(() {
                                _selectedVendorId = result;
                                _selectedVendorName = v?.name ?? '';
                              });
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Vendor *',
                              prefixIcon: Icon(Icons.local_shipping_rounded),
                            ),
                            child: Text(
                              _selectedVendorName.isEmpty
                                  ? 'Select vendor'
                                  : _selectedVendorName,
                              style: TextStyle(
                                color: _selectedVendorName.isNotEmpty
                                    ? null
                                    : AppTheme.textSec(context),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        InkWell(
                          onTap: _pickDate,
                          borderRadius: BorderRadius.circular(16),
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Expected Date *',
                              prefixIcon: Icon(Icons.calendar_today_rounded),
                            ),
                            child: Text(dateFormat.format(_expectedDate)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _notesController,
                          decoration: const InputDecoration(
                            labelText: 'Notes (optional)',
                            prefixIcon: Icon(Icons.note_rounded),
                          ),
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  GlassPanel(
                    borderRadius: 20,
                    padding: const EdgeInsets.all(20),
                    useContentVariant: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(
                              'Items (${_items.length})',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPri(context),
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton.icon(
                                  onPressed: _aiAutoFillLowStock,
                                  icon: const Icon(Icons.bolt_rounded, size: 16, color: AppTheme.primaryColor),
                                  label: const Text(
                                    'Auto-Fill Low Stock',
                                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                TextButton.icon(
                                  onPressed: _addItem,
                                  icon: const Icon(Icons.add_rounded, size: 16),
                                  label: const Text('Add Item', style: TextStyle(fontSize: 11.5)),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ...List.generate(_items.length, (index) {
                          final item = _items[index];
                          final isMobile = MediaQuery.of(context).size.width < 500;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.inputFill(context),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppTheme.inputBorder(context),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: InkWell(
                                          onTap: () =>
                                              _showProductPicker(index),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                color: AppTheme.inputBorder(
                                                  context,
                                                ),
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              color: AppTheme.surface(context),
                                            ),
                                            child: Text(
                                              item.productName.isNotEmpty
                                                  ? item.productName
                                                  : 'Select product...',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color:
                                                    item.productName.isNotEmpty
                                                    ? AppTheme.textPri(context)
                                                    : AppTheme.textSec(context),
                                                fontWeight:
                                                    item.productName.isNotEmpty
                                                    ? FontWeight.w600
                                                    : FontWeight.normal,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (_items.length > 1) ...[
                                        const SizedBox(width: 4),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.remove_circle_outline_rounded,
                                            color: AppTheme.dangerColor,
                                            size: 20,
                                          ),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                          onPressed: () => _removeItem(index),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (isMobile) ...[
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextFormField(
                                            controller: item.qtyController,
                                            decoration: const InputDecoration(
                                              labelText: 'Packs *',
                                              isDense: true,
                                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            ),
                                            style: const TextStyle(fontSize: 13),
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [
                                              FilteringTextInputFormatter.digitsOnly,
                                            ],
                                            onChanged: (_) => setState(() {}),
                                            validator: (v) {
                                              if (item.productId == null) return null;
                                              final packs = int.tryParse(v ?? '') ?? 0;
                                              final pieces = int.tryParse(item.pieceController.text) ?? 0;
                                              final baseQty = toBaseQuantity(
                                                packs: packs,
                                                pieces: pieces,
                                                unitsPerPack: item.unitsPerPack,
                                              );
                                              if (baseQty <= 0) return 'Required';
                                              return null;
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: TextFormField(
                                            controller: item.pieceController,
                                            decoration: InputDecoration(
                                              labelText: 'Loose (${item.baseUnit})',
                                              isDense: true,
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            ),
                                            style: const TextStyle(fontSize: 13),
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [
                                              FilteringTextInputFormatter.digitsOnly,
                                            ],
                                            onChanged: (_) => setState(() {}),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    TextFormField(
                                      controller: item.priceController,
                                      decoration: InputDecoration(
                                        labelText: 'Unit Cost',
                                        isDense: true,
                                        prefixText: '${AppTheme.currencySymbol} ',
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      ),
                                      style: const TextStyle(fontSize: 13),
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ] else ...[
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextFormField(
                                            controller: item.qtyController,
                                            decoration: const InputDecoration(
                                              labelText: 'Packs *',
                                              isDense: true,
                                            ),
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [
                                              FilteringTextInputFormatter.digitsOnly,
                                            ],
                                            onChanged: (_) => setState(() {}),
                                            validator: (v) {
                                              if (item.productId == null) return null;
                                              final packs = int.tryParse(v ?? '') ?? 0;
                                              final pieces = int.tryParse(item.pieceController.text) ?? 0;
                                              final baseQty = toBaseQuantity(
                                                packs: packs,
                                                pieces: pieces,
                                                unitsPerPack: item.unitsPerPack,
                                              );
                                              if (baseQty <= 0) return 'Required';
                                              return null;
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 90,
                                          child: TextFormField(
                                            controller: item.pieceController,
                                            decoration: InputDecoration(
                                              labelText: item.baseUnit,
                                              isDense: true,
                                            ),
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [
                                              FilteringTextInputFormatter.digitsOnly,
                                            ],
                                            onChanged: (_) => setState(() {}),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: TextFormField(
                                            controller: item.priceController,
                                            decoration: InputDecoration(
                                              labelText: 'Unit Price',
                                              isDense: true,
                                              prefixText: '${AppTheme.currencySymbol} ',
                                            ),
                                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                            onChanged: (_) => setState(() {}),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  GlassPanel(
                    borderRadius: 16,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    useContentVariant: true,
                    child: Row(
                      children: [
                        Text(
                          'Total Amount',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPri(context),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          currencyFormat.format(_totalAmount),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  ShimmerButton(
                    label: _isLoading ? 'Sending…' : 'Send',
                    icon: Icons.send_rounded,
                    onPressed: _isLoading
                        ? null
                        : () => _saveOrder(asDraft: false),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () => _saveOrder(asDraft: true),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save Draft'),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
