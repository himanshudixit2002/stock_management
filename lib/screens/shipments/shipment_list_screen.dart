import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/app_navigation.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/shipment_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/shipment_provider.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/provider_error_banner.dart';

/// Everything being picked, packed or shipped.
class ShipmentListScreen extends StatefulWidget {
  const ShipmentListScreen({super.key});

  @override
  State<ShipmentListScreen> createState() => _ShipmentListScreenState();
}

class _ShipmentListScreenState extends State<ShipmentListScreen> {
  ShipmentStatus? _filter;

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
    final canManage = context.select<AuthProvider, bool>(
      (a) =>
          a.currentUser?.hasPermission(AppPermissions.manageShipments) ?? false,
    );

    final shipments = _filter == null
        ? provider.shipments
        : provider.shipments.where((s) => s.status == _filter).toList();

    return AppScreenScaffold(
      icon: Icons.inventory_rounded,
      title: 'Pick, Pack & Ship',
      subtitle: '${provider.open.length} open',
      iconColor: AppTheme.indigoColor,
      isLoading: provider.isLoading && provider.shipments.isEmpty,
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => context.pushAppRoute(AppRoutes.createShipment),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New shipment'),
            )
          : null,
      isEmpty: provider.shipments.isEmpty && !provider.isLoading,
      emptyState: EmptyStateWidget(
        icon: Icons.inventory_rounded,
        title: 'Nothing on the packing bench',
        subtitle:
            'A shipment records what was actually picked and packed for a '
            'sales order, so a short pick is caught at the bench rather than '
            'by the customer.',
        buttonText: canManage ? 'Raise a shipment' : null,
        onButtonPressed: canManage
            ? () => context.pushAppRoute(AppRoutes.createShipment)
            : null,
      ),
      body: Column(
        children: [
          if (provider.errorMessage != null)
            ProviderErrorBanner(
              message: provider.errorMessage!,
              onDismiss: provider.clearError,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: MetricCard(
                    label: 'To pick',
                    value: '${provider.toPick.length}',
                    icon: Icons.playlist_add_check_rounded,
                    color: AppTheme.warningColor,
                    dense: true,
                    index: 0,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MetricCard(
                    label: 'Ready to go',
                    value: '${provider.readyToDispatch.length}',
                    icon: Icons.local_shipping_rounded,
                    color: AppTheme.successColor,
                    caption: '${provider.inTransit.length} on the road',
                    dense: true,
                    index: 1,
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('All'),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                ),
                for (final status in ShipmentStatus.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(ShipmentModel.statusLabelOf(status)),
                      selected: _filter == status,
                      onSelected: (_) => setState(
                        () => _filter = _filter == status ? null : status,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              itemCount: shipments.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ShipmentCard(
                  shipment: shipments[i],
                  index: i,
                  onTap: () => context.pushAppRoute(
                    AppRoutes.shipmentDetail,
                    extra: shipments[i].id,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One shipment, summarised.
class ShipmentCard extends StatelessWidget {
  const ShipmentCard({
    super.key,
    required this.shipment,
    required this.index,
    this.onTap,
  });

  final ShipmentModel shipment;
  final int index;
  final VoidCallback? onTap;

  static final DateFormat _dateFormat = DateFormat('dd MMM');

  static Color statusColor(ShipmentStatus status) => switch (status) {
    ShipmentStatus.draft => AppTheme.textMuted,
    ShipmentStatus.picking => AppTheme.warningColor,
    ShipmentStatus.packed => AppTheme.infoColor,
    ShipmentStatus.dispatched => AppTheme.violetColor,
    ShipmentStatus.delivered => AppTheme.successColor,
    ShipmentStatus.cancelled => AppTheme.dangerColor,
  };

  @override
  Widget build(BuildContext context) {
    final color = statusColor(shipment.status);

    return AnimatedListItem(
      index: index,
      child: GlassCard(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      shipment.customerName.isEmpty
                          ? 'Shipment'
                          : shipment.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      shipment.statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                [
                  if (shipment.shipmentNumber.isNotEmpty)
                    shipment.shipmentNumber,
                  '${shipment.totalPicked}/${shipment.totalOrdered} picked',
                  if (shipment.location.isNotEmpty) shipment.location,
                  if (shipment.carrier.isNotEmpty) shipment.carrier,
                  if (shipment.dispatchedAt != null)
                    'out ${_dateFormat.format(shipment.dispatchedAt!)}',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textSec(context),
                ),
              ),
              if (shipment.status == ShipmentStatus.picking ||
                  shipment.status == ShipmentStatus.draft) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: shipment.pickProgress,
                    minHeight: 5,
                    backgroundColor: color.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
