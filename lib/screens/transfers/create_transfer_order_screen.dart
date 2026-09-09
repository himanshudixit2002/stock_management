import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../models/transfer_order_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/transfer_order_provider.dart';
import '../../utils/dialogs.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/form_section.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/product_picker.dart';

/// Raises a draft transfer between two locations.
class CreateTransferOrderScreen extends StatefulWidget {
  const CreateTransferOrderScreen({super.key, this.order});

  /// An existing draft being edited. Dispatched orders are not editable.
  final TransferOrderModel? order;

  @override
  State<CreateTransferOrderScreen> createState() =>
      _CreateTransferOrderScreenState();
}

class _CreateTransferOrderScreenState extends State<CreateTransferOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reference = TextEditingController();
  final _carrier = TextEditingController();
  final _tracking = TextEditingController();
  final _notes = TextEditingController();

  String _from = '';
  String _to = '';
  DateTime? _expectedAt;
  List<TransferOrderLine> _lines = [];

  bool get _isEditing => widget.order != null;

  @override
  void initState() {
    super.initState();
    final order = widget.order;
    final locations = context.read<SettingsProvider>().locations;
    if (order != null) {
      _reference.text = order.referenceNumber;
      _carrier.text = order.carrier;
      _tracking.text = order.trackingReference;
      _notes.text = order.notes;
      _from = order.fromLocation;
      _to = order.toLocation;
      _expectedAt = order.expectedAt;
      _lines = [...order.lines];
    } else {
      _from = locations.isNotEmpty ? locations.first : 'Main';
      _to = locations.length > 1 ? locations[1] : '';
    }
  }

  @override
  void dispose() {
    _reference.dispose();
    _carrier.dispose();
    _tracking.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _addLine() async {
    final products = context.read<ProductProvider>().analyticsProducts;
    final picked = await showProductPicker(
      context: context,
      products: products,
      title: 'Add a product to move',
    );
    if (picked == null || !mounted) return;
    if (_lines.any((l) => l.productId == picked.id)) {
      showInfoSnackBar(context, '${picked.name} is already on this transfer.');
      return;
    }
    setState(() {
      _lines = [
        ..._lines,
        TransferOrderLine(
          productId: picked.id,
          productName: picked.name,
          unit: picked.unit,
          quantity: 1,
        ),
      ];
    });
  }

  Future<void> _pickExpected() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expectedAt ?? now.add(const Duration(days: 3)),
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null && mounted) setState(() => _expectedAt = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_from.isEmpty || _to.isEmpty) {
      showErrorSnackBar(context, 'Choose both locations.');
      return;
    }
    if (_from == _to) {
      showErrorSnackBar(
        context,
        'Source and destination must be different locations.',
      );
      return;
    }
    final lines = _lines.where((l) => l.quantity > 0).toList();
    if (lines.isEmpty) {
      showErrorSnackBar(context, 'Add at least one product to move.');
      return;
    }

    final user = context.read<AuthProvider>().currentUser;
    final provider = context.read<TransferOrderProvider>();
    final now = DateTime.now();
    final existing = widget.order;

    final order = TransferOrderModel(
      id: existing?.id ?? '',
      referenceNumber: _reference.text.trim(),
      fromLocation: _from,
      toLocation: _to,
      status: existing?.status ?? TransferOrderStatus.draft,
      lines: lines,
      notes: _notes.text.trim(),
      carrier: _carrier.text.trim(),
      trackingReference: _tracking.text.trim(),
      expectedAt: _expectedAt,
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
        _isEditing ? 'Transfer updated.' : 'Transfer drafted.',
      );
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Save failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.createTransferOrders,
      featureName: 'Transfer Orders',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final locations = context.watch<SettingsProvider>().locations;
    final busy = context.watch<TransferOrderProvider>().isBusy;
    final products = context.watch<ProductProvider>().analyticsProducts;

    return AppScreenScaffold(
      icon: Icons.local_shipping_rounded,
      title: _isEditing ? 'Edit Transfer' : 'New Transfer',
      iconColor: AppTheme.infoColor,
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            FormSection(
              title: 'Route',
              icon: Icons.route_rounded,
              index: 0,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: locations.contains(_from) ? _from : null,
                        decoration: const InputDecoration(labelText: 'From'),
                        items: [
                          for (final location in locations)
                            DropdownMenuItem(
                              value: location,
                              child: Text(location),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _from = value);
                        },
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.arrow_forward_rounded, size: 18),
                    ),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: locations.contains(_to) ? _to : null,
                        decoration: const InputDecoration(labelText: 'To'),
                        items: [
                          for (final location in locations)
                            DropdownMenuItem(
                              value: location,
                              child: Text(location),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _to = value);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _reference,
                  label: 'Reference (optional)',
                  hint: 'Your own docket or challan number',
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
                                ? 'Expected arrival (optional)'
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
              ],
            ),
            const SizedBox(height: 12),
            FormSection(
              title: 'What is moving',
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
                      'Nothing added yet.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                  )
                else
                  for (var i = 0; i < _lines.length; i++)
                    _LineEditor(
                      line: _lines[i],
                      // What the source location can actually spare right now,
                      // so an over-quantity is caught here rather than at
                      // dispatch.
                      available: products
                          .where((p) => p.id == _lines[i].productId)
                          .map((p) => p.availableAtLocation(_from))
                          .firstOrNull,
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
              title: 'Shipping',
              icon: Icons.local_shipping_outlined,
              index: 2,
              children: [
                CustomTextField(
                  controller: _carrier,
                  label: 'Carrier (optional)',
                  hint: 'Who is moving it',
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _tracking,
                  label: 'Tracking reference (optional)',
                  hint: 'Vehicle number, LR number, tracking id',
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _notes,
                  label: 'Notes',
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
                label: Text(
                  _isEditing ? 'Save changes' : 'Create draft transfer',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Creating a draft moves nothing. Stock leaves the source only '
              'when the transfer is dispatched.',
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

class _LineEditor extends StatefulWidget {
  const _LineEditor({
    required this.line,
    required this.available,
    required this.onChanged,
    required this.onRemove,
  });

  final TransferOrderLine line;
  final int? available;
  final ValueChanged<TransferOrderLine> onChanged;
  final VoidCallback onRemove;

  @override
  State<_LineEditor> createState() => _LineEditorState();
}

class _LineEditorState extends State<_LineEditor> {
  late final TextEditingController _quantity =
      TextEditingController(text: '${widget.line.quantity}');

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.available;
    final over = available != null && widget.line.quantity > available;

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
                    widget.line.productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    available == null
                        ? 'Availability unknown'
                        : '$available available at source',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: over
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
