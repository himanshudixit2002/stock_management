import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/app_navigation.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/transfer_order_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/transfer_order_provider.dart';
import '../../services/database_service.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/not_found_state.dart';
import '../../widgets/permission_gate.dart';
import 'transfer_order_list_screen.dart' show TransferOrderCard;

/// One transfer: dispatch it, receive it, or cancel it.
class TransferOrderDetailScreen extends StatelessWidget {
  const TransferOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy, HH:mm');

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewTransferOrders,
      featureName: 'Transfer Orders',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final provider = context.watch<TransferOrderProvider>();
    // Read from the live list rather than holding the model passed in: after a
    // dispatch or receipt the stream has newer line quantities, and rendering
    // the stale copy would show an order that could be received twice.
    final order = provider.byId(orderId);
    if (order == null) {
      return const NotFoundState(
        title: 'Transfer not found',
        message: 'It may have been deleted, or belongs to another workspace.',
      );
    }

    final user = context.read<AuthProvider>().currentUser;
    final canDispatch =
        user?.hasPermission(AppPermissions.dispatchTransferOrders) ?? false;
    final canReceive =
        user?.hasPermission(AppPermissions.receiveTransferOrders) ?? false;
    final canEdit =
        user?.hasPermission(AppPermissions.createTransferOrders) ?? false;

    return AppScreenScaffold(
      icon: Icons.local_shipping_rounded,
      title: '${order.fromLocation} → ${order.toLocation}',
      subtitle: order.statusLabel,
      iconColor: TransferOrderCard.statusColor(order.status),
      actions: [
        if (canEdit && order.canEdit)
          IconButton(
            onPressed: () => context.pushAppRoute(
              AppRoutes.createTransferOrder,
              extra: order,
            ),
            icon: const Icon(Icons.edit_rounded),
            tooltip: 'Edit',
          ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _Summary(order: order, dateFormat: _dateFormat),
          const SizedBox(height: 12),
          _Lines(order: order),
          const SizedBox(height: 16),
          _Actions(
            order: order,
            canDispatch: canDispatch,
            canReceive: canReceive,
            busy: provider.isBusy,
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.order, required this.dateFormat});

  final TransferOrderModel order;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 20,
            runSpacing: 12,
            children: [
              _Fact(label: 'Ordered', value: '${order.totalQuantity} units'),
              _Fact(label: 'Dispatched', value: '${order.totalDispatched}'),
              _Fact(label: 'Received', value: '${order.totalReceived}'),
              _Fact(
                label: 'In transit',
                value: '${order.totalInTransit}',
                accent: order.totalInTransit > 0 ? AppTheme.infoColor : null,
              ),
            ],
          ),
          if (order.referenceNumber.isNotEmpty ||
              order.carrier.isNotEmpty ||
              order.trackingReference.isNotEmpty) ...[
            const Divider(height: 24),
            Wrap(
              spacing: 20,
              runSpacing: 12,
              children: [
                if (order.referenceNumber.isNotEmpty)
                  _Fact(label: 'Reference', value: order.referenceNumber),
                if (order.carrier.isNotEmpty)
                  _Fact(label: 'Carrier', value: order.carrier),
                if (order.trackingReference.isNotEmpty)
                  _Fact(label: 'Tracking', value: order.trackingReference),
              ],
            ),
          ],
          const Divider(height: 24),
          if (order.dispatchedAt != null)
            _Timeline(
              icon: Icons.outbound_rounded,
              label: 'Dispatched',
              detail:
                  '${dateFormat.format(order.dispatchedAt!)} · ${order.dispatchedByName}',
            ),
          if (order.expectedAt != null)
            _Timeline(
              icon: Icons.event_rounded,
              label: 'Expected',
              detail: DateFormat('dd MMM yyyy').format(order.expectedAt!),
              accent: order.isOverdue ? AppTheme.dangerColor : null,
            ),
          if (order.receivedAt != null)
            _Timeline(
              icon: Icons.move_to_inbox_rounded,
              label: 'Received',
              detail:
                  '${dateFormat.format(order.receivedAt!)} · ${order.receivedByName}',
            ),
          if (order.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              order.notes,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSec(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.icon,
    required this.label,
    required this.detail,
    this.accent,
  });

  final IconData icon;
  final String label;
  final String detail;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppTheme.textSec(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _Lines extends StatelessWidget {
  const _Lines({required this.order});

  final TransferOrderModel order;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Lines',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final line in order.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      line.productName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5),
                    ),
                  ),
                  Text(
                    '${line.receivedQuantity} / ${line.dispatchedQuantity} of '
                    '${line.quantity} ${line.unit}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: line.inTransitQuantity > 0
                          ? AppTheme.infoColor
                          : AppTheme.textSec(context),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Received / dispatched of ordered. Stock sits in '
            '"${DatabaseService.inTransitLocation}" between the two.',
            style: TextStyle(
              fontSize: 11.5,
              color: AppTheme.textSec(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.order,
    required this.canDispatch,
    required this.canReceive,
    required this.busy,
  });

  final TransferOrderModel order;
  final bool canDispatch;
  final bool canReceive;
  final bool busy;

  Future<void> _dispatch(BuildContext context) async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Dispatch ${order.totalQuantity} units?',
      message:
          'Stock leaves ${order.fromLocation} now and sits in '
          '"${DatabaseService.inTransitLocation}" until it is received.',
      confirmLabel: 'Dispatch',
      icon: Icons.outbound_rounded,
      iconColor: AppTheme.infoColor,
      confirmColor: AppTheme.infoColor,
    );
    if (!confirmed || !context.mounted) return;
    final provider = context.read<TransferOrderProvider>();
    final ok = await provider.dispatch(
      order: order,
      userId: user.uid,
      userName: user.name,
    );
    if (!context.mounted) return;
    if (ok) {
      showSuccessSnackBar(context, 'Dispatched.');
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Dispatch failed.');
    }
  }

