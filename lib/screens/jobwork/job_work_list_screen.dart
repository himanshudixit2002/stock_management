import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/app_navigation.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/job_work_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/job_work_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/provider_error_banner.dart';

/// Work sent out to subcontractors.
class JobWorkListScreen extends StatefulWidget {
  const JobWorkListScreen({super.key});

  @override
  State<JobWorkListScreen> createState() => _JobWorkListScreenState();
}

class _JobWorkListScreenState extends State<JobWorkListScreen> {
  JobWorkStatus? _filter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final companyId = context.read<SettingsProvider>().companyId;
      if (companyId.isNotEmpty) {
        context.read<JobWorkProvider>().initialize(companyId: companyId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewJobWork,
      featureName: 'Job Work',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final provider = context.watch<JobWorkProvider>();
    final canManage = context.select<AuthProvider, bool>(
      (a) => a.currentUser?.hasPermission(AppPermissions.manageJobWork) ?? false,
    );

    final orders = _filter == null
        ? provider.orders
        : provider.orders.where((o) => o.status == _filter).toList();

    return AppScreenScaffold(
      icon: Icons.handyman_rounded,
      title: 'Job Work',
      subtitle: '${provider.atVendor.length} out with vendors',
      iconColor: AppTheme.violetColor,
      isLoading: provider.isLoading && provider.orders.isEmpty,
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => context.pushAppRoute(AppRoutes.createJobWork),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New job'),
            )
          : null,
      isEmpty: provider.orders.isEmpty && !provider.isLoading,
      emptyState: EmptyStateWidget(
        icon: Icons.handyman_rounded,
        title: 'Nothing out for job work',
        subtitle:
            'Send components to a plater, a tailor or a machinist and they '
            'stay on your books in an "At vendor" bucket while they are gone, '
            'instead of vanishing and reappearing as something else.',
        buttonText: canManage ? 'Raise a job' : null,
        onButtonPressed: canManage
            ? () => context.pushAppRoute(AppRoutes.createJobWork)
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
                    label: 'Units at vendors',
                    value: '${provider.unitsAtVendor}',
                    icon: Icons.outbox_rounded,
                    color: AppTheme.violetColor,
                    caption: 'Components, still yours',
                    dense: true,
                    index: 0,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MetricCard(
                    label: 'Awaited back',
                    value: '${provider.outputAwaited}',
                    icon: Icons.move_to_inbox_rounded,
                    color: provider.overdue.isEmpty
                        ? AppTheme.successColor
                        : AppTheme.dangerColor,
                    caption: '${provider.overdue.length} overdue',
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
                for (final status in JobWorkStatus.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(JobWorkOrderModel.statusLabelOf(status)),
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
                child: JobWorkCard(
                  order: orders[i],
                  index: i,
                  onTap: () => context.pushAppRoute(
                    AppRoutes.jobWorkDetail,
                    extra: orders[i].id,
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

/// One job work order, summarised.
class JobWorkCard extends StatelessWidget {
  const JobWorkCard({
    super.key,
    required this.order,
    required this.index,
    this.onTap,
  });

  final JobWorkOrderModel order;
  final int index;
  final VoidCallback? onTap;

  static final DateFormat _dateFormat = DateFormat('dd MMM');

  static Color statusColor(JobWorkStatus status) => switch (status) {
    JobWorkStatus.draft => AppTheme.textMuted,
    JobWorkStatus.issued => AppTheme.violetColor,
    JobWorkStatus.partiallyReceived => AppTheme.infoColor,
    JobWorkStatus.completed => AppTheme.successColor,
    JobWorkStatus.closed => AppTheme.warningColor,
    JobWorkStatus.cancelled => AppTheme.dangerColor,
  };

  @override
  Widget build(BuildContext context) {
    final color = statusColor(order.status);
    final days = order.daysOut;

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
                      order.outputProductName.isEmpty
                          ? 'Job work'
                          : order.outputProductName,
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
                  if (order.vendorName.isNotEmpty) order.vendorName,
                  '${order.receivedQuantity}/${order.outputQuantity} back',
                  '${order.components.length} components',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textSec(context),
                ),
              ),
              if (order.isOut) ...[
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
                          '${order.componentUnitsAtVendor} component units out',
                          if (days != null) '$days day${days == 1 ? '' : 's'}',
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
            ],
          ),
        ),
      ),
    );
  }
}
