import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/sales_order_model.dart';
import '../../providers/sales_order_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/product_picker.dart';
import '../../widgets/searchable_picker.dart';
import '../../widgets/success_overlay.dart';

class CreateSalesOrderScreen extends StatefulWidget {
  const CreateSalesOrderScreen({super.key});

  @override
  State<CreateSalesOrderScreen> createState() => _CreateSalesOrderScreenState();
}

class _SOItemRow {
  String? productId;
  String productName = '';
  int availableStock = 0;
  String unit = 'pcs';
  final TextEditingController qtyController = TextEditingController();
  final TextEditingController priceController = TextEditingController();

  void dispose() {
    qtyController.dispose();
    priceController.dispose();
  }
}

class _CreateSalesOrderScreenState extends State<CreateSalesOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedCustomerId;
  String _selectedCustomerName = '';
  final _notesController = TextEditingController();
  final List<_SOItemRow> _items = [_SOItemRow()];
  bool _isLoading = false;

  double get _totalAmount {
    double total = 0;
    for (final item in _items) {
      final qty = int.tryParse(item.qtyController.text) ?? 0;
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

  void _addItem() => setState(() => _items.add(_SOItemRow()));

  void _removeItem(int index) {
    if (_items.length <= 1) return;
    setState(() {
      _items[index].dispose();
      _items.removeAt(index);
    });
  }

  Future<void> _saveOrder({required bool asDraft}) async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomerId == null) {
      showErrorSnackBar(context, 'Please select a customer');
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
    final soItems = validItems
        .map((i) => SOItem(
              productId: i.productId!,
              productName: i.productName,
              quantity: int.tryParse(i.qtyController.text) ?? 0,
              unitPrice: double.tryParse(i.priceController.text) ?? 0,
            ))
        .toList();

    final order = SalesOrderModel(
      id: '',
      customerId: _selectedCustomerId!,
      customerName: _selectedCustomerName,
      status: asDraft ? SOStatus.draft : SOStatus.confirmed,
      items: soItems,
      totalAmount: _totalAmount,
      notes: _notesController.text.trim(),
      createdBy: user.uid,
      createdByName: user.name,
      createdAt: now,
      updatedAt: now,
    );

    final id = await context.read<SalesOrderProvider>().addOrder(order);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (id != null) {
      HapticFeedback.mediumImpact();
      showSuccessOverlay(context,
          message: asDraft ? 'Draft saved' : 'Sales order confirmed');
      Navigator.pop(context);
    } else {
      showErrorSnackBar(context,
          context.read<SalesOrderProvider>().errorMessage ?? 'Failed to create order');
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
      _items[itemIndex].availableStock = p.quantity;
      _items[itemIndex].unit = p.unit;
      if (p.sellingPrice > 0 && _items[itemIndex].priceController.text.isEmpty) {
        _items[itemIndex].priceController.text = p.sellingPrice.toStringAsFixed(2);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    if (user != null && !user.hasPermission(AppPermissions.createSalesOrders)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Create Sales Order')),
        body: const Center(
          child: Text('You do not have permission to access this feature.'),
        ),
      );
    }

    final customers = context.watch<CustomerProvider>().activeCustomers;
    final currencyFormat = NumberFormat.currency(symbol: AppTheme.currencySymbol, decimalDigits: 2);

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: const AppBarTitleRow(
          icon: Icons.add_chart_rounded,
          color: AppTheme.indigoColor,
          title: 'Create Sales Order',
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: Responsive.formMaxWidth(context)),
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
                        Text('Order Details',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                                color: AppTheme.textPri(context))),
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: () async {
                            final result = await showSearchablePicker(
                              context: context,
                              title: 'Customer',
                              selectedValue: _selectedCustomerId,
                              addNewLabel: 'Create new customer',
                              addNewValue: '__create_new__',
                              items: customers.map((c) => PickerItem(
                                value: c.id,
                                label: c.name,
                                subtitle: c.email.isNotEmpty ? c.email : null,
                                icon: Icons.person_rounded,
                                iconColor: AppTheme.primaryColor,
                              )).toList(),
                            );
                            if (result == '__create_new__') {
                              final navResult = await Navigator.pushNamed(context, AppRoutes.addCustomer);
                              if (navResult is String && navResult.isNotEmpty && mounted) {
                                final c = context.read<CustomerProvider>().getCustomerById(navResult);
                                setState(() {
                                  _selectedCustomerId = navResult;
                                  _selectedCustomerName = c?.name ?? '';
                                });
                              }
                              return;
                            }
                            if (result != null && mounted) {
                              final c = context.read<CustomerProvider>().getCustomerById(result);
                              setState(() {
                                _selectedCustomerId = result;
                                _selectedCustomerName = c?.name ?? '';
                              });
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Customer *',
                              prefixIcon: Icon(Icons.person_rounded),
                            ),
                            child: Text(
                              _selectedCustomerName.isNotEmpty ? _selectedCustomerName : 'Select customer',
                              style: TextStyle(
                                color: _selectedCustomerName.isNotEmpty ? null : AppTheme.textSec(context),
                              ),
                            ),
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
                        Row(
                          children: [
                            Expanded(
                              child: Text('Items',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                                      color: AppTheme.textPri(context))),
                            ),
                            TextButton.icon(
                              onPressed: _addItem,
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('Add Item'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...List.generate(_items.length, (index) {
                          final item = _items[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.inputFill(context),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.inputBorder(context)),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: InkWell(
                                          onTap: () => _showProductPicker(index),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 14),
                                            decoration: BoxDecoration(
                                              border: Border.all(color: AppTheme.inputBorder(context)),
                                              borderRadius: BorderRadius.circular(12),
                                              color: AppTheme.surface(context),
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    item.productName.isNotEmpty
                                                        ? item.productName
                                                        : 'Select product...',
                                                    style: TextStyle(
                                                      color: item.productName.isNotEmpty
                                                          ? AppTheme.textPri(context)
                                                          : AppTheme.textSec(context),
                                                      fontWeight: item.productName.isNotEmpty
                                                          ? FontWeight.w600 : FontWeight.normal,
                                                    ),
                                                  ),
                                                ),
                                                if (item.productId != null)
                                                  Text('${item.availableStock} ${item.unit}',
                                                      style: TextStyle(fontSize: 12,
                                                          color: AppTheme.getStockColor(
                                                              item.availableStock),
                                                          fontWeight: FontWeight.w600)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (_items.length > 1) ...[
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(Icons.remove_circle_rounded,
                                              color: AppTheme.dangerColor),
                                          onPressed: () => _removeItem(index),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          controller: item.qtyController,
                                          decoration: InputDecoration(
                                            labelText: 'Qty *',
                                            isDense: true,
                                            suffixText: item.unit,
                                          ),
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                          onChanged: (_) => setState(() {}),
                                          validator: (v) {
                                            if (item.productId == null) return null;
                                            if (v == null || v.isEmpty) return 'Required';
                                            final qty = int.tryParse(v);
                                            if (qty == null || qty <= 0) return 'Invalid';
                                            if (qty > item.availableStock) {
                                              return 'Max ${item.availableStock}';
                                            }
                                            return null;
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
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
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    useContentVariant: true,
                    child: Row(
                      children: [
                        Text('Total Amount',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                                color: AppTheme.textPri(context))),
                        const Spacer(),
                        Text(
                          currencyFormat.format(_totalAmount),
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                              color: AppTheme.primaryColor),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : () => _saveOrder(asDraft: true),
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Save Draft'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : () => _saveOrder(asDraft: false),
                          icon: _isLoading
                              ? const SizedBox(width: 20, height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.check_rounded),
                          label: const Text('Confirm'),
                        ),
                      ),
                    ],
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
