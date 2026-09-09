import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../models/bom_model.dart';
import '../../models/product_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/bom_provider.dart';
import '../../providers/product_provider.dart';
import '../../utils/dialogs.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/entity_picker_field.dart';
import '../../widgets/form_section.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/product_picker.dart';

/// Creates or edits an assembly recipe.
class BomEditorScreen extends StatefulWidget {
  const BomEditorScreen({super.key, this.bom});

  final BomModel? bom;

  @override
  State<BomEditorScreen> createState() => _BomEditorScreenState();
}

class _BomEditorScreenState extends State<BomEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _outputQuantity = TextEditingController(text: '1');
  final _notes = TextEditingController();

  String _outputProductId = '';
  String _outputProductName = '';
  BomStatus _status = BomStatus.draft;
  List<BomComponent> _components = [];

  bool get _isEditing => widget.bom != null;

  @override
  void initState() {
    super.initState();
    final bom = widget.bom;
    if (bom != null) {
      _name.text = bom.name;
      _outputQuantity.text = '${bom.outputQuantity}';
      _notes.text = bom.notes;
      _outputProductId = bom.outputProductId;
      _outputProductName = bom.outputProductName;
      _status = bom.status;
      _components = [...bom.components];
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _outputQuantity.dispose();
    _notes.dispose();
    super.dispose();
  }

  List<ProductModel> get _products =>
      context.read<ProductProvider>().analyticsProducts;

  Future<void> _pickOutput() async {
    final picked = await showProductPicker(
      context: context,
      products: _products,
      selectedProductId: _outputProductId.isEmpty ? null : _outputProductId,
      title: 'What does this make?',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _outputProductId = picked.id;
      _outputProductName = picked.name;
    });
  }

  Future<void> _addComponent() async {
    final picked = await showProductPicker(
      context: context,
      products: _products,
      title: 'Add a component',
    );
    if (picked == null || !mounted) return;
    if (picked.id == _outputProductId) {
      showErrorSnackBar(
        context,
        'A product cannot be a component of itself — that recipe would consume '
        'and produce the same stock.',
      );
      return;
    }
    if (_components.any((c) => c.productId == picked.id)) {
      showInfoSnackBar(context, '${picked.name} is already a component.');
      return;
    }
    setState(() {
      _components = [
        ..._components,
        BomComponent(
          productId: picked.id,
          productName: picked.name,
          quantity: 1,
          unit: picked.unit,
        ),
      ];
    });
  }

  void _updateComponent(int index, BomComponent component) {
    setState(() {
      final next = [..._components];
      next[index] = component;
      _components = next;
    });
  }

  void _removeComponent(int index) {
    setState(() {
      final next = [..._components]..removeAt(index);
      _components = next;
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_outputProductId.isEmpty) {
      showErrorSnackBar(context, 'Choose the product this recipe makes.');
      return;
    }
    if (_components.isEmpty) {
      showErrorSnackBar(context, 'Add at least one component.');
      return;
    }
    if (_components.any((c) => c.quantity <= 0)) {
      showErrorSnackBar(context, 'Every component needs a quantity above zero.');
      return;
    }

    final user = context.read<AuthProvider>().currentUser;
    final provider = context.read<BomProvider>();
    final now = DateTime.now();
    final existing = widget.bom;

    final bom = BomModel(
      id: existing?.id ?? '',
      name: _name.text.trim(),
      outputProductId: _outputProductId,
      outputProductName: _outputProductName,
      outputQuantity: int.tryParse(_outputQuantity.text.trim()) ?? 1,
      components: _components,
      status: _status,
      notes: _notes.text.trim(),
      totalBuilt: existing?.totalBuilt ?? 0,
      lastBuiltAt: existing?.lastBuiltAt,
      createdBy: existing?.createdBy ?? user?.uid ?? '',
      createdByName: existing?.createdByName ?? user?.name ?? '',
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    final ok = _isEditing
        ? await provider.updateBom(bom)
        : (await provider.addBom(bom)) != null;

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      showSuccessSnackBar(
        context,
        _isEditing ? 'BOM updated.' : 'BOM created.',
      );
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Save failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.manageBoms,
      featureName: 'Bills of Materials',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final busy = context.watch<BomProvider>().isBusy;

    return AppScreenScaffold(
      icon: Icons.account_tree_rounded,
      title: _isEditing ? 'Edit BOM' : 'New BOM',
      iconColor: AppTheme.violetColor,
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            FormSection(
              title: 'Recipe',
              icon: Icons.description_rounded,
              index: 0,
              children: [
                CustomTextField(
                  controller: _name,
                  label: 'Name',
                  hint: 'e.g. Gift hamper — festive',
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Give this recipe a name'
                      : null,
                ),
                const SizedBox(height: 12),
                EntityPickerField(
                  label: 'Makes',
                  icon: Icons.inventory_2_rounded,
                  value: _outputProductName.isEmpty ? null : _outputProductName,
                  placeholder: 'Choose the finished product',
                  onTap: _pickOutput,
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _outputQuantity,
                  label: 'Units produced per run',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) {
                    final parsed = int.tryParse((value ?? '').trim()) ?? 0;
                    return parsed <= 0 ? 'Must be at least 1' : null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<BomStatus>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(
                      value: BomStatus.draft,
                      child: Text('Draft — not yet buildable'),
                    ),
                    DropdownMenuItem(
                      value: BomStatus.active,
                      child: Text('Active — ready to build'),
                    ),
                    DropdownMenuItem(
                      value: BomStatus.archived,
                      child: Text('Archived — kept for history'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _status = value);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            FormSection(
              title: 'Components',
              subtitle: 'Quantities are per run, not per unit',
              icon: Icons.category_rounded,
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
                      'No components yet. A recipe that consumes nothing would '
                      'create stock out of thin air, so at least one is '
                      'required.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                  )
                else
                  for (var i = 0; i < _components.length; i++)
                    _ComponentEditor(
                      component: _components[i],
                      onChanged: (c) => _updateComponent(i, c),
                      onRemove: () => _removeComponent(i),
                    ),
              ],
            ),
            const SizedBox(height: 12),
            FormSection(
              title: 'Notes',
              icon: Icons.sticky_note_2_rounded,
              index: 2,
              children: [
                CustomTextField(
                  controller: _notes,
                  label: 'Notes',
                  hint: 'Assembly instructions, tolerances, anything useful',
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
                label: Text(_isEditing ? 'Save changes' : 'Create BOM'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComponentEditor extends StatelessWidget {
  const _ComponentEditor({
    required this.component,
    required this.onChanged,
    required this.onRemove,
  });

  final BomComponent component;
  final ValueChanged<BomComponent> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    component.productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Remove',
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _NumberField(
                    label: 'Qty per run',
                    initial: '${component.quantity}',
                    onChanged: (value) => onChanged(
                      component.copyWith(quantity: int.tryParse(value) ?? 0),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _NumberField(
                    label: 'Wastage %',
                    initial: component.wastagePercent == 0
                        ? ''
                        : '${component.wastagePercent}',
                    allowDecimal: true,
                    onChanged: (value) => onChanged(
                      component.copyWith(
                        wastagePercent: double.tryParse(value) ?? 0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ),
            if (component.wastagePercent > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'One run consumes ${component.consumptionFor(1)} '
                  '${component.unit} including wastage',
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

/// A small numeric field that keeps its own controller, so editing one
/// component's quantity does not rebuild and reset the others.
class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.label,
    required this.initial,
    required this.onChanged,
    this.allowDecimal = false,
  });

  final String label;
  final String initial;
  final ValueChanged<String> onChanged;
  final bool allowDecimal;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: TextInputType.numberWithOptions(
        decimal: widget.allowDecimal,
      ),
      inputFormatters: [
        if (widget.allowDecimal)
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
        else
          FilteringTextInputFormatter.digitsOnly,
      ],
      decoration: InputDecoration(
        labelText: widget.label,
        isDense: true,
      ),
      onChanged: widget.onChanged,
    );
  }
}
