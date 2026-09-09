import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/app_navigation.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/transfer_order_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/transfer_order_provider.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/provider_error_banner.dart';

/// Transfers between locations, including what is currently on the road.
class TransferOrderListScreen extends StatefulWidget {
  const TransferOrderListScreen({super.key});

  @override
  State<TransferOrderListScreen> createState() =>
      _TransferOrderListScreenState();
}

class _TransferOrderListScreenState extends State<TransferOrderListScreen> {
  TransferOrderStatus? _filter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final companyId = context.read<SettingsProvider>().companyId;
      if (companyId.isNotEmpty) {
        context.read<TransferOrderProvider>().initialize(companyId: companyId);
      }
    });
  }

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
    final canCreate = context.select<AuthProvider, bool>(
      (a) =>
          a.currentUser?.hasPermission(AppPermissions.createTransferOrders) ??
          false,
    );

    final orders = _filter == null
        ? provider.orders
        : provider.orders.where((o) => o.status == _filter).toList();

    return AppScreenScaffold(
      icon: Icons.local_shipping_rounded,
      title: 'Transfer Orders',
      subtitle: '${provider.inTransit.length} in transit',
      iconColor: AppTheme.infoColor,
      isLoading: provider.isLoading && provider.orders.isEmpty,
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () =>
                  context.pushAppRoute(AppRoutes.createTransferOrder),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New transfer'),
            )
          : null,
      isEmpty: provider.orders.isEmpty && !provider.isLoading,
      emptyState: EmptyStateWidget(
        icon: Icons.local_shipping_rounded,
        title: 'No transfer orders yet',
        subtitle:
            'A transfer order keeps stock visible while it is between two '
            'locations, instead of making it vanish from one and appear in the '
            'other days later.',
        buttonText: canCreate ? 'Raise a transfer' : null,
        onButtonPressed: canCreate
            ? () => context.pushAppRoute(AppRoutes.createTransferOrder)
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
                    label: 'Units in transit',
                    value: '${provider.unitsInTransit}',
                    icon: Icons.local_shipping_rounded,
                    color: AppTheme.infoColor,
                    dense: true,
                    index: 0,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MetricCard(
                    label: 'Overdue',
                    value: '${provider.overdue.length}',
                    icon: Icons.schedule_rounded,
                    color: provider.overdue.isEmpty
                        ? AppTheme.successColor
                        : AppTheme.dangerColor,
                    caption: 'Past expected arrival',
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
                for (final status in TransferOrderStatus.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(TransferOrderModel.statusLabelOf(status)),
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
              itemCount: orders.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TransferOrderCard(
                  order: orders[i],
                  index: i,
                  onTap: () => context.pushAppRoute(
                    AppRoutes.transferOrderDetail,
                    extra: orders[i],
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

/// One transfer order, summarised.
class TransferOrderCard extends StatelessWidget {
  const TransferOrderCard({
    super.key,
    required this.order,
    required this.index,
    this.onTap,
  });

  final TransferOrderModel order;
  final int index;
  final VoidCallback? onTap;

  static final DateFormat _dateFormat = DateFormat('dd MMM');

  static Color statusColor(TransferOrderStatus status) => switch (status) {
    TransferOrderStatus.draft => AppTheme.warningColor,
    TransferOrderStatus.dispatched => AppTheme.infoColor,
    TransferOrderStatus.received => AppTheme.successColor,
    TransferOrderStatus.cancelled => AppTheme.dangerColor,
  };

  @override
  Widget build(BuildContext context) {
    final color = statusColor(order.status);
    final days = order.daysInTransit;

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
                      '${order.fromLocation} → ${order.toLocation}',
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
                      order.statusLabel,
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
                  if (order.referenceNumber.isNotEmpty) order.referenceNumber,
                  '${order.lines.length} line${order.lines.length == 1 ? '' : 's'}',
                  '${order.totalQuantity} units',
                  if (order.carrier.isNotEmpty) order.carrier,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textSec(context),
                ),
              ),
              if (order.status == TransferOrderStatus.dispatched) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      order.isOverdue
                          ? Icons.warning_amber_rounded
                          : Icons.schedule_rounded,
                      size: 14,
                      color: order.isOverdue
                          ? AppTheme.dangerColor
                          : AppTheme.textSec(context),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        [
                          '${order.totalInTransit} units in transit',
                          if (days != null)
                            '$days day${days == 1 ? '' : 's'} out',
                          if (order.expectedAt != null)
                            'due ${_dateFormat.format(order.expectedAt!)}',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: order.isOverdue
                              ? AppTheme.dangerColor
                              : AppTheme.textSec(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (order.hasShortage) ...[
                const SizedBox(height: 8),
                Text(
                  'Closed short by '
                  '${order.totalDispatched - order.totalReceived} units',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.warningColor,
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
