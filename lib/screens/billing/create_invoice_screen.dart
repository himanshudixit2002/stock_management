// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../config/permissions.dart';
import '../../widgets/permission_gate.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/billing_settings_model.dart';
import '../../models/invoice_model.dart';
import '../../providers/price_list_provider.dart';
import '../../services/credit_control_service.dart';
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
import '../../utils/currency.dart';

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

  /// True once a save has been attempted, so inline errors only appear after
  /// the user has actually tried to submit.
  bool _submitted = false;

  /// Why the party section is invalid, or null.
  String? get _partyError {
    if (!_submitted) return null;
    if (_invoiceType == InvoiceType.sales && _selectedCustomerId == null) {
      return 'Choose the customer this invoice is for';
    }
    if (_invoiceType == InvoiceType.purchase && _selectedVendorId == null) {
      return 'Choose the vendor this bill is from';
    }
    return null;
  }

  /// Why the items section is invalid, or null.
  String? get _itemsError {
    if (!_submitted) return null;
    if (_items.every((i) => i.productId == null)) {
      return 'Add at least one item before saving';
    }
    return null;
  }

  /// Whether anything has been entered worth warning about on the way out.
  ///
  /// This screen holds up to 1,410 lines' worth of entry and had no guard at
  /// all — one back gesture discarded the lot silently.
  bool get _isDirty =>
      _selectedCustomerId != null ||
      _selectedVendorId != null ||
      _notesCtrl.text.trim().isNotEmpty ||
      _items.any((i) => i.productId != null);

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
  double get _invoiceDiscount => _totals.invoiceDiscount;

  double get _totalTax => _totals.totalTax;

  double get _grandTotal => _totals.grandTotal;

  Future<void> _save({required bool asDraft}) async {
    // Errors are shown inline against the section that is wrong as well as
    // scrolled to. A transient snackbar was the only feedback before, so the
    // message was gone by the time the offending section was on screen.
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;
    if (_partyError != null) {
      _scrollSectionIntoView(_partySectionKey);
      return;
    }
    final validItems = _items.where((i) => i.productId != null).toList();
    if (_itemsError != null) {
      _scrollSectionIntoView(_itemsSectionKey);
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
      invoiceDiscount: _invoiceDiscount,
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

    // A sales invoice that is not a draft is credit extended to the customer,
    // so their limit is checked before it is written rather than reported
    // afterwards by the credit dashboard. Drafts and purchases are unaffected.
    if (!asDraft &&
        _invoiceType == InvoiceType.sales &&
        (_selectedCustomerId ?? '').isNotEmpty) {
      final customers = context.read<CustomerProvider>().customers;
      final idx = customers.indexWhere((c) => c.id == _selectedCustomerId);
      if (idx != -1) {
        final exposure = CreditControlService.exposureAfterSale(
          customer: customers[idx],
          invoices: billing.invoices,
          amount: _grandTotal,
        );
        if (exposure.isBlocked) {
          setState(() => _isSaving = false);
          showErrorSnackBar(
            context,
            '${customers[idx].name}: ${exposure.reason} Save it as a draft, or '
            'clear the balance first.',
          );
          return;
        }
        if (exposure.verdict == CreditVerdict.warning &&
            exposure.reason.isNotEmpty) {
          showInfoSnackBar(context, '${customers[idx].name}: ${exposure.reason}');
        }
      }
    }

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
    // Block invoice creation when billing is disabled for the company, even if
    // the user still holds the create-invoices permission and reaches this
    // screen via a stale/deep route — entry points are hidden, writes blocked.
    if (!context.watch<BillingSettingsProvider>().billingEnabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('Billing Disabled')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.receipt_long_rounded,
                  size: 64,
                  color: AppTheme.warningColor,
                ),
                const SizedBox(height: 16),
                Text(
                  'Billing is turned off',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPri(context),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'An admin can turn it on in Settings → Workspace features.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSec(context),
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Go Back'),
                  // The theme makes buttons full width; a lone back button
                  // stretched across a desktop window.
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(160, 48),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final bs = context.watch<BillingSettingsProvider>().settings;
    final sym = Money.symbolOrFallback(bs.currencySymbol);

    final isSales = _invoiceType == InvoiceType.sales;
    final appBarTitle = widget.salesOrderId != null
        ? 'Invoice from Order'
        : widget.purchaseOrderId != null
        ? 'Bill from PO'
        : _invoiceType == InvoiceType.purchase
        ? 'New Purchase Bill'
        : 'New Invoice';

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !mounted) return;
        // confirmDiscardChanges is already used by seven other forms; this one
        // was the largest and the only unguarded one.
        final discard = await confirmDiscardChanges(
          context,
          hasChanges: _isDirty,
        );
        if (discard && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
      appBar: AppBar(
        title: AppBarTitleRow(
          icon: Icons.receipt_long_rounded,
          color: AppTheme.primary(context),
          title: appBarTitle,
        ),
      ),
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
                      // A purchase bill needs a vendor, so the choice is only
                      // offered while vendors are switched on and visible.
                      if (widget.salesOrderId == null &&
                          widget.purchaseOrderId == null &&
                          _canBillPurchases(context)) ...[
                        _buildTypeToggle(),
                        const SizedBox(height: 16),
                      ],
                      KeyedSubtree(
                        key: _partySectionKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            isSales
                                ? _buildCustomerSection()
                                : _buildVendorSection(),
                            _SectionError(message: _partyError),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildDateSection(bs),
                      const SizedBox(height: 16),
                      KeyedSubtree(
                        key: _itemsSectionKey,
                        child: _buildItemsSection(bs),
                      ),
                      _SectionError(message: _itemsError),
                      if (bs.enableDiscounts) ...[
                        const SizedBox(height: 16),
                        _buildDiscountSection(),
                      ],
                      const SizedBox(height: 16),
                      _buildTotals(sym, bs),
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
      ),
    );
  }

  bool _canBillPurchases(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    return context.watch<SettingsProvider>().vendorsEnabled &&
        (user?.hasPermission(AppPermissions.viewVendors) ?? false);
  }

  /// "+ Add new customer" as a real button: it was 12 px text with a tap
  /// target no taller than its line, and showed to people who may not add one.
  Widget _addPartyLink({
    required String label,
    required String permission,
    required VoidCallback onTap,
  }) {
    final user = context.watch<AuthProvider>().currentUser;
    if (!(user?.hasPermission(permission) ?? false)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: TextButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text(label),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.centerLeft,
          textStyle: const TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
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
          _addPartyLink(
            label: 'Add new vendor',
            permission: AppPermissions.addVendors,
            onTap: () => Navigator.pushNamed(context, AppRoutes.addVendor),
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
          _addPartyLink(
            label: 'Add new customer',
            permission: AppPermissions.addCustomers,
            onTap: () => Navigator.pushNamed(context, AppRoutes.addCustomer),
          ),
        ],
      ),
    );
  }

  /// One line inside Invoice details. It used to be a card of its own, a
  /// screen's height away from the dates it belongs with.
  Widget _buildNextNumberLine(BillingSettings bs) {
    final preview = _invoiceType == InvoiceType.purchase
        ? bs.formatPurchaseNumber(bs.nextPurchaseNumber)
        : bs.formatInvoiceNumber(bs.nextInvoiceNumber);
    return Tooltip(
      message:
          'The final number is assigned when you save. If someone else saves '
          'first, yours takes the next one.',
      child: Row(
        children: [
          Icon(Icons.tag_rounded, size: 16, color: AppTheme.textSec(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: preview,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPri(context),
                    ),
                  ),
                  const TextSpan(text: '  ·  assigned when you save'),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: AppTheme.textSec(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSection(BillingSettings bs) {
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
          _buildNextNumberLine(bs),
          const SizedBox(height: 12),
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
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: termOptions.contains(_paymentTermDays)
                ? _paymentTermDays
                : null,
            // Outlined and unfilled like the date boxes above it; the theme's
            // filled grey made it look like a different kind of control.
            decoration: InputDecoration(
              labelText: 'Payment Terms',
              isDense: true,
              filled: false,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppTheme.dividerC(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppTheme.dividerC(context)),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
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
          Text(
            'Line Items',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textTer(context),
            ),
          ),
          const SizedBox(height: 10),
          ...List.generate(_items.length, (i) => _buildItemRow(i, bs)),
          // Under the lines it adds to, full width. As a small text button in
          // the header its label sat inset from every edge below it.
          OutlinedButton.icon(
            onPressed: () => setState(
              () => _items.add(
                _LineItem()..taxCtrl.text = bs.defaultTaxRate.toString(),
              ),
            ),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add item'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
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
                    if (result != null && mounted) {
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
                        // A single-unit product has no loose-pieces field, so
                        // none may linger from the product picked before.
                        if (result.unitsPerPack <= 1) item.pieceCtrl.text = '0';
                        // Sales lines price through the customer's price
                        // list when they are on one, so a wholesale customer
                        // is not quoted the retail price and corrected by
                        // hand. Purchases are supplier-side and unaffected.
                        final price = _invoiceType == InvoiceType.purchase
                            ? result.costPrice
                            : context.read<PriceListProvider>().priceFor(
                                product: result,
                                customerId: _selectedCustomerId ?? '',
                                quantity: item.baseQuantity,
                              ).unitPrice;
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
              if (_items.length > 1) ...[
                const SizedBox(width: 4),
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
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                ),
              ],
            ],
          ),
          if (item.productId != null) ...[
            const SizedBox(height: 8),
            _buildItemFields(item, bs),
          ],
        ],
      ),
    );
  }

  /// Quantity, price, discount and tax for one line.
  ///
  /// Five fields used to share one row at every width, about 45 px each on a
  /// phone. Narrow screens now put quantities on one row and money on the
  /// next. A product sold in single units gets one quantity field: it used to
  /// get two, both labelled "pcs".
  Widget _buildItemFields(_LineItem item, dynamic bs) {
    Widget field(
      TextEditingController controller,
      String label, {
      bool decimal = false,
    }) => TextFormField(
      controller: controller,
      decoration: _fieldDeco(label),
      keyboardType: decimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.number,
      inputFormatters: decimal
          ? null
          : [FilteringTextInputFormatter.digitsOnly],
      onChanged: (_) => setState(() {}),
    );

    final quantities = <Widget>[
      if (item.unitsPerPack > 1) ...[
        field(item.qtyCtrl, 'Qty (${item.packUnit})'),
        field(item.pieceCtrl, '+ ${item.baseUnit}'),
      ] else
        field(item.qtyCtrl, 'Qty (${item.baseUnit})'),
    ];
    final money = <(Widget, int)>[
      (field(item.priceCtrl, 'Price', decimal: true), 2),
      if (bs.enableDiscounts) (field(item.discCtrl, 'Disc %', decimal: true), 1),
      if (bs.enableTax) (field(item.taxCtrl, 'Tax %', decimal: true), 1),
    ];

    Widget row(List<(Widget, int)> cells) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(flex: cells[i].$2, child: cells[i].$1),
        ],
      ],
    );

    final qtyCells = [for (final w in quantities) (w, 1)];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 520) return row([...qtyCells, ...money]);
        return Column(
          children: [row(qtyCells), const SizedBox(height: 8), row(money)],
        );
      },
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

  Widget _buildTotals(String sym, dynamic bs) {
    return GlassPanel(
      borderRadius: 14,
      useContentVariant: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          _TotalRow(
            label: 'Subtotal',
            value: '$sym${Money.number(_subtotal)}',
          ),
          if (bs.enableDiscounts && _totalDiscount > 0)
            _TotalRow(
              label: 'Discount',
              value: '- $sym${Money.number(_totalDiscount)}',
              color: AppTheme.dangerColor,
            ),
          if (bs.enableTax && _totalTax > 0)
            _TotalRow(
              label: bs.taxLabel,
              value: '$sym${Money.number(_totalTax)}',
            ),
          const Divider(height: 16),
          _TotalRow(
            label: 'Grand Total',
            value: '$sym${Money.number(_grandTotal)}',
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
              color: AppTheme.textSec(context),
            ),
            const SizedBox(width: 8),
            // Expanded so the label and date shorten rather than overflow on
            // a narrow phone or at larger text sizes.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSec(context),
                    ),
                  ),
                  Text(
                    DateFormat('dd MMM yyyy').format(date),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPri(context),
                    ),
                  ),
                ],
              ),
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
        children: [
          // The label gives way to the amount; neither could shrink before,
          // and both inherited the theme's grey body text.
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: size,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color: bold
                    ? AppTheme.textPri(context)
                    : AppTheme.textSec(context),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: size,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: color ?? AppTheme.textPri(context),
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

/// An inline validation message for a whole section.
///
/// The invoice form validated imperatively at submit time and reported problems
/// through a transient snackbar, which had usually disappeared by the time the
/// offending section was scrolled into view.
class _SectionError extends StatelessWidget {
  const _SectionError({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: AppTheme.danger(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.danger(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
