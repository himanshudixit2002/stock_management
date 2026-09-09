import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../models/landed_cost_model.dart';
import '../../models/purchase_order_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/landed_cost_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/purchase_order_provider.dart';
import '../../services/landed_cost_allocator.dart';
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

/// Builds a landed cost sheet and applies it to product cost prices.
class LandedCostEditorScreen extends StatefulWidget {
  const LandedCostEditorScreen({super.key, this.sheet});

  final LandedCostModel? sheet;

  @override
  State<LandedCostEditorScreen> createState() => _LandedCostEditorScreenState();
}

class _LandedCostEditorScreenState extends State<LandedCostEditorScreen> {
  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy');

  final _formKey = GlobalKey<FormState>();
  final _reference = TextEditingController();
  final _notes = TextEditingController();

  String _purchaseOrderId = '';
  String _purchaseOrderNumber = '';
  String _vendorId = '';
  String _vendorName = '';
  DateTime _shipmentDate = DateTime.now();
  List<LandedCostCharge> _charges = [];
  List<LandedCostLine> _lines = [];
  LandedCostStatus _status = LandedCostStatus.draft;

  bool get _isEditing => widget.sheet != null;
  bool get _isLocked => _status != LandedCostStatus.draft;

  @override
  void initState() {
    super.initState();
    final sheet = widget.sheet;
    if (sheet != null) {
      _reference.text = sheet.referenceNumber;
      _notes.text = sheet.notes;
      _purchaseOrderId = sheet.purchaseOrderId;
      _purchaseOrderNumber = sheet.purchaseOrderNumber;
      _vendorId = sheet.vendorId;
      _vendorName = sheet.vendorName;
      _shipmentDate = sheet.shipmentDate;
      _charges = [...sheet.charges];
      _lines = [...sheet.lines];
      _status = sheet.status;
    }
  }

