import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../models/price_list_model.dart';
import '../../models/product_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/price_list_provider.dart';
import '../../providers/product_provider.dart';
import '../../utils/currency.dart';
import '../../utils/dialogs.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/form_section.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/product_picker.dart';

/// Creates or edits a price list, including who is on it.
class PriceListEditorScreen extends StatefulWidget {
  const PriceListEditorScreen({super.key, this.list});

  final PriceListModel? list;

  @override
  State<PriceListEditorScreen> createState() => _PriceListEditorScreenState();
}

class _PriceListEditorScreenState extends State<PriceListEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _defaultDiscount = TextEditingController();

  bool _isActive = true;
  DateTime? _validUntil;
  List<PriceListEntry> _entries = [];
  Set<String> _customerIds = {};

  bool get _isEditing => widget.list != null;

  @override
  void initState() {
    super.initState();
    final list = widget.list;
    if (list != null) {
      _name.text = list.name;
      _description.text = list.description;
      _defaultDiscount.text = list.defaultDiscountPercent == 0
          ? ''
          : '${list.defaultDiscountPercent}';
      _isActive = list.isActive;
      _validUntil = list.validUntil;
      _entries = [...list.entries];
      _customerIds = {...list.customerIds};
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _defaultDiscount.dispose();
    super.dispose();
  }

  Future<void> _addEntry() async {
    final products = context.read<ProductProvider>().analyticsProducts;
    final picked = await showProductPicker(
      context: context,
      products: products,
      title: 'Price a product',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _entries = [
        ..._entries,
        PriceListEntry(
          productId: picked.id,
          productName: picked.name,
          mode: PriceListMode.discountPercent,
          value: 0,
        ),
      ];
    });
  }

  Future<void> _pickValidUntil() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _validUntil ?? now.add(const Duration(days: 90)),
      firstDate: now,
      lastDate: DateTime(now.year + 10),
      helpText: 'Price list valid until',
    );
    if (picked != null && mounted) setState(() => _validUntil = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final user = context.read<AuthProvider>().currentUser;
    final provider = context.read<PriceListProvider>();
    final now = DateTime.now();
    final existing = widget.list;

    final list = PriceListModel(
      id: existing?.id ?? '',
      name: _name.text.trim(),
      description: _description.text.trim(),
      defaultDiscountPercent:
          double.tryParse(_defaultDiscount.text.trim()) ?? 0,
      entries: _entries.where((e) => e.productId.isNotEmpty).toList(),
      customerIds: _customerIds.toList(),
      isActive: _isActive,
      validUntil: _validUntil,
      createdBy: existing?.createdBy ?? user?.uid ?? '',
      createdByName: existing?.createdByName ?? user?.name ?? '',
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    final ok = _isEditing
        ? await provider.update(list)
        : (await provider.add(list)) != null;

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      showSuccessSnackBar(
        context,
        _isEditing ? 'Price list updated.' : 'Price list created.',
      );
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Save failed.');
    }
  }

  Future<void> _delete() async {
    final list = widget.list;
    if (list == null) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete "${list.name}"?',
      message:
          'Customers on it go back to catalog prices. Invoices already raised '
          'keep the prices they were raised at.',
    );
    if (!confirmed || !mounted) return;
    final provider = context.read<PriceListProvider>();
    final ok = await provider.remove(list.id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      showSuccessSnackBar(context, 'Price list deleted.');
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Delete failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.managePriceLists,
      featureName: 'Price Lists',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final busy = context.watch<PriceListProvider>().isBusy;
    final customers = context.watch<CustomerProvider>().customers;
    final products = context.watch<ProductProvider>().analyticsProducts;
    final symbol = Money.symbolOf(context);

    return AppScreenScaffold(
      icon: Icons.sell_rounded,
      title: _isEditing ? 'Edit Price List' : 'New Price List',
      iconColor: AppTheme.successColor,
      actions: [
        if (_isEditing)
          IconButton(
            onPressed: busy ? null : _delete,
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Delete',
          ),
      ],
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            FormSection(
              title: 'The list',
              icon: Icons.label_rounded,
              index: 0,
              children: [
                CustomTextField(
                  controller: _name,
                  label: 'Name',
                  hint: 'e.g. Wholesale — tier 1',
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? 'Name the list' : null,
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _description,
                  label: 'Description (optional)',
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _defaultDiscount,
                  label: 'Blanket discount %',
                  helperText:
                      'Applied to anything with no price of its own below',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                  ],
                ),
                const SizedBox(height: 4),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active', style: TextStyle(fontSize: 14)),
                  subtitle: Text(
                    'An inactive list prices nothing',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSec(context),
                    ),
                  ),
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                ),
                InkWell(
                  onTap: _pickValidUntil,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.event_busy_rounded,
                          size: 18,
                          color: AppTheme.textSec(context),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _validUntil == null
                                ? 'No expiry'
                                : 'Expires '
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
              title: 'Product prices',
              subtitle: 'Overrides the blanket discount for these products',
              icon: Icons.inventory_2_rounded,
              index: 1,
              trailing: TextButton.icon(
                onPressed: _addEntry,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add'),
              ),
              children: [
                if (_entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'None yet — the blanket discount applies to everything.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                  )
                else
                  for (var i = 0; i < _entries.length; i++)
                    _EntryEditor(
                      entry: _entries[i],
                      symbol: symbol,
                      product: products
                          .where((p) => p.id == _entries[i].productId)
                          .firstOrNull,
                      onChanged: (entry) => setState(() {
                        final next = [..._entries];
                        next[i] = entry;
                        _entries = next;
                      }),
                      onRemove: () => setState(() {
                        final next = [..._entries]..removeAt(i);
                        _entries = next;
                      }),
                    ),
              ],
            ),
            const SizedBox(height: 12),
            FormSection(
              title: 'Customers',
              subtitle: '${_customerIds.length} on this list',
              icon: Icons.people_rounded,
              index: 2,
              children: [
                if (customers.isEmpty)
                  Text(
                    'No customers to assign yet.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSec(context),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: customers.length,
                      itemBuilder: (context, i) {
                        final customer = customers[i];
                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: _customerIds.contains(customer.id),
                          title: Text(
                            customer.name,
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: customer.phone.isEmpty
                              ? null
                              : Text(
                                  customer.phone,
                                  style: const TextStyle(fontSize: 12),
                                ),
                          onChanged: (checked) => setState(() {
                            if (checked ?? false) {
                              _customerIds.add(customer.id);
                            } else {
                              _customerIds.remove(customer.id);
                            }
                          }),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'A customer should sit on one list only. If they are on '
                  'another, the list giving the bigger blanket discount wins.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textSec(context),
                  ),
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
                label: Text(_isEditing ? 'Save changes' : 'Create price list'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryEditor extends StatefulWidget {
  const _EntryEditor({
    required this.entry,
    required this.symbol,
    required this.product,
    required this.onChanged,
    required this.onRemove,
  });

  final PriceListEntry entry;
  final String symbol;
  final ProductModel? product;
  final ValueChanged<PriceListEntry> onChanged;
  final VoidCallback onRemove;

  @override
  State<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<_EntryEditor> {
  late final TextEditingController _value = TextEditingController(
    text: widget.entry.value == 0 ? '' : '${widget.entry.value}',
  );
  late final TextEditingController _minQuantity = TextEditingController(
    text: widget.entry.minQuantity == 0 ? '' : '${widget.entry.minQuantity}',
  );

  @override
  void dispose() {
    _value.dispose();
    _minQuantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    // Live preview against the real catalog numbers, so a 30% margin over cost
    // is shown as the price it actually produces.
    final resolved = product == null
        ? null
        : widget.entry.priceFor(
            sellingPrice: product.sellingPrice,
            costPrice: product.costPrice,
            quantity: widget.entry.minQuantity > 0
                ? widget.entry.minQuantity
                : 1,
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.entry.productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Remove',
                ),
              ],
            ),
            DropdownButtonFormField<PriceListMode>(
              initialValue: widget.entry.mode,
              decoration: const InputDecoration(labelText: 'How', isDense: true),
              items: [
                for (final mode in PriceListMode.values)
                  DropdownMenuItem(
                    value: mode,
                    child: Text(PriceListEntry.modeLabelOf(mode)),
                  ),
              ],
              onChanged: (mode) {
                if (mode != null) {
                  widget.onChanged(widget.entry.copyWith(mode: mode));
                }
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _value,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    decoration: InputDecoration(
                      labelText: switch (widget.entry.mode) {
                        PriceListMode.fixedPrice => 'Price (${widget.symbol})',
                        PriceListMode.discountPercent => 'Discount %',
                        PriceListMode.marginOverCost => 'Margin %',
                      },
                      isDense: true,
                    ),
                    onChanged: (value) => widget.onChanged(
                      widget.entry.copyWith(
                        value: double.tryParse(value) ?? 0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _minQuantity,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'From qty',
                      isDense: true,
                    ),
                    onChanged: (value) => widget.onChanged(
                      widget.entry.copyWith(
                        minQuantity: int.tryParse(value) ?? 0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ),
            if (resolved != null && product != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${Money.withSymbol(widget.symbol, resolved)} per unit '
                  '(catalog ${Money.withSymbol(widget.symbol, product.sellingPrice)})',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: resolved > product.sellingPrice
                        ? AppTheme.warningColor
                        : AppTheme.textSec(context),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
