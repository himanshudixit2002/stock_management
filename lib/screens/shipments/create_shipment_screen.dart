import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../models/sales_order_model.dart';
import '../../models/shipment_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/sales_order_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/shipment_provider.dart';
import '../../utils/dialogs.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/entity_picker_field.dart';
import '../../widgets/form_section.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/searchable_picker.dart';

/// Raises a pick list against a sales order.
class CreateShipmentScreen extends StatefulWidget {
  const CreateShipmentScreen({super.key, this.salesOrderId});

  /// Pre-selects an order when the screen is opened from one.
  final String? salesOrderId;

  @override
  State<CreateShipmentScreen> createState() => _CreateShipmentScreenState();
}

class _CreateShipmentScreenState extends State<CreateShipmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _shipmentNumber = TextEditingController();
  final _carrier = TextEditingController();
  final _tracking = TextEditingController();
  final _packages = TextEditingController(text: '1');
  final _weight = TextEditingController();
  final _notes = TextEditingController();

  SalesOrderModel? _order;
  String _location = '';
  List<ShipmentLine> _lines = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final companyId = context.read<SettingsProvider>().companyId;
      if (companyId.isNotEmpty) {
        context.read<ShipmentProvider>().initialize(companyId: companyId);
      }
      final locations = context.read<SettingsProvider>().locations;
      setState(() {
        _location = locations.isNotEmpty ? locations.first : 'Main';
      });
      final preselected = widget.salesOrderId;
      if (preselected != null && preselected.isNotEmpty) {
        final order = context.read<SalesOrderProvider>().getOrderById(
          preselected,
        );
        if (order != null) _selectOrder(order);
      }
    });
  }

  @override
  void dispose() {
    _shipmentNumber.dispose();
    _carrier.dispose();
    _tracking.dispose();
    _packages.dispose();
    _weight.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Orders with something still to send.
  List<SalesOrderModel> get _shippableOrders => context
      .read<SalesOrderProvider>()
      .orders
      .where(
        (o) =>
            (o.status == SOStatus.confirmed ||
                o.status == SOStatus.dispatched) &&
            o.remainingUnits > 0,
      )
      .toList();

  void _selectOrder(SalesOrderModel order) {
    final shipments = context.read<ShipmentProvider>();
    setState(() {
      _order = order;
      _lines = [
        for (var i = 0; i < order.items.length; i++)
          if (order.items[i].remainingToDispatch -
                  shipments.committedForOrderLine(order.id, i) >
              0)
            ShipmentLine(
              productId: order.items[i].productId,
              productName: order.items[i].productName,
              orderItemIndex: i,
              // What is left after any other open shipment has already claimed
              // its share, so two pick lists cannot promise the same units.
              orderedQuantity:
                  order.items[i].remainingToDispatch -
                  shipments.committedForOrderLine(order.id, i),
              pickedQuantity:
                  order.items[i].remainingToDispatch -
                  shipments.committedForOrderLine(order.id, i),
              location: _location,
            ),
      ];
    });
  }

  Future<void> _pickOrder() async {
    final orders = _shippableOrders;
    if (orders.isEmpty) {
      showInfoSnackBar(
        context,
        'No confirmed sales orders have anything left to send.',
      );
      return;
    }
    final selected = await showSearchablePicker(
      context: context,
      title: 'Which order is being shipped?',
      selectedValue: _order?.id,
      items: [
        for (final order in orders)
          PickerItem(
            value: order.id,
            label: order.customerName.isEmpty
                ? 'Order ${order.id.substring(0, 6)}'
                : order.customerName,
            subtitle: '${order.remainingUnits} units left to send',
            icon: Icons.receipt_long_rounded,
          ),
      ],
    );
    if (selected == null || !mounted) return;
    final order = orders.firstWhere((o) => o.id == selected);
    _selectOrder(order);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final order = _order;
    if (order == null) {
      showErrorSnackBar(context, 'Choose the sales order being shipped.');
      return;
    }
    final lines = _lines.where((l) => l.orderedQuantity > 0).toList();
    if (lines.isEmpty) {
      showErrorSnackBar(context, 'There is nothing left to pick on this order.');
      return;
    }

    final user = context.read<AuthProvider>().currentUser;
    final provider = context.read<ShipmentProvider>();
    final now = DateTime.now();
    final anythingPicked = lines.any((l) => l.pickedQuantity > 0);

    final shipment = ShipmentModel(
      id: '',
      shipmentNumber: _shipmentNumber.text.trim(),
      salesOrderId: order.id,
      customerId: order.customerId,
      customerName: order.customerName,
      status: anythingPicked ? ShipmentStatus.picking : ShipmentStatus.draft,
      lines: [for (final line in lines) line.copyWith(location: _location)],
      location: _location,
      packageCount: int.tryParse(_packages.text.trim()) ?? 1,
      weightKg: double.tryParse(_weight.text.trim()) ?? 0,
      carrier: _carrier.text.trim(),
      trackingReference: _tracking.text.trim(),
      notes: _notes.text.trim(),
      pickedBy: anythingPicked ? (user?.uid ?? '') : '',
      pickedByName: anythingPicked ? (user?.name ?? '') : '',
      pickedAt: anythingPicked ? now : null,
      createdBy: user?.uid ?? '',
      createdByName: user?.name ?? '',
      createdAt: now,
      updatedAt: now,
    );

    final id = await provider.addShipment(shipment);
    if (!mounted) return;
    if (id != null) {
      Navigator.of(context).pop();
      showSuccessSnackBar(context, 'Shipment raised.');
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Save failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.manageShipments,
      featureName: 'Shipments',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final locations = context.watch<SettingsProvider>().locations;
    final busy = context.watch<ShipmentProvider>().isBusy;
    final products = context.watch<ProductProvider>().analyticsProducts;

    return AppScreenScaffold(
      icon: Icons.inventory_rounded,
      title: 'New Shipment',
      iconColor: AppTheme.indigoColor,
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            FormSection(
              title: 'What is being sent',
              icon: Icons.receipt_long_rounded,
              index: 0,
              children: [
                EntityPickerField(
                  label: 'Sales order',
                  icon: Icons.receipt_long_rounded,
                  value: _order == null
                      ? null
                      : (_order!.customerName.isEmpty
                            ? _order!.id
                            : _order!.customerName),
                  detail: _order == null
                      ? null
                      : '${_order!.remainingUnits} units left to send',
                  onTap: _pickOrder,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: locations.contains(_location)
                      ? _location
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Picking from',
                  ),
                  items: [
                    for (final location in locations)
                      DropdownMenuItem(value: location, child: Text(location)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _location = value;
                      _lines = [
                        for (final line in _lines) line.copyWith(location: value),
                      ];
                    });
                  },
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _shipmentNumber,
                  label: 'Shipment number (optional)',
                  hint: 'Your own docket or challan number',
                ),
              ],
            ),
            const SizedBox(height: 12),
            FormSection(
              title: 'Pick list',
              icon: Icons.playlist_add_check_rounded,
              index: 1,
              children: [
                if (_lines.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      _order == null
                          ? 'Choose an order to build its pick list.'
                          : 'Every line on this order is already on a shipment.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                  )
                else
                  for (var i = 0; i < _lines.length; i++)
                    _PickLineEditor(
                      key: ValueKey('${_lines[i].productId}-$i'),
                      line: _lines[i],
                      available: products
                          .where((p) => p.id == _lines[i].productId)
                          .map((p) => p.availableAtLocation(_location))
                          .firstOrNull,
                      onChanged: (line) => setState(() {
                        final next = [..._lines];
                        next[i] = line;
                        _lines = next;
                      }),
                    ),
              ],
            ),
            const SizedBox(height: 12),
            FormSection(
              title: 'Packing & carrier',
              icon: Icons.local_shipping_outlined,
              index: 2,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: CustomTextField(
                        controller: _packages,
                        label: 'Packages',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CustomTextField(
                        controller: _weight,
                        label: 'Weight (kg)',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _carrier,
                  label: 'Carrier (optional)',
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _tracking,
                  label: 'Tracking reference (optional)',
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _notes,
                  label: 'Notes',
                  maxLines: 2,
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
                label: const Text('Create shipment'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Raising a shipment moves no stock. The units leave when the '
              'packed shipment is dispatched, through the sales order.',
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

class _PickLineEditor extends StatefulWidget {
  const _PickLineEditor({
    super.key,
    required this.line,
    required this.available,
    required this.onChanged,
  });

  final ShipmentLine line;
  final int? available;
  final ValueChanged<ShipmentLine> onChanged;

  @override
  State<_PickLineEditor> createState() => _PickLineEditorState();
}

class _PickLineEditorState extends State<_PickLineEditor> {
  late final TextEditingController _picked = TextEditingController(
    text: '${widget.line.pickedQuantity}',
  );

  @override
  void dispose() {
    _picked.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.available;
    final short = widget.line.pickedQuantity < widget.line.orderedQuantity;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
                    'Ordered ${widget.line.orderedQuantity}'
                    '${available == null ? '' : ' · $available on the shelf'}'
                    '${short ? ' · short by ${widget.line.orderedQuantity - widget.line.pickedQuantity}' : ''}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: short
                          ? AppTheme.warningColor
                          : AppTheme.textSec(context),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 88,
              child: TextField(
                controller: _picked,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  labelText: 'Picked',
                  isDense: true,
                ),
                onChanged: (value) {
                  final picked = int.tryParse(value) ?? 0;
                  widget.onChanged(
                    widget.line.copyWith(
                      pickedQuantity: picked,
                      packedQuantity: picked,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
