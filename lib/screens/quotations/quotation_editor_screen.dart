import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../models/customer_model.dart';
import '../../models/quotation_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/billing_settings_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/price_list_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/quotation_provider.dart';
import '../../utils/currency.dart';
import '../../utils/dialogs.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/entity_picker_field.dart';
import '../../widgets/form_section.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/product_picker.dart';
import '../../widgets/searchable_picker.dart';

/// Writes or edits a quotation.
class QuotationEditorScreen extends StatefulWidget {
  const QuotationEditorScreen({super.key, this.quotation});

  final QuotationModel? quotation;

  @override
  State<QuotationEditorScreen> createState() => _QuotationEditorScreenState();
}

class _QuotationEditorScreenState extends State<QuotationEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _quoteNumber = TextEditingController();
  final _notes = TextEditingController();
  final _terms = TextEditingController();

  String _customerId = '';
  String _customerName = '';
  String _customerPhone = '';
  DateTime? _validUntil;
  List<QuotationLine> _lines = [];

  bool get _isEditing => widget.quotation != null;

  @override
  void initState() {
    super.initState();
    final quotation = widget.quotation;
    if (quotation != null) {
      _quoteNumber.text = quotation.quoteNumber;
      _notes.text = quotation.notes;
      _terms.text = quotation.termsText;
      _customerId = quotation.customerId;
      _customerName = quotation.customerName;
      _customerPhone = quotation.customerPhone;
      _validUntil = quotation.validUntil;
      _lines = [...quotation.lines];
    } else {
      // Two weeks is the default nobody has to think about, and it is the
      // reason a quote can lapse at all: a quote with no date is a price
      // promised forever.
      _validUntil = DateTime.now().add(const Duration(days: 14));
      _terms.text =
          context.read<BillingSettingsProvider>().settings.invoiceFooter;
    }
  }

  @override
  void dispose() {
    _quoteNumber.dispose();
    _notes.dispose();
    _terms.dispose();
    super.dispose();
  }

  Future<void> _pickCustomer() async {
    final customers = context.read<CustomerProvider>().customers;
    final selected = await showSearchablePicker(
      context: context,
      title: 'Choose a customer',
      selectedValue: _customerId.isEmpty ? null : _customerId,
      items: [
        for (final c in customers)
          PickerItem(
            value: c.id,
            label: c.name,
            subtitle: c.phone.isEmpty ? c.company : c.phone,
            icon: Icons.person_rounded,
          ),
      ],
    );
    if (selected == null || !mounted) return;
    final customer = customers.firstWhere(
      (c) => c.id == selected,
      orElse: () => CustomerModel(
        id: selected,
        name: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    setState(() {
      _customerId = customer.id;
      _customerName = customer.name;
      _customerPhone = customer.phone;
      _repriceLines();
    });
  }

  /// Re-applies the customer's price list to every line.
  ///
  /// Choosing the customer after the lines are keyed in is the normal order of
  /// events, so the quote is repriced rather than left on whatever the first
  /// pick happened to use — the same rule Fast POS follows at the counter.
  void _repriceLines() {
    final products = context.read<ProductProvider>().analyticsProducts;
    final pricing = context.read<PriceListProvider>();
    _lines = [
      for (final line in _lines)
        () {
          final idx = products.indexWhere((p) => p.id == line.productId);
          if (idx == -1) return line;
          final priced = pricing.priceFor(
            product: products[idx],
            customerId: _customerId,
            quantity: line.quantity,
          );
          return line.copyWith(unitPrice: priced.unitPrice);
        }(),
    ];
  }

  Future<void> _addLine() async {
    final products = context.read<ProductProvider>().analyticsProducts;
    final picked = await showProductPicker(
      context: context,
      products: products,
      title: 'Add a product to quote',
    );
    if (picked == null || !mounted) return;
    if (_lines.any((l) => l.productId == picked.id)) {
      showInfoSnackBar(context, '${picked.name} is already on this quote.');
      return;
    }
    final bs = context.read<BillingSettingsProvider>().settings;
    final priced = context.read<PriceListProvider>().priceFor(
      product: picked,
      customerId: _customerId,
      quantity: 1,
    );
    setState(() {
      _lines = [
        ..._lines,
        QuotationLine(
          productId: picked.id,
          productName: picked.name,
          unit: picked.baseUnit,
          quantity: 1,
          unitPrice: priced.unitPrice,
          taxRate: bs.enableTax ? bs.defaultTaxRate : 0,
        ),
      ];
    });
  }

  Future<void> _pickValidUntil() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _validUntil ?? now.add(const Duration(days: 14)),
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null && mounted) setState(() => _validUntil = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_customerId.isEmpty) {
      showErrorSnackBar(context, 'Choose the customer this quote is for.');
      return;
    }
    final lines = _lines.where((l) => l.quantity > 0).toList();
    if (lines.isEmpty) {
      showErrorSnackBar(context, 'Add at least one line to quote.');
      return;
    }

    final user = context.read<AuthProvider>().currentUser;
    final provider = context.read<QuotationProvider>();
    final now = DateTime.now();
    final existing = widget.quotation;

    final quotation = QuotationModel(
      id: existing?.id ?? '',
      quoteNumber: _quoteNumber.text.trim(),
      customerId: _customerId,
      customerName: _customerName,
      customerPhone: _customerPhone,
      status: existing?.status ?? QuotationStatus.draft,
      lines: lines,
      notes: _notes.text.trim(),
      termsText: _terms.text.trim(),
      validUntil: _validUntil,
      sentAt: existing?.sentAt,
      decidedAt: existing?.decidedAt,
      decisionNote: existing?.decisionNote ?? '',
      convertedSalesOrderId: existing?.convertedSalesOrderId ?? '',
      createdBy: existing?.createdBy ?? user?.uid ?? '',
      createdByName: existing?.createdByName ?? user?.name ?? '',
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    final ok = _isEditing
        ? await provider.updateQuotation(quotation)
        : (await provider.addQuotation(quotation)) != null;

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      showSuccessSnackBar(
        context,
        _isEditing ? 'Quotation updated.' : 'Quotation saved as a draft.',
      );
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Save failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.manageQuotations,
      featureName: 'Quotations',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final busy = context.watch<QuotationProvider>().isBusy;
    final symbol = Money.symbolOf(context);

    final subtotal = _lines.fold(0.0, (acc, l) => acc + l.gross);
    final discount = _lines.fold(0.0, (acc, l) => acc + l.discountAmount);
    final tax = _lines.fold(0.0, (acc, l) => acc + l.taxAmount);
    final total = _lines.fold(0.0, (acc, l) => acc + l.total);

    return AppScreenScaffold(
      icon: Icons.request_quote_rounded,
      title: _isEditing ? 'Edit Quotation' : 'New Quotation',
      iconColor: AppTheme.indigoColor,
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            FormSection(
              title: 'Who it is for',
              icon: Icons.person_rounded,
              index: 0,
              children: [
                EntityPickerField(
                  label: 'Customer',
                  icon: Icons.person_rounded,
                  value: _customerName.isEmpty ? null : _customerName,
                  detail: _customerPhone.isEmpty ? null : _customerPhone,
                  onTap: _pickCustomer,
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _quoteNumber,
                  label: 'Quote number (optional)',
                  hint: 'Your own reference',
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickValidUntil,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.event_available_rounded,
                          size: 18,
                          color: AppTheme.textSec(context),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _validUntil == null
                                ? 'Valid until (optional)'
                                : 'Valid until '
                                      '${_validUntil!.day}/${_validUntil!.month}/${_validUntil!.year}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        if (_validUntil != null)
                          IconButton(
                            onPressed: () =>
                                setState(() => _validUntil = null),
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FormSection(
              title: 'What is being offered',
              icon: Icons.inventory_2_rounded,
              index: 1,
              trailing: TextButton.icon(
                onPressed: _addLine,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add'),
              ),
              children: [
                if (_lines.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Nothing quoted yet.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                  )
                else
                  for (var i = 0; i < _lines.length; i++)
                    _QuotationLineEditor(
                      key: ValueKey(_lines[i].productId),
                      line: _lines[i],
                      symbol: symbol,
                      onChanged: (line) => setState(() {
                        final next = [..._lines];
                        next[i] = line;
                        _lines = next;
                      }),
                      onRemove: () => setState(() {
                        final next = [..._lines]..removeAt(i);
                        _lines = next;
                      }),
                    ),
              ],
            ),
            const SizedBox(height: 12),
            GlassPanel(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  _TotalRow(
                    label: 'Subtotal',
                    value: Money.withSymbol(symbol, subtotal),
                  ),
                  if (discount > 0)
                    _TotalRow(
                      label: 'Discount',
                      value: '-${Money.withSymbol(symbol, discount)}',
                    ),
                  if (tax > 0)
                    _TotalRow(
                      label: 'Tax',
                      value: Money.withSymbol(symbol, tax),
                    ),
                  const Divider(height: 18),
                  _TotalRow(
                    label: 'Total',
                    value: Money.withSymbol(symbol, total),
                    emphasise: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FormSection(
              title: 'Notes & terms',
              icon: Icons.notes_rounded,
              index: 2,
              children: [
                CustomTextField(
                  controller: _notes,
                  label: 'Notes',
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _terms,
                  label: 'Terms shown on the quote',
                  maxLines: 3,
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : _save,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(_isEditing ? 'Save changes' : 'Save draft'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Saving reserves nothing and moves no stock. A quote only becomes '
              'an order when it is accepted and converted.',
              style: TextStyle(
                fontSize: 11.5,
                color: AppTheme.textSec(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  final String label;
  final String value;
  final bool emphasise;

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
              fontSize: emphasise ? 14 : 13,
              fontWeight: emphasise ? FontWeight.w700 : FontWeight.w500,
              color: emphasise ? null : AppTheme.textSec(context),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: emphasise ? 16 : 13,
              fontWeight: emphasise ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuotationLineEditor extends StatefulWidget {
  const _QuotationLineEditor({
    super.key,
    required this.line,
    required this.symbol,
    required this.onChanged,
    required this.onRemove,
  });

  final QuotationLine line;
  final String symbol;
  final ValueChanged<QuotationLine> onChanged;
  final VoidCallback onRemove;

  @override
  State<_QuotationLineEditor> createState() => _QuotationLineEditorState();
}

class _QuotationLineEditorState extends State<_QuotationLineEditor> {
  late final TextEditingController _quantity = TextEditingController(
    text: '${widget.line.quantity}',
  );
  late final TextEditingController _price = TextEditingController(
    text: widget.line.unitPrice == 0
        ? ''
        : widget.line.unitPrice.toStringAsFixed(2),
  );
  late final TextEditingController _discount = TextEditingController(
    text: widget.line.discountPercent == 0
        ? ''
        : widget.line.discountPercent.toString(),
  );

  @override
  void didUpdateWidget(_QuotationLineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A reprice from choosing the customer has to reach the field, but typing
    // must not fight the controller, so only an actual change is written back.
    if (widget.line.unitPrice != oldWidget.line.unitPrice) {
      final text = widget.line.unitPrice.toStringAsFixed(2);
      if (_price.text != text) _price.text = text;
    }
  }

  @override
  void dispose() {
    _quantity.dispose();
    _price.dispose();
    _discount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.line.productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  Money.withSymbol(widget.symbol, widget.line.total),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Remove',
                ),
              ],
            ),
            Row(
              children: [
                SizedBox(
                  width: 74,
                  child: TextField(
                    controller: _quantity,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      labelText: 'Qty',
                      isDense: true,
                    ),
                    onChanged: (value) => widget.onChanged(
                      widget.line.copyWith(quantity: int.tryParse(value) ?? 0),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Unit price',
                      isDense: true,
                      prefixText: widget.symbol,
                    ),
                    onChanged: (value) => widget.onChanged(
                      widget.line.copyWith(
                        unitPrice: double.tryParse(value) ?? 0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 84,
                  child: TextField(
                    controller: _discount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      labelText: 'Disc %',
                      isDense: true,
                    ),
                    onChanged: (value) => widget.onChanged(
                      widget.line.copyWith(
                        discountPercent: double.tryParse(value) ?? 0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
