import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../config/permissions.dart';
import '../../widgets/permission_gate.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/purchase_order_model.dart';
import '../../models/return_model.dart';
import '../../models/sales_order_model.dart';
import '../../providers/return_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/vendor_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/sales_order_provider.dart';
import '../../providers/purchase_order_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/product_picker.dart';
import '../../widgets/searchable_picker.dart';
import '../../widgets/success_overlay.dart';
import '../../config/app_navigation.dart';
import '../../utils/unit_conversion.dart';

class CreateReturnScreen extends StatefulWidget {
  const CreateReturnScreen({super.key});

  @override
  State<CreateReturnScreen> createState() => _CreateReturnScreenState();
}

class _ReturnItemRow {
  String? productId;
  String productName = '';
  String baseUnit = 'pcs';
  String packUnit = 'box';
  int unitsPerPack = 1;
  final TextEditingController qtyController = TextEditingController(); // packs
  final TextEditingController pieceController = TextEditingController();
  final TextEditingController reasonController = TextEditingController();

  int get baseQuantity => toBaseQuantity(
    packs: int.tryParse(qtyController.text) ?? 0,
    pieces: int.tryParse(pieceController.text) ?? 0,
    unitsPerPack: unitsPerPack,
  );

  void dispose() {
    qtyController.dispose();
    pieceController.dispose();
    reasonController.dispose();
  }
}

class _CreateReturnScreenState extends State<CreateReturnScreen> {
  final _formKey = GlobalKey<FormState>();
  ReturnType _returnType = ReturnType.customerReturn;
  String? _selectedPartyId;
  String _selectedPartyName = '';
  String _relatedOrderId = '';
  String _relatedOrderSummary = '';
  final _notesController = TextEditingController();
  final _orderSearchController = TextEditingController();
  final List<_ReturnItemRow> _items = [_ReturnItemRow()];
  bool _isLoading = false;

