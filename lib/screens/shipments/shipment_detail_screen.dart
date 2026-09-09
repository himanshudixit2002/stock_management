import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../models/shipment_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/sales_order_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/shipment_provider.dart';
import '../../services/database_service.dart';
import '../../utils/dialogs.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/not_found_state.dart';
import '../../widgets/permission_gate.dart';
import 'shipment_list_screen.dart' show ShipmentCard;

/// One shipment: pick it, pack it, send it.
class ShipmentDetailScreen extends StatefulWidget {
  const ShipmentDetailScreen({super.key, required this.shipmentId});

  final String shipmentId;

  @override
  State<ShipmentDetailScreen> createState() => _ShipmentDetailScreenState();
}

class _ShipmentDetailScreenState extends State<ShipmentDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final companyId = context.read<SettingsProvider>().companyId;
      if (companyId.isNotEmpty) {
        context.read<ShipmentProvider>().initialize(companyId: companyId);
      }
    });
  }

  Future<void> _editPick(ShipmentModel shipment) async {
    final controllers = {
      for (var i = 0; i < shipment.lines.length; i++)
        i: TextEditingController(text: '${shipment.lines[i].pickedQuantity}'),
    };

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Record what was picked',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < shipment.lines.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${shipment.lines[i].productName}\n'
                        'ordered ${shipment.lines[i].orderedQuantity}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: controllers[i],
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          labelText: 'Picked',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(sheetCtx, true),
                child: const Text('Save pick'),
              ),
            ),
          ],
        ),
      ),
    );

    final picks = {
      for (final entry in controllers.entries)
        entry.key: int.tryParse(entry.value.text) ?? 0,
    };
    for (final c in controllers.values) {
      c.dispose();
    }
    if (saved != true || !mounted) return;

    final user = context.read<AuthProvider>().currentUser;
    final provider = context.read<ShipmentProvider>();
    final lines = [
      for (var i = 0; i < shipment.lines.length; i++)
        shipment.lines[i].copyWith(
          pickedQuantity: picks[i] ?? shipment.lines[i].pickedQuantity,
          // Packing a line you have not picked is not a thing, so packed
          // follows picked down but is set deliberately when packing.
          packedQuantity: (picks[i] ?? shipment.lines[i].pickedQuantity) <
                  shipment.lines[i].packedQuantity
              ? (picks[i] ?? 0)
              : shipment.lines[i].packedQuantity,
        ),
    ];

    final ok = await provider.updateShipment(
      shipment.copyWith(
        lines: lines,
        status: ShipmentStatus.picking,
        pickedBy: user?.uid ?? shipment.pickedBy,
        pickedByName: user?.name ?? shipment.pickedByName,
        pickedAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    if (!mounted) return;
    if (ok) {
      showSuccessSnackBar(context, 'Pick recorded.');
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Could not save.');
    }
  }

  Future<void> _pack(ShipmentModel shipment) async {
    final provider = context.read<ShipmentProvider>();
    final ok = await provider.updateShipment(
      shipment.copyWith(
        lines: [
          for (final line in shipment.lines)
            line.copyWith(packedQuantity: line.pickedQuantity),
        ],
        status: ShipmentStatus.packed,
        packedAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    if (!mounted) return;
    if (ok) {
      showSuccessSnackBar(context, 'Packed and ready to go.');
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Could not pack.');
    }
  }

  Future<void> _dispatch(ShipmentModel shipment) async {
    final order = context.read<SalesOrderProvider>().getOrderById(
      shipment.salesOrderId,
    );
    if (order == null) {
      showErrorSnackBar(
        context,
        'The sales order behind this shipment no longer exists.',
      );
      return;
    }
    final confirmed = await showConfirmDialog(
      context,
      title: 'Dispatch this shipment?',
      message:
          '${shipment.totalPacked} unit(s) leave ${shipment.location} and the '
          'sales order is updated. This cannot be undone from here.',
      confirmLabel: 'Dispatch',
      icon: Icons.local_shipping_rounded,
      iconColor: AppTheme.infoColor,
    );
    if (!confirmed || !mounted) return;

    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;

    // The stock moves through the sales order — the one path that consumes this
    // order's reserved holds from the locations they were held at. Only once it
    // has actually moved is the shipment stamped: a repeat attempt dispatches
    // nothing, because the order has no remaining units, and simply re-stamps.
    final moved = await context.read<SalesOrderProvider>().dispatchOrderItems(
      order: order,
      dispatchByItemIndex: shipment.dispatchByOrderIndex,
      userId: user.uid,
      userName: user.name,
      location: shipment.location,
      db: DatabaseService()
        ..setCompanyId(context.read<SettingsProvider>().companyId),
    );

    if (!mounted) return;
    if (!moved) {
      showErrorSnackBar(
        context,
        context.read<SalesOrderProvider>().errorMessage ?? 'Dispatch failed.',
      );
      return;
    }

    final provider = context.read<ShipmentProvider>();
    final stamped = await provider.markDispatched(
      shipment: shipment,
      userId: user.uid,
      userName: user.name,
    );
    if (!mounted) return;

    context.read<ProductProvider>().invalidateAnalytics();
    context.read<ProductProvider>().refreshProductsByIds(
      shipment.lines.map((l) => l.productId),
    );
    HapticFeedback.mediumImpact();

    if (stamped) {
      showSuccessSnackBar(context, 'Shipment dispatched.');
    } else {
      showErrorSnackBar(
        context,
        'The stock moved, but the shipment could not be stamped. Try '
        'dispatching again — it will not move the stock twice.',
      );
    }
  }

  Future<void> _deliver(ShipmentModel shipment) async {
    final provider = context.read<ShipmentProvider>();
    final ok = await provider.updateShipment(
      shipment.copyWith(
        status: ShipmentStatus.delivered,
        deliveredAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    if (!mounted) return;
    if (ok) {
      showSuccessSnackBar(context, 'Marked delivered.');
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Could not update.');
    }
  }

  Future<void> _cancel(ShipmentModel shipment) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Cancel this shipment?',
      message:
          'The units go back to being unclaimed on the sales order, so another '
          'shipment can pick them.',
      confirmLabel: 'Cancel shipment',
    );
    if (!confirmed || !mounted) return;
    final provider = context.read<ShipmentProvider>();
    final ok = await provider.updateShipment(
      shipment.copyWith(
        status: ShipmentStatus.cancelled,
        updatedAt: DateTime.now(),
      ),
    );
    if (!mounted) return;
    if (ok) {
      showSuccessSnackBar(context, 'Shipment cancelled.');
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Could not cancel.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewShipments,
      featureName: 'Shipments',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final provider = context.watch<ShipmentProvider>();
    final shipment = provider.byId(widget.shipmentId);

    if (shipment == null) {
      return AppScreenScaffold(
        icon: Icons.inventory_rounded,
        title: 'Shipment',
        iconColor: AppTheme.indigoColor,
        isLoading: provider.isLoading,
        body: const NotFoundState(
          icon: Icons.inventory_rounded,
          title: 'Shipment not found',
          message: 'It may have been deleted since this link was opened.',
        ),
      );
    }

    final user = context.watch<AuthProvider>().currentUser;
    final canManage =
        user?.hasPermission(AppPermissions.manageShipments) ?? false;
    final canDispatch =
        user?.hasPermission(AppPermissions.dispatchShipments) ?? false;
    final busy = provider.isBusy;

    return AppScreenScaffold(
      icon: Icons.inventory_rounded,
      title: shipment.shipmentNumber.isEmpty
          ? 'Shipment'
          : shipment.shipmentNumber,
      subtitle: shipment.customerName,
      iconColor: ShipmentCard.statusColor(shipment.status),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          GlassPanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shipment.statusLabel,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: ShipmentCard.statusColor(shipment.status),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _Stat(
                        label: 'Ordered',
                        value: '${shipment.totalOrdered}',
                      ),
                    ),
                    Expanded(
                      child: _Stat(
                        label: 'Picked',
                        value: '${shipment.totalPicked}',
                        warn: shipment.totalPicked < shipment.totalOrdered,
                      ),
                    ),
                    Expanded(
                      child: _Stat(
                        label: 'Packed',
                        value: '${shipment.totalPacked}',
                      ),
                    ),
                    Expanded(
                      child: _Stat(
                        label: 'Packages',
                        value: '${shipment.packageCount}',
                      ),
                    ),
                  ],
                ),
                if (shipment.carrier.isNotEmpty ||
                    shipment.trackingReference.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    [
                      if (shipment.carrier.isNotEmpty) shipment.carrier,
                      if (shipment.trackingReference.isNotEmpty)
                        shipment.trackingReference,
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.textSec(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          GlassSectionCard(
            title: 'Lines',
            icon: Icons.playlist_add_check_rounded,
            child: Column(
              children: [
                for (final line in shipment.lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                line.productName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'ordered ${line.orderedQuantity} · picked '
                                '${line.pickedQuantity} · packed '
                                '${line.packedQuantity}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: line.shortPicked > 0
                                      ? AppTheme.warningColor
                                      : AppTheme.textSec(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (line.shortPicked > 0)
                          Text(
                            'short ${line.shortPicked}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.warningColor,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (canManage && shipment.canEdit)
            _ActionButton(
              icon: Icons.edit_note_rounded,
              label: 'Record the pick',
              onPressed: busy ? null : () => _editPick(shipment),
            ),
          if (canManage && shipment.canPack)
            _ActionButton(
              icon: Icons.inventory_2_rounded,
              label: 'Mark packed',
              color: AppTheme.infoColor,
              onPressed: busy ? null : () => _pack(shipment),
            ),
          if (canDispatch && shipment.canDispatch)
            _ActionButton(
              icon: Icons.local_shipping_rounded,
              label: 'Dispatch (moves stock)',
              color: AppTheme.violetColor,
              onPressed: busy ? null : () => _dispatch(shipment),
            ),
          if (canManage && shipment.canDeliver)
            _ActionButton(
              icon: Icons.task_alt_rounded,
              label: 'Mark delivered',
              color: AppTheme.successColor,
              onPressed: busy ? null : () => _deliver(shipment),
            ),
          if (canManage && shipment.canCancel)
            _ActionButton(
              icon: Icons.cancel_rounded,
              label: 'Cancel shipment',
              color: AppTheme.dangerColor,
              onPressed: busy ? null : () => _cancel(shipment),
            ),
          if (shipment.status == ShipmentStatus.packed && !canDispatch)
            Text(
              'This shipment is packed. Sending it out needs the Dispatch '
              'Shipments permission.',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSec(context),
              ),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.warn = false});

  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: warn ? AppTheme.warningColor : null,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11.5, color: AppTheme.textSec(context)),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: color == null
              ? null
              : FilledButton.styleFrom(backgroundColor: color),
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        ),
      ),
    );
  }
}
