import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/permissions.dart';
import '../../widgets/permission_gate.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/billing_settings_model.dart';
import '../../models/invoice_model.dart';
import '../../providers/billing_provider.dart';
import '../../providers/billing_settings_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/sales_order_provider.dart';
import '../../providers/vendor_provider.dart';
import '../../providers/purchase_order_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/dialogs.dart';
import '../../utils/invoice_totals.dart';
import '../../utils/responsive.dart';
import '../../utils/unit_conversion.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/searchable_picker.dart'
    show showSearchablePicker, PickerItem;
import '../../widgets/success_overlay.dart';

class _LineItem {
  String? productId;
  String productName = '';
  String unit = 'box';
  String baseUnit = 'pcs';
  String packUnit = 'box';
  int unitsPerPack = 1;
  final TextEditingController qtyCtrl = TextEditingController(text: '1'); // packs
  final TextEditingController pieceCtrl = TextEditingController(text: '0');
  final TextEditingController priceCtrl = TextEditingController();
  final TextEditingController discCtrl = TextEditingController(text: '0');
  final TextEditingController taxCtrl = TextEditingController();

  int get baseQuantity => toBaseQuantity(
    packs: int.tryParse(qtyCtrl.text) ?? 0,
    pieces: int.tryParse(pieceCtrl.text) ?? 0,
    unitsPerPack: unitsPerPack,
  );

  void dispose() {
    qtyCtrl.dispose();
    pieceCtrl.dispose();
    priceCtrl.dispose();
    discCtrl.dispose();
    taxCtrl.dispose();
  }
}

class CreateInvoiceScreen extends StatefulWidget {
  final String? salesOrderId;
  final String? purchaseOrderId;
  final InvoiceType initialType;
  final String? preselectedVendorId;
  final String? preselectedVendorName;
  final String? preselectedCustomerId;
  final String? preselectedCustomerName;
  const CreateInvoiceScreen({
    super.key,
    this.salesOrderId,
    this.purchaseOrderId,
    this.initialType = InvoiceType.sales,
    this.preselectedVendorId,
    this.preselectedVendorName,
    this.preselectedCustomerId,
    this.preselectedCustomerName,
  });

  @override
  State<CreateInvoiceScreen> createState() => _CreateInvoiceScreenState();
}

