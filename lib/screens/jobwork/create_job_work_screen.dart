import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../models/job_work_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/bom_provider.dart';
import '../../providers/job_work_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/settings_provider.dart';
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

/// Raises a draft job work order.
class CreateJobWorkScreen extends StatefulWidget {
  const CreateJobWorkScreen({super.key, this.order});

  /// An existing draft being edited. Issued jobs are not editable.
  final JobWorkOrderModel? order;

  @override
  State<CreateJobWorkScreen> createState() => _CreateJobWorkScreenState();
}

class _CreateJobWorkScreenState extends State<CreateJobWorkScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reference = TextEditingController();
  final _outputQuantity = TextEditingController(text: '1');
  final _chargePerUnit = TextEditingController();
  final _additional = TextEditingController();
  final _notes = TextEditingController();

  String _vendorId = '';
  String _vendorName = '';
  String _bomId = '';
  String _outputProductId = '';
  String _outputProductName = '';
  String _outputUnit = '';
  String _issueLocation = '';
  String _receiveLocation = '';
  DateTime? _expectedAt;
  bool _updateOutputCost = true;
  List<JobWorkComponent> _components = [];

  bool get _isEditing => widget.order != null;

  @override
  void initState() {
    super.initState();
    final order = widget.order;
    final locations = context.read<SettingsProvider>().locations;
    if (order != null) {
      _reference.text = order.referenceNumber;
      _outputQuantity.text = '${order.outputQuantity}';
      _chargePerUnit.text = order.jobChargePerUnit == 0
          ? ''
          : order.jobChargePerUnit.toString();
      _additional.text = order.additionalCharges == 0
          ? ''
          : order.additionalCharges.toString();
      _notes.text = order.notes;
      _vendorId = order.vendorId;
      _vendorName = order.vendorName;
      _bomId = order.bomId;
      _outputProductId = order.outputProductId;
      _outputProductName = order.outputProductName;
      _outputUnit = order.outputUnit;
      _issueLocation = order.issueLocation;
      _receiveLocation = order.receiveLocation;
      _expectedAt = order.expectedAt;
      _updateOutputCost = order.updateOutputCost;
      _components = [...order.components];
    } else {
      _issueLocation = locations.isNotEmpty ? locations.first : 'Main';
      _receiveLocation = _issueLocation;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final companyId = context.read<SettingsProvider>().companyId;
      if (companyId.isEmpty) return;
      context.read<JobWorkProvider>().initialize(companyId: companyId);
      context.read<BomProvider>().initialize(companyId: companyId);
    });
  }

  @override
  void dispose() {
    _reference.dispose();
    _outputQuantity.dispose();
    _chargePerUnit.dispose();
    _additional.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickVendor() async {
    final vendors = context.read<VendorProvider>().vendors;
    final selected = await showSearchablePicker(
      context: context,
      title: 'Which subcontractor?',
      selectedValue: _vendorId.isEmpty ? null : _vendorId,
      items: [
        for (final v in vendors)
          PickerItem(
            value: v.id,
            label: v.name,
            subtitle: v.phone,
            icon: Icons.store_rounded,
          ),
      ],
    );
    if (selected == null || !mounted) return;
    final vendor = context.read<VendorProvider>().vendors.firstWhere(
      (v) => v.id == selected,
    );
    setState(() {
      _vendorId = vendor.id;
      _vendorName = vendor.name;
    });
  }

  /// Pre-fills the job from a bill of materials.
  ///
  /// The components are copied onto the order rather than referenced, so
  /// editing the recipe later cannot change what a vendor was already sent.
  Future<void> _pickBom() async {
    final boms = context.read<BomProvider>().boms;
    if (boms.isEmpty) {
      showInfoSnackBar(
        context,
        'No bills of materials yet. Add the components by hand instead.',
      );
      return;
    }
    final selected = await showSearchablePicker(
      context: context,
      title: 'Start from a recipe',
      selectedValue: _bomId.isEmpty ? null : _bomId,
      items: [
        for (final bom in boms)
          PickerItem(
            value: bom.id,
            label: bom.name,
            subtitle:
                '${bom.components.length} components → ${bom.outputProductName}',
            icon: Icons.account_tree_rounded,
          ),
      ],
    );
    if (selected == null || !mounted) return;
    final bom = boms.firstWhere((b) => b.id == selected);
    setState(() {
      _bomId = bom.id;
      _outputProductId = bom.outputProductId;
      _outputProductName = bom.outputProductName;
      _components = [
        for (final component in bom.components)
          JobWorkComponent(
            productId: component.productId,
            productName: component.productName,
            unit: component.unit,
            // A BOM states its components per run of outputQuantity units; a
            // job work order states them per finished unit, so the recipe is
            // divided down and rounded up. Rounding up rather than down keeps a
            // job from being issued short of what it physically needs.
            quantityPerOutput: bom.outputQuantity <= 1
                ? component.quantity
                : (component.quantity / bom.outputQuantity).ceil(),
          ),
      ];
    });
  }

  Future<void> _pickOutput() async {
    final products = context.read<ProductProvider>().analyticsProducts;
    final picked = await showProductPicker(
      context: context,
      products: products,
      title: 'What comes back?',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _outputProductId = picked.id;
      _outputProductName = picked.name;
      _outputUnit = picked.baseUnit;
    });
  }

  Future<void> _addComponent() async {
    final products = context.read<ProductProvider>().analyticsProducts;
    final picked = await showProductPicker(
      context: context,
      products: products,
      title: 'Which component goes out?',
    );
    if (picked == null || !mounted) return;
    if (_components.any((c) => c.productId == picked.id)) {
      showInfoSnackBar(context, '${picked.name} is already on this job.');
      return;
    }
    setState(() {
      _components = [
        ..._components,
        JobWorkComponent(
          productId: picked.id,
          productName: picked.name,
          unit: picked.baseUnit,
          quantityPerOutput: 1,
        ),
      ];
    });
  }

  Future<void> _pickExpected() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expectedAt ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null && mounted) setState(() => _expectedAt = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_vendorId.isEmpty) {
      showErrorSnackBar(context, 'Choose the subcontractor.');
      return;
    }
    if (_outputProductId.isEmpty) {
      showErrorSnackBar(context, 'Choose what comes back.');
      return;
    }
    final components = _components
        .where((c) => c.quantityPerOutput > 0)
        .toList();
    if (components.isEmpty) {
      showErrorSnackBar(context, 'Add at least one component to send out.');
      return;
    }
    final outputQuantity = int.tryParse(_outputQuantity.text.trim()) ?? 0;
    if (outputQuantity <= 0) {
      showErrorSnackBar(context, 'How many finished units are expected?');
      return;
    }

    final user = context.read<AuthProvider>().currentUser;
    final provider = context.read<JobWorkProvider>();
    final now = DateTime.now();
    final existing = widget.order;

    final order = JobWorkOrderModel(
      id: existing?.id ?? '',
      referenceNumber: _reference.text.trim(),
      vendorId: _vendorId,
      vendorName: _vendorName,
      bomId: _bomId,
      outputProductId: _outputProductId,
      outputProductName: _outputProductName,
      outputUnit: _outputUnit,
      outputQuantity: outputQuantity,
      receivedQuantity: existing?.receivedQuantity ?? 0,
      components: components,
      jobChargePerUnit: double.tryParse(_chargePerUnit.text.trim()) ?? 0,
      additionalCharges: double.tryParse(_additional.text.trim()) ?? 0,
      issueLocation: _issueLocation,
      receiveLocation: _receiveLocation,
      status: existing?.status ?? JobWorkStatus.draft,
      updateOutputCost: _updateOutputCost,
      expectedAt: _expectedAt,
      notes: _notes.text.trim(),
      createdBy: existing?.createdBy ?? user?.uid ?? '',
      createdByName: existing?.createdByName ?? user?.name ?? '',
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    final ok = _isEditing
        ? await provider.updateOrder(order)
        : (await provider.addOrder(order)) != null;

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      showSuccessSnackBar(
        context,
        _isEditing ? 'Job updated.' : 'Job drafted. Issue it to send the parts.',
      );
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Save failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.manageJobWork,
      featureName: 'Job Work',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final locations = context.watch<SettingsProvider>().locations;
    final busy = context.watch<JobWorkProvider>().isBusy;
    final products = context.watch<ProductProvider>().analyticsProducts;
    final symbol = Money.symbolOf(context);
    final outputQuantity = int.tryParse(_outputQuantity.text.trim()) ?? 0;

    // What the finished unit will cost: the components it consumes at today's
    // cost price, plus the conversion charge.
    var componentCost = 0.0;
    for (final component in _components) {
      final idx = products.indexWhere((p) => p.id == component.productId);
      if (idx == -1) continue;
      componentCost += products[idx].costPrice * component.quantityPerOutput;
    }
    final charge = double.tryParse(_chargePerUnit.text.trim()) ?? 0;
    final additional = double.tryParse(_additional.text.trim()) ?? 0;
    final unitCost =
        componentCost +
        charge +
        (outputQuantity > 0 ? additional / outputQuantity : 0);

    return AppScreenScaffold(
      icon: Icons.handyman_rounded,
      title: _isEditing ? 'Edit Job Work' : 'New Job Work',
      iconColor: AppTheme.violetColor,
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            FormSection(
              title: 'Who and what',
              icon: Icons.store_rounded,
              index: 0,
              children: [
                EntityPickerField(
                  label: 'Subcontractor',
                  icon: Icons.store_rounded,
                  value: _vendorName.isEmpty ? null : _vendorName,
                  onTap: _pickVendor,
                ),
                const SizedBox(height: 12),
                EntityPickerField(
                  label: 'Finished product',
                  icon: Icons.inventory_2_rounded,
                  value: _outputProductName.isEmpty
                      ? null
                      : _outputProductName,
                  onTap: _pickOutput,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: CustomTextField(
                        controller: _outputQuantity,
                        label: 'Units expected',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CustomTextField(
                        controller: _reference,
                        label: 'Reference',
                        hint: 'Optional',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickBom,
                  icon: const Icon(Icons.account_tree_rounded, size: 18),
                  label: const Text('Start from a bill of materials'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FormSection(
              title: 'Components per finished unit',
              icon: Icons.outbox_rounded,
              index: 1,
              trailing: TextButton.icon(
                onPressed: _addComponent,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add'),
              ),
              children: [
                if (_components.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Nothing to send out yet.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                  )
                else
                  for (var i = 0; i < _components.length; i++)
                    _ComponentEditor(
                      key: ValueKey(_components[i].productId),
                      component: _components[i],
                      totalUnits: outputQuantity,
                      available: products
                          .where((p) => p.id == _components[i].productId)
                          .map((p) => p.availableAtLocation(_issueLocation))
                          .firstOrNull,
                      onChanged: (component) => setState(() {
                        final next = [..._components];
                        next[i] = component;
                        _components = next;
                      }),
                      onRemove: () => setState(() {
                        final next = [..._components]..removeAt(i);
                        _components = next;
                      }),
                    ),
              ],
            ),
            const SizedBox(height: 12),
            FormSection(
              title: 'Charges & locations',
              icon: Icons.payments_rounded,
              index: 2,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: CustomTextField(
                        controller: _chargePerUnit,
                        label: 'Charge per unit',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CustomTextField(
                        controller: _additional,
                        label: 'Other charges',
                        helperText: 'Freight, packing',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: locations.contains(_issueLocation)
                            ? _issueLocation
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Issue from',
                        ),
                        items: [
                          for (final l in locations)
                            DropdownMenuItem(value: l, child: Text(l)),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _issueLocation = value);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: locations.contains(_receiveLocation)
                            ? _receiveLocation
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Receive into',
                        ),
                        items: [
                          for (final l in locations)
                            DropdownMenuItem(value: l, child: Text(l)),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _receiveLocation = value);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickExpected,
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
                            _expectedAt == null
                                ? 'Expected back (optional)'
                                : 'Expected '
                                      '${_expectedAt!.day}/${_expectedAt!.month}/${_expectedAt!.year}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        if (_expectedAt != null)
                          IconButton(
                            onPressed: () =>
                                setState(() => _expectedAt = null),
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                      ],
                    ),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _updateOutputCost,
                  onChanged: (value) =>
                      setState(() => _updateOutputCost = value),
                  title: const Text('Write the computed cost to the product'),
                  subtitle: Text(
                    'Receiving records a price history row, exactly as a '
                    'landed cost sheet does.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSec(context),
                    ),
                  ),
                ),
                CustomTextField(
                  controller: _notes,
                  label: 'Notes',
                  maxLines: 2,
                ),
              ],
            ),
            const SizedBox(height: 12),
            GlassPanel(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Cost per finished unit',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Components ${Money.withSymbol(symbol, componentCost)} '
                          '+ conversion '
                          '${Money.withSymbol(symbol, unitCost - componentCost)}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.textSec(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    Money.withSymbol(symbol, unitCost),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
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
                label: Text(_isEditing ? 'Save changes' : 'Create draft job'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Creating a draft moves nothing. Components leave the shelf only '
              'when the job is issued, and they stay yours — in an "At vendor" '
              'bucket — until finished goods come back.',
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

class _ComponentEditor extends StatefulWidget {
  const _ComponentEditor({
    super.key,
    required this.component,
    required this.totalUnits,
    required this.available,
    required this.onChanged,
    required this.onRemove,
  });

  final JobWorkComponent component;
  final int totalUnits;
  final int? available;
  final ValueChanged<JobWorkComponent> onChanged;
  final VoidCallback onRemove;

  @override
  State<_ComponentEditor> createState() => _ComponentEditorState();
}

class _ComponentEditorState extends State<_ComponentEditor> {
  late final TextEditingController _perUnit = TextEditingController(
    text: '${widget.component.quantityPerOutput}',
  );

  @override
  void dispose() {
    _perUnit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needed = widget.component.quantityPerOutput * widget.totalUnits;
    final available = widget.available;
    final short = available != null && needed > available;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.component.productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Issues $needed ${widget.component.unit}'
                    '${available == null ? '' : ' · $available available'}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: short
                          ? AppTheme.dangerColor
                          : AppTheme.textSec(context),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 88,
              child: TextField(
                controller: _perUnit,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  labelText: 'Per unit',
                  isDense: true,
                ),
                onChanged: (value) => widget.onChanged(
                  widget.component.copyWith(
                    quantityPerOutput: int.tryParse(value) ?? 0,
                  ),
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
      ),
    );
  }
}