  @override
  void dispose() {
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// The sheet as currently edited, with charges allocated across the lines.
  LandedCostModel get _preview {
    final user = context.read<AuthProvider>().currentUser;
    final existing = widget.sheet;
    final now = DateTime.now();
    return LandedCostModel(
      id: existing?.id ?? '',
      referenceNumber: _reference.text.trim(),
      purchaseOrderId: _purchaseOrderId,
      purchaseOrderNumber: _purchaseOrderNumber,
      vendorId: _vendorId,
      vendorName: _vendorName,
      status: _status,
      charges: _charges,
      lines: LandedCostAllocator.allocate(lines: _lines, charges: _charges),
      notes: _notes.text.trim(),
      shipmentDate: _shipmentDate,
      appliedBy: existing?.appliedBy ?? '',
      appliedByName: existing?.appliedByName ?? '',
      appliedAt: existing?.appliedAt,
      createdBy: existing?.createdBy ?? user?.uid ?? '',
      createdByName: existing?.createdByName ?? user?.name ?? '',
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
  }

  /// Pulls the received lines off a purchase order, so a sheet does not have to
  /// be keyed in twice.
  Future<void> _pickPurchaseOrder() async {
    final orders = context.read<PurchaseOrderProvider>().orders;
    final selected = await showSearchablePicker(
      context: context,
      title: 'Which shipment?',
      selectedValue: _purchaseOrderId.isEmpty ? null : _purchaseOrderId,
      items: [
        for (final PurchaseOrderModel order in orders)
          PickerItem(
            value: order.id,
            label: order.vendorName.isEmpty
                ? 'Order ${order.id.substring(0, 6)}'
                : order.vendorName,
            subtitle:
                '${order.items.length} lines · ${_dateFormat.format(order.createdAt)}',
            icon: Icons.receipt_long_rounded,
          ),
      ],
    );
    if (selected == null || !mounted) return;
    final order = orders.where((o) => o.id == selected).firstOrNull;
    if (order == null) return;

    setState(() {
      _purchaseOrderId = order.id;
      _purchaseOrderNumber = order.id.substring(
        0,
        order.id.length < 8 ? order.id.length : 8,
      );
      _vendorId = order.vendorId;
      _vendorName = order.vendorName;
      _lines = [
        for (final item in order.items)
          LandedCostLine(
            productId: item.productId,
            productName: item.productName,
            // What was actually received where it differs from what was
            // ordered: charges attach to goods that arrived, not to goods that
            // were promised.
            quantity: item.receivedQuantity > 0
                ? item.receivedQuantity
                : item.quantity,
            baseUnitCost: item.unitPrice,
          ),
      ];
    });
  }

  Future<void> _addLine() async {
    final products = context.read<ProductProvider>().analyticsProducts;
    final picked = await showProductPicker(
      context: context,
      products: products,
      title: 'Add a received line',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _lines = [
        ..._lines,
        LandedCostLine(
          productId: picked.id,
          productName: picked.name,
          quantity: 1,
          baseUnitCost: picked.costPrice,
        ),
      ];
    });
  }

  void _addCharge() {
    setState(() {
      _charges = [
        ..._charges,
        const LandedCostCharge(label: 'Freight', amount: 0),
      ];
    });
  }

  Future<void> _pickShipmentDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _shipmentDate,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      helpText: 'Shipment date',
    );
    if (picked != null && mounted) setState(() => _shipmentDate = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_lines.isEmpty) {
      showErrorSnackBar(context, 'Add at least one received line.');
      return;
    }
    final provider = context.read<LandedCostProvider>();
    final sheet = _preview;
    final ok = _isEditing
        ? await provider.update(sheet)
        : (await provider.add(sheet)) != null;

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      showSuccessSnackBar(
        context,
        _isEditing ? 'Sheet saved.' : 'Sheet created.',
      );
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Save failed.');
    }
  }

  Future<void> _apply({required bool reverse}) async {
    final sheet = widget.sheet;
    final user = context.read<AuthProvider>().currentUser;
    if (sheet == null || user == null) return;

    final symbol = Money.symbolOf(context);
    final confirmed = await showConfirmDialog(
      context,
      title: reverse ? 'Reverse this sheet?' : 'Apply to cost prices?',
      message: reverse
          ? 'Each product goes back to the cost price it had before this sheet '
                'was applied.'
          : '${Money.withSymbol(symbol, sheet.totalCharges)} is spread across '
                '${sheet.lines.length} products, raising their cost price by '
                '${sheet.upliftPercent.toStringAsFixed(1)}% on average. Every '
                'change is written to Price History.',
      confirmLabel: reverse ? 'Reverse' : 'Apply',
      icon: reverse ? Icons.undo_rounded : Icons.calculate_rounded,
      iconColor: reverse ? AppTheme.warningColor : AppTheme.successColor,
      confirmColor: reverse ? AppTheme.warningColor : AppTheme.successColor,
    );
    if (!confirmed || !mounted) return;

    final provider = context.read<LandedCostProvider>();
    final ok = reverse
        ? await provider.reverse(
            sheet: sheet,
            userId: user.uid,
            userName: user.name,
          )
        : await provider.apply(
            sheet: sheet,
            userId: user.uid,
            userName: user.name,
          );

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      showSuccessSnackBar(
        context,
        reverse ? 'Costs restored.' : 'Cost prices updated.',
      );
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'That failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.manageLandedCosts,
      featureName: 'Landed Costs',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final busy = context.watch<LandedCostProvider>().isBusy;
    final symbol = Money.symbolOf(context);
    final preview = _preview;

    return AppScreenScaffold(
      icon: Icons.local_shipping_outlined,
      title: _isEditing ? 'Landed Cost Sheet' : 'New Landed Cost',
      subtitle: _isLocked ? preview.statusLabel : null,
      iconColor: AppTheme.warningColor,
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            FormSection(
              title: 'Shipment',
              icon: Icons.inventory_rounded,
              index: 0,
              children: [
                CustomTextField(
                  controller: _reference,
                  label: 'Reference',
                  hint: 'Bill of entry, AWB, invoice number',
                  enabled: !_isLocked,
                ),
                const SizedBox(height: 12),
                EntityPickerField(
                  label: 'From purchase order',
                  icon: Icons.receipt_long_rounded,
                  value: _vendorName.isEmpty ? null : _vendorName,
                  placeholder: 'Optional — pulls the received lines in',
                  detail: _purchaseOrderNumber.isEmpty
                      ? null
                      : 'PO $_purchaseOrderNumber',
                  onTap: _isLocked ? () {} : _pickPurchaseOrder,
                  enabled: !_isLocked,
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _isLocked ? null : _pickShipmentDate,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.event_rounded,
                          size: 18,
                          color: AppTheme.textSec(context),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Shipment ${_dateFormat.format(_shipmentDate)}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FormSection(
              title: 'Charges',
              subtitle: 'Each spreads on its own basis',
              icon: Icons.receipt_rounded,
              index: 1,
              trailing: _isLocked
                  ? null
                  : TextButton.icon(
                      onPressed: _addCharge,
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Add'),
                    ),
              children: [
                if (_charges.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No charges yet. Without one there is nothing to allocate.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                  )
                else
                  for (var i = 0; i < _charges.length; i++)
                    _ChargeEditor(
                      charge: _charges[i],
                      symbol: symbol,
                      enabled: !_isLocked,
                      onChanged: (charge) => setState(() {
                        final next = [..._charges];
                        next[i] = charge;
                        _charges = next;
                      }),
                      onRemove: () => setState(() {
                        final next = [..._charges]..removeAt(i);
                        _charges = next;
                      }),
                    ),
              ],
            ),
            const SizedBox(height: 12),
            FormSection(
              title: 'Received lines',
              subtitle: 'Allocation updates as you type',
              icon: Icons.inventory_2_rounded,
              index: 2,
              trailing: _isLocked
                  ? null
                  : TextButton.icon(
                      onPressed: _addLine,
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Add'),
                    ),
              children: [
                if (preview.lines.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Nothing received yet.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                  )
                else
                  for (var i = 0; i < preview.lines.length; i++)
                    _LineEditor(
                      line: preview.lines[i],
                      symbol: symbol,
                      enabled: !_isLocked,
                      onChanged: (line) => setState(() {
                        final next = [..._lines];
                        next[i] = next[i].copyWith(
                          quantity: line.quantity,
                          baseUnitCost: line.baseUnitCost,
                        );
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
            _Totals(sheet: preview, symbol: symbol),
            const SizedBox(height: 12),
            FormSection(
              title: 'Notes',
              icon: Icons.sticky_note_2_rounded,
              index: 3,
              children: [
                CustomTextField(
                  controller: _notes,
                  label: 'Notes',
                  maxLines: 2,
                  enabled: !_isLocked,
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (!_isLocked)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : _save,
                  icon: const Icon(Icons.save_rounded),
                  label: Text(_isEditing ? 'Save draft' : 'Create sheet'),
                ),
              ),
            if (_isEditing) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy || (!preview.canApply && !preview.canReverse)
                      ? null
                      : () => _apply(reverse: preview.canReverse),
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          preview.canReverse
                              ? Icons.undo_rounded
                              : Icons.calculate_rounded,
                        ),
                  label: Text(
                    preview.canReverse
                        ? 'Reverse cost changes'
                        : 'Apply to cost prices',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Applying writes each line\'s landed unit cost onto its '
              'product\'s cost price, and records the change in Price History. '
              'Selling prices are untouched.',
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

class _Totals extends StatelessWidget {
  const _Totals({required this.sheet, required this.symbol});

  final LandedCostModel sheet;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _Row(
            label: 'Goods value',
            value: Money.withSymbol(symbol, sheet.baseValue),
          ),
          _Row(
            label: 'Charges',
            value: Money.withSymbol(symbol, sheet.totalCharges),
          ),
          const Divider(height: 20),
          _Row(
            label: 'Landed value',
            value: Money.withSymbol(symbol, sheet.landedValue),
            bold: true,
          ),
          _Row(
            label: 'Average uplift',
            value: '${sheet.upliftPercent.toStringAsFixed(2)}%',
            accent: sheet.upliftPercent > 15 ? AppTheme.dangerColor : null,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.bold = false,
    this.accent,
  });

  final String label;
  final String value;
  final bool bold;
  final Color? accent;

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
              fontSize: 13,
              color: AppTheme.textSec(context),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 15 : 13.5,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChargeEditor extends StatefulWidget {
  const _ChargeEditor({
    required this.charge,
    required this.symbol,
    required this.enabled,
    required this.onChanged,
    required this.onRemove,
  });

  final LandedCostCharge charge;
  final String symbol;
  final bool enabled;
  final ValueChanged<LandedCostCharge> onChanged;
  final VoidCallback onRemove;

  @override
  State<_ChargeEditor> createState() => _ChargeEditorState();
}

class _ChargeEditorState extends State<_ChargeEditor> {
  late final TextEditingController _label = TextEditingController(
    text: widget.charge.label,
  );
  late final TextEditingController _amount = TextEditingController(
    text: widget.charge.amount == 0 ? '' : '${widget.charge.amount}',
  );

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _label,
                    enabled: widget.enabled,
                    decoration: const InputDecoration(
                      labelText: 'Charge',
                      isDense: true,
                    ),
                    onChanged: (value) =>
                        widget.onChanged(widget.charge.copyWith(label: value)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _amount,
                    enabled: widget.enabled,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    decoration: InputDecoration(
                      labelText: widget.symbol,
                      isDense: true,
                    ),
                    onChanged: (value) => widget.onChanged(
                      widget.charge.copyWith(
                        amount: double.tryParse(value) ?? 0,
                      ),
                    ),
                  ),
                ),
                if (widget.enabled)
                  IconButton(
                    onPressed: widget.onRemove,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: 'Remove',
                  )
                else
                  const SizedBox(width: 6),
              ],
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<AllocationBasis>(
              initialValue: widget.charge.basis,
              decoration: const InputDecoration(
                labelText: 'Spread',
                isDense: true,
              ),
              items: [
                for (final basis in AllocationBasis.values)
                  DropdownMenuItem(
                    value: basis,
                    child: Text(LandedCostCharge.basisLabelOf(basis)),
                  ),
              ],
              onChanged: widget.enabled
                  ? (basis) {
                      if (basis != null) {
                        widget.onChanged(widget.charge.copyWith(basis: basis));
                      }
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _LineEditor extends StatefulWidget {
  const _LineEditor({
    required this.line,
    required this.symbol,
    required this.enabled,
    required this.onChanged,
    required this.onRemove,
  });

  final LandedCostLine line;
  final String symbol;
  final bool enabled;
  final ValueChanged<LandedCostLine> onChanged;
  final VoidCallback onRemove;

  @override
  State<_LineEditor> createState() => _LineEditorState();
}

class _LineEditorState extends State<_LineEditor> {
  late final TextEditingController _quantity = TextEditingController(
    text: '${widget.line.quantity}',
  );
  late final TextEditingController _cost = TextEditingController(
    text: widget.line.baseUnitCost.toStringAsFixed(2),
  );

  @override
  void dispose() {
    _quantity.dispose();
    _cost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                    widget.line.productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.enabled)
                  IconButton(
                    onPressed: widget.onRemove,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: 'Remove',
                  ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantity,
                    enabled: widget.enabled,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
                    controller: _cost,
                    enabled: widget.enabled,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Supplier ${widget.symbol}/unit',
                      isDense: true,
                    ),
                    onChanged: (value) => widget.onChanged(
                      widget.line.copyWith(
                        baseUnitCost: double.tryParse(value) ?? 0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ),
            if (widget.line.allocatedAmount != 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '+${Money.withSymbol(widget.symbol, widget.line.allocatedAmount)} '
                  'allocated → landed '
                  '${Money.withSymbol(widget.symbol, widget.line.landedUnitCost)}/unit '
                  '(+${widget.line.upliftPercent.toStringAsFixed(1)}%)',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textSec(context),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