class _CreateInvoiceScreenState extends State<CreateInvoiceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  final _partySectionKey = GlobalKey();
  final _itemsSectionKey = GlobalKey();
  late InvoiceType _invoiceType;
  String? _selectedCustomerId;
  String _selectedCustomerName = '';
  String _selectedCustomerPhone = '';
  String _selectedCustomerAddress = '';
  String? _selectedVendorId;
  String _selectedVendorName = '';
  DateTime _invoiceDate = DateTime.now();
  DateTime _dueDate = DateTime.now();
  final _notesCtrl = TextEditingController();
  final _discountPctCtrl = TextEditingController(text: '0');
  final _discountAmtCtrl = TextEditingController(text: '0');
  final List<_LineItem> _items = [_LineItem()];
  bool _isSaving = false;
  int _paymentTermDays = 0;

  InvoiceTotals get _totals {
    final bs = context.read<BillingSettingsProvider>().settings;
    final lines = _items
        .where((item) => item.productId != null)
        .map(
          (item) => InvoiceTotalsLineInput(
            quantity: item.baseQuantity,
            unitPrice: double.tryParse(item.priceCtrl.text) ?? 0,
            lineDiscountPercent: double.tryParse(item.discCtrl.text) ?? 0,
            lineTaxRate: double.tryParse(item.taxCtrl.text) ?? 0,
          ),
        )
        .toList();
    return calculateInvoiceTotals(
      lines: lines,
      invoiceDiscountPercent: double.tryParse(_discountPctCtrl.text) ?? 0,
      invoiceDiscountAmount: double.tryParse(_discountAmtCtrl.text) ?? 0,
      taxEnabled: bs.enableTax,
      discountEnabled: bs.enableDiscounts,
    );
  }

  @override
  void initState() {
    super.initState();
    _invoiceType = widget.initialType;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bs = context.read<BillingSettingsProvider>().settings;
      _paymentTermDays = bs.defaultPaymentTermDays;
      _dueDate = _invoiceDate.add(Duration(days: _paymentTermDays));
      for (final item in _items) {
        item.taxCtrl.text = bs.defaultTaxRate.toString();
      }
      if (bs.defaultNotes.isNotEmpty) {
        _notesCtrl.text = bs.defaultNotes;
      }
      if (widget.preselectedCustomerId != null) {
        _selectedCustomerId = widget.preselectedCustomerId;
        _selectedCustomerName = widget.preselectedCustomerName ?? '';
      }
      if (widget.preselectedVendorId != null) {
        _selectedVendorId = widget.preselectedVendorId;
        _selectedVendorName = widget.preselectedVendorName ?? '';
      }
      if (widget.salesOrderId != null) _prefillFromSalesOrder();
      if (widget.purchaseOrderId != null) _prefillFromPurchaseOrder();
      setState(() {});
    });
  }

  void _prefillFromSalesOrder() {
    final so = context.read<SalesOrderProvider>().getOrderById(
      widget.salesOrderId!,
    );
    if (so == null) return;
    final customers = context.read<CustomerProvider>().customers;
    final customer = customers.where((c) => c.id == so.customerId).firstOrNull;
    setState(() {
      _selectedCustomerId = so.customerId;
      _selectedCustomerName = so.customerName;
      _selectedCustomerPhone = customer?.phone ?? '';
      _selectedCustomerAddress = customer?.address ?? '';
      _items.clear();
      final bs = context.read<BillingSettingsProvider>().settings;
      for (final soItem in so.items) {
        final li = _LineItem()
          ..productId = soItem.productId
          ..productName = soItem.productName;
        li.qtyCtrl.text = soItem.quantity.toString();
        li.pieceCtrl.text = '0';
        li.priceCtrl.text = soItem.unitPrice.toString();
        li.taxCtrl.text = bs.defaultTaxRate.toString();
        _items.add(li);
      }
      if (_items.isEmpty) _items.add(_LineItem());
    });
  }

  void _prefillFromPurchaseOrder() {
    final po = context.read<PurchaseOrderProvider>().getOrderById(
      widget.purchaseOrderId!,
    );
    if (po == null) return;
    setState(() {
      _invoiceType = InvoiceType.purchase;
      _selectedVendorId = po.vendorId;
      _selectedVendorName = po.vendorName;
      _items.clear();
      final bs = context.read<BillingSettingsProvider>().settings;
      for (final poItem in po.items) {
        final li = _LineItem()
          ..productId = poItem.productId
          ..productName = poItem.productName;
        li.qtyCtrl.text = poItem.quantity.toString();
        li.pieceCtrl.text = '0';
        li.priceCtrl.text = poItem.unitPrice.toString();
        li.taxCtrl.text = bs.defaultTaxRate.toString();
        _items.add(li);
      }
      if (_items.isEmpty) _items.add(_LineItem());
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _notesCtrl.dispose();
    _discountPctCtrl.dispose();
    _discountAmtCtrl.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _scrollSectionIntoView(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx != null && mounted) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: 0.12,
        );
      }
    });
  }

  double get _subtotal => _totals.subtotal;

  double get _totalDiscount => _totals.totalDiscount;

  double get _totalTax => _totals.totalTax;

  double get _grandTotal => _totals.grandTotal;

  Future<void> _save({required bool asDraft}) async {
    if (!_formKey.currentState!.validate()) return;
    if (_invoiceType == InvoiceType.sales && _selectedCustomerId == null) {
      _scrollSectionIntoView(_partySectionKey);
      showInfoSnackBar(context, 'Please select a customer');
      return;
    }
    if (_invoiceType == InvoiceType.purchase && _selectedVendorId == null) {
      _scrollSectionIntoView(_partySectionKey);
      showInfoSnackBar(context, 'Please select a vendor');
      return;
    }
    final validItems = _items.where((i) => i.productId != null).toList();
    if (validItems.isEmpty) {
      _scrollSectionIntoView(_itemsSectionKey);
      showInfoSnackBar(context, 'Add at least one item');
      return;
    }
    setState(() => _isSaving = true);

    final billing = context.read<BillingProvider>();
    final bs = context.read<BillingSettingsProvider>().settings;
    final user = context.read<AuthProvider>().currentUser!;
    final now = DateTime.now();

    final prefix = _invoiceType == InvoiceType.purchase
        ? bs.purchasePrefix
        : bs.invoicePrefix;
    final invoiceNumber = await billing.getNextInvoiceNumber(
      prefix,
      type: _invoiceType,
    );
    if (invoiceNumber == null) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      showErrorSnackBar(context, 'Could not generate invoice number');
      return;
    }

    final invoiceItems = validItems
        .map(
          (li) => InvoiceItem(
            productId: li.productId!,
            productName: li.productName,
            quantity: li.baseQuantity,
            unit: li.baseUnit,
            unitPrice: double.tryParse(li.priceCtrl.text) ?? 0,
            discountPercent: double.tryParse(li.discCtrl.text) ?? 0,
            taxRate: double.tryParse(li.taxCtrl.text) ?? 0,
          ),
        )
        .toList();

    final invoice = InvoiceModel(
      id: '',
      invoiceType: _invoiceType,
      invoiceNumber: invoiceNumber,
      customerId: _invoiceType == InvoiceType.sales
          ? (_selectedCustomerId ?? '')
          : '',
      customerName: _invoiceType == InvoiceType.sales
          ? _selectedCustomerName
          : '',
      customerPhone: _invoiceType == InvoiceType.sales
          ? _selectedCustomerPhone
          : '',
      customerAddress: _invoiceType == InvoiceType.sales
          ? _selectedCustomerAddress
          : '',
      vendorId: _invoiceType == InvoiceType.purchase
          ? (_selectedVendorId ?? '')
          : '',
      vendorName: _invoiceType == InvoiceType.purchase
          ? _selectedVendorName
          : '',
      status: asDraft ? InvoiceStatus.draft : InvoiceStatus.sent,
      items: invoiceItems,
      discountPercent: double.tryParse(_discountPctCtrl.text) ?? 0,
      discountAmount: double.tryParse(_discountAmtCtrl.text) ?? 0,
      taxLabel: bs.taxLabel,
      subtotal: _subtotal,
      totalDiscount: _totalDiscount,
      totalTax: _totalTax,
      grandTotal: _grandTotal,
      amountDue: _grandTotal,
      invoiceDate: _invoiceDate,
      dueDate: _dueDate,
      notes: _notesCtrl.text.trim(),
      termsText: bs.invoiceFooter,
      linkedSalesOrderId: widget.salesOrderId ?? '',
      linkedPurchaseOrderId: widget.purchaseOrderId ?? '',
      createdBy: user.uid,
      createdByName: user.name,
      createdAt: now,
      updatedAt: now,
    );

    final locations = context.read<SettingsProvider>().locations;
    final defaultLoc = locations.isNotEmpty ? locations.first : 'Main';
    final id = await billing.addInvoice(
      invoice,
      userId: user.uid,
      userName: user.name,
      defaultLocation: defaultLoc,
      autoCreateStandaloneSalesOrder:
          _invoiceType == InvoiceType.sales &&
          (widget.salesOrderId ?? '').isEmpty &&
          bs.autoCreateSalesOrderForStandaloneSales,
      autoCreateStandalonePurchaseOrder:
          _invoiceType == InvoiceType.purchase &&
          (widget.purchaseOrderId ?? '').isEmpty &&
          bs.autoCreatePurchaseOrderForStandaloneBills,
    );
    if (!mounted) return;
    setState(() => _isSaving = false);

    if (id != null) {
      final label = _invoiceType == InvoiceType.purchase ? 'Bill' : 'Invoice';
      await showSuccessOverlay(context, message: '$label $invoiceNumber created');
    } else {
      showErrorSnackBar(
        context,
        billing.errorMessage ?? 'Failed to create invoice',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.createInvoices,
      featureName: 'New Invoice',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {

    final bs = context.watch<BillingSettingsProvider>().settings;
    final sym = bs.currencySymbol.isNotEmpty ? bs.currencySymbol : '₹';
    final numFmt = NumberFormat('#,##0.00');

    final isSales = _invoiceType == InvoiceType.sales;
    final appBarTitle = widget.salesOrderId != null
        ? 'Invoice from Order'
        : widget.purchaseOrderId != null
        ? 'Bill from PO'
        : _invoiceType == InvoiceType.purchase
        ? 'New Purchase Bill'
        : 'New Invoice';

    return Scaffold(
      appBar: AppBar(title: Text(appBarTitle)),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
        child: Form(
        key: _formKey,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Responsive.formMaxWidth(context),
            ),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(
                      Responsive.horizontalPadding(context),
                      12,
                      Responsive.horizontalPadding(context),
                      24,
                    ),
                    children: [
                      if (widget.salesOrderId == null &&
                          widget.purchaseOrderId == null) ...[
                        _buildTypeToggle(),
                        const SizedBox(height: 16),
                      ],
                      KeyedSubtree(
                        key: _partySectionKey,
                        child: isSales
                            ? _buildCustomerSection()
                            : _buildVendorSection(),
                      ),
                      const SizedBox(height: 16),
                      _buildDateSection(),
                      const SizedBox(height: 16),
                      _buildNextNumberPreview(bs),
                      const SizedBox(height: 16),
                      KeyedSubtree(
                        key: _itemsSectionKey,
                        child: _buildItemsSection(bs),
                      ),
                      if (bs.enableDiscounts) ...[
                        const SizedBox(height: 16),
                        _buildDiscountSection(),
                      ],
                      const SizedBox(height: 16),
                      _buildTotals(sym, numFmt, bs),
                      const SizedBox(height: 16),
                      _buildNotesField(),
                    ],
                  ),
                ),
                _buildBottomBar(),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildTypeToggle() {
    return GlassPanel(
      borderRadius: 14,
      useContentVariant: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Invoice Type',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textTer(context),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _TypeChip(
                  label: 'Sales Invoice',
                  icon: Icons.receipt_long_rounded,
                  selected: _invoiceType == InvoiceType.sales,
                  onTap: () => setState(() => _invoiceType = InvoiceType.sales),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TypeChip(
                  label: 'Purchase Bill',
                  icon: Icons.shopping_bag_rounded,
                  selected: _invoiceType == InvoiceType.purchase,
                  onTap: () =>
                      setState(() => _invoiceType = InvoiceType.purchase),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVendorSection() {
    final vendors = context.watch<VendorProvider>().activeVendors;
    return GlassPanel(
      borderRadius: 14,
      useContentVariant: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vendor',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textTer(context),
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () async {
              final value = await showSearchablePicker(
                context: context,
                items: vendors
                    .map(
                      (v) => PickerItem(
                        value: v.id,
                        label: v.name,
                        subtitle: v.phone,
                      ),
                    )
                    .toList(),
                selectedValue: _selectedVendorId,
                title: 'Select Vendor',
              );
              if (value != null) {
                final v = vendors.firstWhere((v) => v.id == value);
                setState(() {
                  _selectedVendorId = v.id;
                  _selectedVendorName = v.name;
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.dividerC(context)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedVendorName.isEmpty
                          ? 'Select vendor'
                          : _selectedVendorName,
                      style: TextStyle(
                        fontSize: 14,
                        color: _selectedVendorName.isEmpty
                            ? AppTheme.textMuted
                            : AppTheme.textPri(context),
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, AppRoutes.addVendor),
            child: Text(
              '+ Add new vendor',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.primaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerSection() {
    final customers = context.watch<CustomerProvider>().activeCustomers;
    return GlassPanel(
      borderRadius: 14,
      useContentVariant: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Customer',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textTer(context),
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () async {
              final value = await showSearchablePicker(
                context: context,
                items: customers
                    .map(
                      (c) => PickerItem(
                        value: c.id,
                        label: c.name,
                        subtitle: c.phone,
                      ),
                    )
                    .toList(),
                selectedValue: _selectedCustomerId,
                title: 'Select Customer',
              );
              if (value != null) {
                final c = customers.firstWhere((c) => c.id == value);
                setState(() {
                  _selectedCustomerId = c.id;
                  _selectedCustomerName = c.name;
                  _selectedCustomerPhone = c.phone;
                  _selectedCustomerAddress = c.address;
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.dividerC(context)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedCustomerName.isEmpty
                          ? 'Select customer'
                          : _selectedCustomerName,
                      style: TextStyle(
                        fontSize: 14,
                        color: _selectedCustomerName.isEmpty
                            ? AppTheme.textMuted
                            : AppTheme.textPri(context),
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () async {
              await Navigator.pushNamed(context, AppRoutes.addCustomer);
            },
            child: Text(
              '+ Add new customer',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.primaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextNumberPreview(BillingSettings bs) {
    final preview = _invoiceType == InvoiceType.purchase
        ? bs.formatPurchaseNumber(bs.nextPurchaseNumber)
        : bs.formatInvoiceNumber(bs.nextInvoiceNumber);
    return GlassPanel(
      borderRadius: 14,
      useContentVariant: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Next number (preview)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textTer(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            preview,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'The final number is assigned when you save. If someone else saves first, yours will use the next sequence.',
            style: TextStyle(fontSize: 11, color: AppTheme.textSec(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSection() {
    final termOptions = [0, 15, 30, 60, 90];
    return GlassPanel(
      borderRadius: 14,
      useContentVariant: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Invoice Details',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textTer(context),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _DateField(
                  label: 'Invoice Date',
                  date: _invoiceDate,
                  onPicked: (d) => setState(() {
                    _invoiceDate = d;
                    _dueDate = d.add(Duration(days: _paymentTermDays));
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DateField(
                  label: 'Due Date',
                  date: _dueDate,
                  onPicked: (d) => setState(() => _dueDate = d),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            value: termOptions.contains(_paymentTermDays)
                ? _paymentTermDays
                : null,
            decoration: InputDecoration(
              labelText: 'Payment Terms',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            items: termOptions
                .map(
                  (d) => DropdownMenuItem(
                    value: d,
                    child: Text(
                      d == 0 ? 'Due on Receipt' : 'Net $d days',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                _paymentTermDays = v;
                _dueDate = _invoiceDate.add(Duration(days: v));
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildItemsSection(dynamic bs) {
    return GlassPanel(
      borderRadius: 14,
      useContentVariant: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Line Items',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textTer(context),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(
                  () => _items.add(
                    _LineItem()..taxCtrl.text = bs.defaultTaxRate.toString(),
                  ),
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Item', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...List.generate(_items.length, (i) => _buildItemRow(i, bs)),
        ],
      ),
    );
  }

  Widget _buildItemRow(int index, dynamic bs) {
    final item = _items[index];
    final products = context.watch<ProductProvider>().allProducts;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    final result = await showSearch(
                      context: context,
                      delegate: _ProductSearchDelegate(products),
                    );
                    if (result != null) {
                      setState(() {
                        item.productId = result.id;
                        item.productName = result.name;
                        item.unit = result.unitsPerPack > 1
                            ? result.packUnit
                            : result.baseUnit;
                        item.packUnit = result.unitsPerPack > 1
                            ? result.packUnit
                            : result.baseUnit;
                        item.baseUnit = result.baseUnit;
                        item.unitsPerPack = result.unitsPerPack;
                        final price = _invoiceType == InvoiceType.purchase
                            ? result.costPrice
                            : result.sellingPrice;
                        item.priceCtrl.text = price > 0 ? price.toString() : '';
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.dividerC(context)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      item.productName.isEmpty
                          ? 'Select product'
                          : item.productName,
                      style: TextStyle(
                        fontSize: 13,
                        color: item.productName.isEmpty
                            ? AppTheme.textMuted
                            : AppTheme.textPri(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (_items.length > 1)
                IconButton(
                  icon: Icon(
                    Icons.remove_circle_outline,
                    color: AppTheme.dangerColor.withValues(alpha: 0.7),
                    size: 20,
                  ),
                  tooltip: 'Remove line item',
                  onPressed: () => setState(() {
                    _items[index].dispose();
                    _items.removeAt(index);
                  }),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
            ],
          ),
          if (item.productId != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: item.qtyCtrl,
                    decoration: _fieldDeco(item.packUnit),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: item.pieceCtrl,
                    decoration: _fieldDeco(item.baseUnit),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: item.priceCtrl,
                    decoration: _fieldDeco('Price'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                if (bs.enableDiscounts) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: item.discCtrl,
                      decoration: _fieldDeco('Disc%'),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
                if (bs.enableTax) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: item.taxCtrl,
                      decoration: _fieldDeco('Tax%'),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _fieldDeco(String label) => InputDecoration(
    labelText: label,
    isDense: true,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    labelStyle: const TextStyle(fontSize: 12),
  );

  Widget _buildDiscountSection() {
    return GlassPanel(
      borderRadius: 14,
      useContentVariant: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Invoice Discount',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textTer(context),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _discountPctCtrl,
                  decoration: _fieldDeco('Discount %'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _discountAmtCtrl,
                  decoration: _fieldDeco('Flat Discount'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTotals(String sym, NumberFormat numFmt, dynamic bs) {
    return GlassPanel(
      borderRadius: 14,
      useContentVariant: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          _TotalRow(
            label: 'Subtotal',
            value: '$sym${numFmt.format(_subtotal)}',
          ),
          if (bs.enableDiscounts && _totalDiscount > 0)
            _TotalRow(
              label: 'Discount',
              value: '- $sym${numFmt.format(_totalDiscount)}',
              color: AppTheme.dangerColor,
            ),
          if (bs.enableTax && _totalTax > 0)
            _TotalRow(
              label: bs.taxLabel,
              value: '$sym${numFmt.format(_totalTax)}',
            ),
          const Divider(height: 16),
          _TotalRow(
            label: 'Grand Total',
            value: '$sym${numFmt.format(_grandTotal)}',
            bold: true,
            size: 16,
          ),
        ],
      ),
    );
  }

  Widget _buildNotesField() {
    return TextFormField(
      controller: _notesCtrl,
      decoration: InputDecoration(
        labelText: 'Notes (optional)',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      maxLines: 3,
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        Responsive.horizontalPadding(context),
        10,
        Responsive.horizontalPadding(context),
        10,
      ),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        border: Border(top: BorderSide(color: AppTheme.dividerC(context))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _isSaving ? null : () => _save(asDraft: true),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Save Draft',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _isSaving ? null : () => _save(asDraft: false),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _invoiceType == InvoiceType.purchase
                            ? 'Create Bill'
                            : 'Create Invoice',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime date;
  final ValueChanged<DateTime> onPicked;
  const _DateField({
    required this.label,
    required this.date,
    required this.onPicked,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (picked != null) onPicked(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.dividerC(context)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today,
              size: 16,
              color: AppTheme.textTer(context),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.textTer(context),
                  ),
                ),
                Text(
                  DateFormat('dd MMM yyyy').format(date),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final double size;
  final Color? color;
  const _TotalRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.size = 13,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: size,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: size,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _TypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: selected
                ? AppTheme.primaryColor.withValues(alpha: 0.12)
                : Colors.transparent,
            border: Border.all(
              color: selected
                  ? AppTheme.primaryColor
                  : AppTheme.dividerC(context),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? AppTheme.primaryColor
                    : AppTheme.textTer(context),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? AppTheme.primaryColor
                      : AppTheme.textSec(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductSearchDelegate extends SearchDelegate {
  final List products;
  _ProductSearchDelegate(this.products);

  @override
  List<Widget>? buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  @override
  Widget buildResults(BuildContext context) => _buildList();

  @override
  Widget buildSuggestions(BuildContext context) => _buildList();

  Widget _buildList() {
    final q = query.toLowerCase();
    final filtered = products
        .where((p) => p.name.toLowerCase().contains(q))
        .toList();
    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, i) {
        final p = filtered[i];
        return ListTile(
          title: Text(p.name),
          subtitle: Text('Stock: ${p.quantity} ${p.unit}'),
          trailing: Text(
            '${p.sellingPrice}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          onTap: () => close(context, p),
        );
      },
    );
  }
}