  Future<void> _receive(BuildContext context) async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    await showResponsiveBottomSheet<void>(
      context: context,
      maxHeightFactor: 0.9,
      builder: (_) => _ReceiveSheet(
        order: order,
        userId: user.uid,
        userName: user.name,
      ),
    );
  }

  Future<void> _cancel(BuildContext context) async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Cancel this transfer?',
      message: order.totalInTransit > 0
          ? '${order.totalInTransit} units in transit go back to '
                '${order.fromLocation}.'
          : 'The draft is marked cancelled. No stock moves.',
      confirmLabel: 'Cancel transfer',
    );
    if (!confirmed || !context.mounted) return;
    final provider = context.read<TransferOrderProvider>();
    final ok = await provider.cancel(
      order: order,
      userId: user.uid,
      userName: user.name,
    );
    if (!context.mounted) return;
    if (ok) {
      showSuccessSnackBar(context, 'Transfer cancelled.');
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Cancel failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[
      if (canDispatch && order.canDispatch)
        FilledButton.icon(
          onPressed: busy ? null : () => _dispatch(context),
          icon: const Icon(Icons.outbound_rounded, size: 18),
          label: const Text('Dispatch'),
        ),
      if (canReceive && order.canReceive)
        FilledButton.icon(
          onPressed: busy ? null : () => _receive(context),
          icon: const Icon(Icons.move_to_inbox_rounded, size: 18),
          label: const Text('Receive'),
        ),
      if (order.canCancel)
        OutlinedButton.icon(
          onPressed: busy ? null : () => _cancel(context),
          icon: const Icon(Icons.cancel_outlined, size: 18),
          label: const Text('Cancel'),
        ),
    ];

    if (buttons.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 10, runSpacing: 10, children: buttons);
  }
}

/// Books in-transit units into the destination, line by line.
class _ReceiveSheet extends StatefulWidget {
  const _ReceiveSheet({
    required this.order,
    required this.userId,
    required this.userName,
  });

  final TransferOrderModel order;
  final String userId;
  final String userName;

  @override
  State<_ReceiveSheet> createState() => _ReceiveSheetState();
}

class _ReceiveSheetState extends State<_ReceiveSheet> {
  late final Map<String, TextEditingController> _controllers = {
    for (final line in widget.order.lines)
      if (line.inTransitQuantity > 0)
        line.productId: TextEditingController(
          text: '${line.inTransitQuantity}',
        ),
  };
  bool _closeShort = false;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, int> get _quantities => {
    for (final entry in _controllers.entries)
      entry.key: int.tryParse(entry.value.text.trim()) ?? 0,
  };

  Future<void> _submit() async {
    final provider = context.read<TransferOrderProvider>();
    final ok = await provider.receive(
      order: widget.order,
      quantities: _quantities,
      userId: widget.userId,
      userName: widget.userName,
      closeShort: _closeShort,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      showSuccessSnackBar(context, 'Received into ${widget.order.toLocation}.');
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Receipt failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<TransferOrderProvider>().isBusy;
    final total = _quantities.values.fold(0, (acc, v) => acc + v);

    return GlassPanel(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Receive into ${widget.order.toLocation}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            for (final line in widget.order.lines)
              if (line.inTransitQuantity > 0)
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
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${line.inTransitQuantity} in transit',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppTheme.textSec(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 88,
                        child: TextField(
                          controller: _controllers[line.productId],
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            labelText: 'Received',
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _closeShort,
              onChanged: (value) =>
                  setState(() => _closeShort = value ?? false),
              title: const Text(
                'Close the transfer short',
                style: TextStyle(fontSize: 14),
              ),
              subtitle: Text(
                'Anything not received stays out of stock and is reported as a '
                'shortage, rather than sitting in transit forever.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.textSec(context),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy || (total == 0 && !_closeShort)
                    ? null
                    : _submit,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text('Receive $total units'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.accent});

  final String label;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: AppTheme.textSec(context)),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: accent,
          ),
        ),
      ],
    );
  }
}