  @override
  void dispose() {
    _notesController.dispose();
    _orderSearchController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _addItem() => setState(() => _items.add(_ReturnItemRow()));

  void _removeItem(int index) {
    if (_items.length <= 1) return;
    setState(() {
      _items[index].dispose();
      _items.removeAt(index);
    });
  }

  void _switchReturnType(ReturnType type) {
    setState(() {
      _returnType = type;
      _selectedPartyId = null;
      _selectedPartyName = '';
      _relatedOrderId = '';
      _relatedOrderSummary = '';
    });
  }

  Future<void> _saveReturn() async {
    if (!_formKey.currentState!.validate()) return;

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
    final returnItems = validItems
        .map(
          (i) => ReturnItem(
            productId: i.productId!,
            productName: i.productName,
            quantity: i.baseQuantity,
            reason: i.reasonController.text.trim(),
          ),
        )
        .toList();

    final returnModel = ReturnModel(
      id: '',
      type: _returnType,
      relatedOrderId: _relatedOrderId,
      relatedOrderSummary: _relatedOrderSummary,
      customerId: _returnType == ReturnType.customerReturn
          ? (_selectedPartyId ?? '')
          : '',
      customerName: _returnType == ReturnType.customerReturn
          ? _selectedPartyName
          : '',
      vendorId: _returnType == ReturnType.vendorReturn
          ? (_selectedPartyId ?? '')
          : '',
      vendorName: _returnType == ReturnType.vendorReturn
          ? _selectedPartyName
          : '',
      items: returnItems,
      status: ReturnStatus.pending,
      notes: _notesController.text.trim(),
      createdBy: user.uid,
      createdByName: user.name,
      createdAt: now,
      updatedAt: now,
    );

    final id = await context.read<ReturnProvider>().addReturn(returnModel);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (id != null) {
      HapticFeedback.mediumImpact();
      showSuccessOverlay(context, message: 'Return created');
    } else {
      showErrorSnackBar(
        context,
        context.read<ReturnProvider>().errorMessage ??
            'Failed to create return',
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
    });
  }

  void _showOrderLookup() {
    final isCustomer = _returnType == ReturnType.customerReturn;
    final dateFmt = DateFormat('dd MMM yyyy');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: Responsive.sheetConstraints(context),
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        if (isCustomer) {
          var orders = context.read<SalesOrderProvider>().orders.toList();
          if (_selectedPartyId != null) {
            orders = orders
                .where((o) => o.customerId == _selectedPartyId)
                .toList();
          }
          return _buildOrderLookupSheet(
            orders.map((o) => _orderRefFromSales(o, dateFmt)).toList(),
            emptyMessage: _selectedPartyId == null
                ? 'Select a customer above to list their sales orders, or all orders are shown below.'
                : 'No sales orders for this customer.',
            showAllHint: _selectedPartyId == null,
          );
        } else {
          var orders = context.read<PurchaseOrderProvider>().orders.toList();
          if (_selectedPartyId != null) {
            orders = orders
                .where((o) => o.vendorId == _selectedPartyId)
                .toList();
          }
          return _buildOrderLookupSheet(
            orders.map((o) => _orderRefFromPurchase(o, dateFmt)).toList(),
            emptyMessage: _selectedPartyId == null
                ? 'Select a vendor above to filter purchase orders, or all orders are shown below.'
                : 'No purchase orders for this vendor.',
            showAllHint: _selectedPartyId == null,
          );
        }
      },
    );
  }

  _OrderRef _orderRefFromSales(SalesOrderModel o, DateFormat dateFmt) {
    final preview = o.items
        .take(4)
        .map((i) {
          final name = i.productName.isNotEmpty ? i.productName : i.productId;
          return '$name ×${i.quantity}';
        })
        .join(', ');
    final more = o.items.length > 4 ? '… +${o.items.length - 4} more' : '';
    final detail =
        '${o.statusLabel} · ${dateFmt.format(o.createdAt)} · ${o.items.length} line(s) · Total ${o.totalAmount.toStringAsFixed(2)}';
    final summary = [
      'Sales order · ${o.customerName.isNotEmpty ? o.customerName : 'Customer'} · ${o.statusLabel}',
      detail,
      if (preview.isNotEmpty) 'Lines: $preview$more',
      'Document ID: ${o.id}',
    ].join('\n');
    return _OrderRef(
      id: o.id,
      title: o.customerName.isNotEmpty ? o.customerName : 'Sales order',
      badge: o.statusLabel,
      detailLine: detail,
      productLine: preview.isEmpty ? 'No line items' : '$preview$more',
      summaryForStorage: summary,
    );
  }

  _OrderRef _orderRefFromPurchase(PurchaseOrderModel o, DateFormat dateFmt) {
    final preview = o.items
        .take(4)
        .map((i) {
          final name = i.productName.isNotEmpty ? i.productName : i.productId;
          return '$name ×${i.quantity} (rcvd ${i.receivedQuantity})';
        })
        .join(', ');
    final more = o.items.length > 4 ? '… +${o.items.length - 4} more' : '';
    final detail =
        '${o.statusLabel} · ${dateFmt.format(o.createdAt)} · ${o.items.length} line(s) · Total ${o.totalAmount.toStringAsFixed(2)}';
    final summary = [
      'Purchase order · ${o.vendorName.isNotEmpty ? o.vendorName : 'Vendor'} · ${o.statusLabel}',
      detail,
      if (preview.isNotEmpty) 'Lines: $preview$more',
      'Document ID: ${o.id}',
    ].join('\n');
    return _OrderRef(
      id: o.id,
      title: o.vendorName.isNotEmpty ? o.vendorName : 'Purchase order',
      badge: o.statusLabel,
      detailLine: detail,
      productLine: preview.isEmpty ? 'No line items' : '$preview$more',
      summaryForStorage: summary,
    );
  }

  Widget _buildOrderLookupSheet(
    List<_OrderRef> orders, {
    required String emptyMessage,
    required bool showAllHint,
  }) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.emptyIcon(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select related order',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                if (showAllHint) ...[
                  const SizedBox(height: 6),
                  Text(
                    emptyMessage,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSec(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: orders.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        emptyMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textSec(context)),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: orders.length,
                    itemBuilder: (context, idx) {
                      final o = orders[idx];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        elevation: 0,
                        color: AppTheme.inputFill(context),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: AppTheme.inputBorder(context),
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            setState(() {
                              _relatedOrderId = o.id;
                              _relatedOrderSummary = o.summaryForStorage;
                            });
                            Navigator.pop(context);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        o.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryColor.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        o.badge,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.primaryColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  o.detailLine,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSec(context),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  o.productLine,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textSec(context),
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'ID: ${o.id}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppTheme.iconMute(context),
                                    fontFamily: 'monospace',
                                  ),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.createReturns,
      featureName: 'Create Return',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {

    final customers = context.watch<CustomerProvider>().activeCustomers;
    final vendors = context.watch<VendorProvider>().activeVendors;

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: const AppBarTitleRow(
          icon: Icons.assignment_return_rounded,
          color: AppTheme.warningColor,
          title: 'Create Return',
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
                          'Return Type',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPri(context),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _typeChip(
                                'Customer Return',
                                ReturnType.customerReturn,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _typeChip(
                                'Vendor Return',
                                ReturnType.vendorReturn,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (_returnType == ReturnType.customerReturn)
                          GestureDetector(
                            onTap: () async {
                              final result = await showSearchablePicker(
                                context: context,
                                title: 'Customer',
                                selectedValue: _selectedPartyId,
                                addNewLabel: 'Create new customer',
                                addNewValue: '__create_new__',
                                items: customers
                                    .map(
                                      (c) => PickerItem(
                                        value: c.id,
                                        label: c.name,
                                        subtitle: c.email.isNotEmpty
                                            ? c.email
                                            : null,
                                        icon: Icons.person_rounded,
                                        iconColor: AppTheme.primaryColor,
                                      ),
                                    )
                                    .toList(),
                              );
                              if (result == '__create_new__') {
                                final navResult = await context.pushAppRoute(
                                  AppRoutes.addCustomer,
                                );
                                if (navResult is String &&
                                    navResult.isNotEmpty &&
                                    mounted) {
                                  final c = context
                                      .read<CustomerProvider>()
                                      .getCustomerById(navResult);
                                  setState(() {
                                    _selectedPartyId = navResult;
                                    _selectedPartyName = c?.name ?? '';
                                  });
                                }
                                return;
                              }
                              if (result != null && mounted) {
                                final c = context
                                    .read<CustomerProvider>()
                                    .getCustomerById(result);
                                setState(() {
                                  _selectedPartyId = result;
                                  _selectedPartyName = c?.name ?? '';
                                });
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Customer',
                                prefixIcon: Icon(Icons.person_rounded),
                              ),
                              child: Text(
                                _selectedPartyName.isNotEmpty
                                    ? _selectedPartyName
                                    : 'Select customer',
                                style: TextStyle(
                                  color: _selectedPartyName.isNotEmpty
                                      ? null
                                      : AppTheme.textSec(context),
                                ),
                              ),
                            ),
                          )
                        else
                          GestureDetector(
                            onTap: () async {
                              final result = await showSearchablePicker(
                                context: context,
                                title: 'Vendor',
                                selectedValue: _selectedPartyId,
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
                                final navResult = await context.pushAppRoute(
                                  AppRoutes.addVendor,
                                );
                                if (navResult is String &&
                                    navResult.isNotEmpty &&
                                    mounted) {
                                  final v = context
                                      .read<VendorProvider>()
                                      .getVendorById(navResult);
                                  setState(() {
                                    _selectedPartyId = navResult;
                                    _selectedPartyName = v?.name ?? '';
                                  });
                                }
                                return;
                              }
                              if (result != null && mounted) {
                                final v = context
                                    .read<VendorProvider>()
                                    .getVendorById(result);
                                setState(() {
                                  _selectedPartyId = result;
                                  _selectedPartyName = v?.name ?? '';
                                });
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Vendor',
                                prefixIcon: Icon(Icons.local_shipping_rounded),
                              ),
                              child: Text(
                                _selectedPartyName.isEmpty
                                    ? 'Select vendor'
                                    : _selectedPartyName,
                                style: TextStyle(
                                  color: _selectedPartyName.isNotEmpty
                                      ? null
                                      : AppTheme.textSec(context),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        InkWell(
                          onTap: _showOrderLookup,
                          borderRadius: BorderRadius.circular(16),
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Related order (optional)',
                              prefixIcon: Icon(Icons.link_rounded),
                              alignLabelWithHint: true,
                            ),
                            child: _relatedOrderId.isEmpty
                                ? Text(
                                    'Tap to choose — shows party, status, lines, total, full ID',
                                    style: TextStyle(
                                      color: AppTheme.textSec(context),
                                      fontSize: 13,
                                    ),
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _relatedOrderSummary.split('\n').first,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.textPri(context),
                                          fontSize: 14,
                                        ),
                                      ),
                                      if (_relatedOrderSummary.contains(
                                        '\n',
                                      )) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          _relatedOrderSummary
                                              .split('\n')
                                              .skip(1)
                                              .join('\n'),
                                          style: TextStyle(
                                            fontSize: 11,
                                            height: 1.25,
                                            color: AppTheme.textSec(context),
                                          ),
                                        ),
                                      ],
                                    ],
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
                              child: Text(
                                'Items',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPri(context),
                                ),
                              ),
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
                                              horizontal: 12,
                                              vertical: 14,
                                            ),
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                color: AppTheme.inputBorder(
                                                  context,
                                                ),
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              color: AppTheme.surface(context),
                                            ),
                                            child: Text(
                                              item.productName.isNotEmpty
                                                  ? item.productName
                                                  : 'Select product...',
                                              style: TextStyle(
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
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.remove_circle_rounded,
                                            color: AppTheme.dangerColor,
                                          ),
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
                                            labelText:
                                                '${item.packUnit} Qty *',
                                            isDense: true,
                                          ),
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                          ],
                                          validator: (v) {
                                            if (item.productId == null)
                                              return null;
                                            final baseQty = toBaseQuantity(
                                              packs:
                                                  int.tryParse(v ?? '') ?? 0,
                                              pieces: int.tryParse(
                                                    item.pieceController.text,
                                                  ) ??
                                                  0,
                                              unitsPerPack:
                                                  item.unitsPerPack,
                                            );
                                            if (baseQty <= 0)
                                              return 'Required';
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
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 2,
                                        child: TextFormField(
                                          controller: item.reasonController,
                                          decoration: const InputDecoration(
                                            labelText: 'Reason',
                                            isDense: true,
                                          ),
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
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _saveReturn,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded),
                    label: const Text('Submit Return'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.warningColor,
                      minimumSize: const Size(double.infinity, 52),
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

  Widget _typeChip(String label, ReturnType type) {
    final isSelected = _returnType == type;
    return InkWell(
      onTap: () => _switchReturnType(type),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withValues(alpha: 0.12)
              : AppTheme.inputFill(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryColor
                : AppTheme.inputBorder(context),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isSelected
                  ? AppTheme.primaryColor
                  : AppTheme.textSec(context),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderRef {
  final String id;
  final String title;
  final String badge;
  final String detailLine;
  final String productLine;
  final String summaryForStorage;
  _OrderRef({
    required this.id,
    required this.title,
    required this.badge,
    required this.detailLine,
    required this.productLine,
    required this.summaryForStorage,
  });
}
