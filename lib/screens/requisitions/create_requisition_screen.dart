import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../models/requisition_model.dart';
import '../../models/vendor_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/requisition_provider.dart';
import '../../providers/vendor_provider.dart';
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

/// Raises or edits a request to buy.
class CreateRequisitionScreen extends StatefulWidget {
  const CreateRequisitionScreen({super.key, this.requisition});

  final RequisitionModel? requisition;

  @override
  State<CreateRequisitionScreen> createState() =>
      _CreateRequisitionScreenState();
}

class _CreateRequisitionScreenState extends State<CreateRequisitionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _reference = TextEditingController();
  final _department = TextEditingController();
  final _justification = TextEditingController();

  RequisitionUrgency _urgency = RequisitionUrgency.normal;
  String _vendorId = '';
  String _vendorName = '';
  DateTime? _neededBy;
  List<RequisitionLine> _lines = [];

  bool get _isEditing => widget.requisition != null;

  @override
  void initState() {
    super.initState();
    final requisition = widget.requisition;
    if (requisition != null) {
      _title.text = requisition.title;
      _reference.text = requisition.referenceNumber;
      _department.text = requisition.department;
      _justification.text = requisition.justification;
      _urgency = requisition.urgency;
      _vendorId = requisition.vendorId;
      _vendorName = requisition.vendorName;
      _neededBy = requisition.neededBy;
      _lines = [...requisition.lines];
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _reference.dispose();
    _department.dispose();
    _justification.dispose();
    super.dispose();
  }

  Future<void> _pickVendor() async {
    final vendors = context.read<VendorProvider>().vendors;
    final selected = await showSearchablePicker(
      context: context,
      title: 'Suggested supplier',
      selectedValue: _vendorId.isEmpty ? null : _vendorId,
      items: [
        for (final VendorModel vendor in vendors)
          PickerItem(
            value: vendor.id,
            label: vendor.name,
            subtitle: vendor.phone,
            icon: Icons.store_rounded,
          ),
      ],
    );
    if (selected == null || !mounted) return;
    final vendor = vendors.where((v) => v.id == selected).firstOrNull;
    setState(() {
      _vendorId = vendor?.id ?? '';
      _vendorName = vendor?.name ?? '';
    });
  }

  Future<void> _addLine() async {
    final products = context.read<ProductProvider>().analyticsProducts;
    final picked = await showProductPicker(
      context: context,
      products: products,
      title: 'What do you need?',
    );
    if (picked == null || !mounted) return;
    if (_lines.any((l) => l.productId == picked.id)) {
      showInfoSnackBar(context, '${picked.name} is already on this request.');
      return;
    }
    setState(() {
      _lines = [
        ..._lines,
        RequisitionLine(
          productId: picked.id,
          productName: picked.name,
          unit: picked.unit,
          quantity: 1,
          // Seeded from the product's cost so the approver sees a number
          // without the requester having to look one up.
          estimatedUnitCost: picked.costPrice,
        ),
      ];
    });
  }

  Future<void> _pickNeededBy() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _neededBy ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null && mounted) setState(() => _neededBy = picked);
  }

  RequisitionModel _compose() {
    final user = context.read<AuthProvider>().currentUser;
    final now = DateTime.now();
    final existing = widget.requisition;
    return RequisitionModel(
      id: existing?.id ?? '',
      referenceNumber: _reference.text.trim(),
      title: _title.text.trim(),
      status: existing?.status ?? RequisitionStatus.draft,
      urgency: _urgency,
      lines: _lines.where((l) => l.quantity > 0).toList(),
      vendorId: _vendorId,
      vendorName: _vendorName,
      department: _department.text.trim(),
      justification: _justification.text.trim(),
      neededBy: _neededBy,
      requestedBy: existing?.requestedBy ?? user?.uid ?? '',
      requestedByName: existing?.requestedByName ?? user?.name ?? '',
      submittedAt: existing?.submittedAt,
      decidedBy: existing?.decidedBy ?? '',
      decidedByName: existing?.decidedByName ?? '',
      decidedAt: existing?.decidedAt,
      decisionNote: existing?.decisionNote ?? '',
      purchaseOrderId: existing?.purchaseOrderId ?? '',
      purchaseOrderNumber: existing?.purchaseOrderNumber ?? '',
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
  }

  Future<void> _save({required bool submit}) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final requisition = _compose();
    if (requisition.lines.isEmpty) {
      showErrorSnackBar(context, 'Add at least one line.');
      return;
    }

    final provider = context.read<RequisitionProvider>();
    final toSave = submit
        ? requisition.copyWith(
            status: RequisitionStatus.submitted,
            submittedAt: DateTime.now(),
            decisionNote: '',
          )
        : requisition;

    final ok = _isEditing
        ? await provider.update(toSave)
        : (await provider.add(toSave)) != null;

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      showSuccessSnackBar(
        context,
        submit ? 'Sent for approval.' : 'Saved as a draft.',
      );
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Save failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.createRequisitions,
      featureName: 'Requisitions',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final busy = context.watch<RequisitionProvider>().isBusy;
    final symbol = Money.symbolOf(context);
    final estimate = _lines.fold(0.0, (acc, l) => acc + l.estimatedTotal);

    return AppScreenScaffold(
      icon: Icons.assignment_rounded,
      title: _isEditing ? 'Edit Request' : 'New Request',
      subtitle: estimate > 0
          ? 'Estimated ${Money.withSymbol(symbol, estimate)}'
          : null,
      iconColor: AppTheme.indigoColor,
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            FormSection(
              title: 'Request',
              icon: Icons.description_rounded,
              index: 0,
              children: [
                CustomTextField(
                  controller: _title,
                  label: 'Title',
                  hint: 'e.g. Packaging for the festive run',
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Give the request a title'
                      : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: CustomTextField(
                        controller: _reference,
                        label: 'Reference (optional)',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CustomTextField(
                        controller: _department,
                        label: 'Department (optional)',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<RequisitionUrgency>(
                  initialValue: _urgency,
                  decoration: const InputDecoration(labelText: 'Urgency'),
                  items: [
                    for (final urgency in RequisitionUrgency.values)
                      DropdownMenuItem(
                        value: urgency,
                        child: Text(RequisitionModel.urgencyLabelOf(urgency)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _urgency = value);
                  },
                ),
                const SizedBox(height: 12),
                EntityPickerField(
                  label: 'Suggested supplier',
                  icon: Icons.store_rounded,
                  value: _vendorName.isEmpty ? null : _vendorName,
                  placeholder: 'Optional — carried to the purchase order',
                  onTap: _pickVendor,
                  onClear: _vendorId.isEmpty
                      ? null
                      : () => setState(() {
                          _vendorId = '';
                          _vendorName = '';
                        }),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickNeededBy,
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
                            _neededBy == null
                                ? 'Needed by (optional)'
                                : 'Needed by '
                                      '${_neededBy!.day}/${_neededBy!.month}/${_neededBy!.year}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        if (_neededBy != null)
                          IconButton(
                            onPressed: () => setState(() => _neededBy = null),
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
              title: 'Lines',
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
                      'Nothing requested yet.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                  )
                else
                  for (var i = 0; i < _lines.length; i++)
                    _RequisitionLineEditor(
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
            FormSection(
              title: 'Justification',
              subtitle: 'What the approver needs to know',
              icon: Icons.help_outline_rounded,
              index: 2,
              children: [
                CustomTextField(
                  controller: _justification,
                  label: 'Why this is needed',
                  maxLines: 3,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : () => _save(submit: false),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save draft'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : () => _save(submit: true),
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                    label: const Text('Submit'),
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

class _RequisitionLineEditor extends StatefulWidget {
  const _RequisitionLineEditor({
    required this.line,
    required this.symbol,
    required this.onChanged,
    required this.onRemove,
  });

  final RequisitionLine line;
  final String symbol;
  final ValueChanged<RequisitionLine> onChanged;
  final VoidCallback onRemove;

  @override
  State<_RequisitionLineEditor> createState() => _RequisitionLineEditorState();
}

class _RequisitionLineEditorState extends State<_RequisitionLineEditor> {
  late final TextEditingController _quantity = TextEditingController(
    text: '${widget.line.quantity}',
  );
  late final TextEditingController _cost = TextEditingController(
    text: widget.line.estimatedUnitCost == 0
        ? ''
        : widget.line.estimatedUnitCost.toStringAsFixed(2),
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
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'Qty (${widget.line.unit})',
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
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Est. ${widget.symbol}/unit',
                      isDense: true,
                    ),
                    onChanged: (value) => widget.onChanged(
                      widget.line.copyWith(
                        estimatedUnitCost: double.tryParse(value) ?? 0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ),
            if (widget.line.estimatedTotal > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Line estimate '
                  '${Money.withSymbol(widget.symbol, widget.line.estimatedTotal)}',
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
