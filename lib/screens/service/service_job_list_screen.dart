import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/app_navigation.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/service_job_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/service_job_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/currency.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/provider_error_banner.dart';

/// Repairs and warranty jobs on the bench.
class ServiceJobListScreen extends StatefulWidget {
  const ServiceJobListScreen({super.key});

  @override
  State<ServiceJobListScreen> createState() => _ServiceJobListScreenState();
}

class _ServiceJobListScreenState extends State<ServiceJobListScreen> {
  ServiceJobStatus? _filter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final companyId = context.read<SettingsProvider>().companyId;
      if (companyId.isNotEmpty) {
        context.read<ServiceJobProvider>().initialize(companyId: companyId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewServiceJobs,
      featureName: 'Service Jobs',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final provider = context.watch<ServiceJobProvider>();
    final symbol = Money.symbolOf(context);
    final canManage = context.select<AuthProvider, bool>(
      (a) =>
          a.currentUser?.hasPermission(AppPermissions.manageServiceJobs) ??
          false,
    );

    final jobs = _filter == null
        ? provider.jobs
        : provider.jobs.where((j) => j.status == _filter).toList();

    return AppScreenScaffold(
      icon: Icons.build_circle_rounded,
      title: 'Service & Repairs',
      subtitle: '${provider.open.length} on the bench',
      iconColor: AppTheme.infoColor,
      isLoading: provider.isLoading && provider.jobs.isEmpty,
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => context.pushAppRoute(AppRoutes.createServiceJob),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Book a job in'),
            )
          : null,
      isEmpty: provider.jobs.isEmpty && !provider.isLoading,
      emptyState: EmptyStateWidget(
        icon: Icons.build_circle_rounded,
        title: 'Nothing in for repair',
        subtitle:
            'Book a unit in against its serial number and the warranty '
            'position is decided from the record rather than from memory. '
            'Parts fitted come out of stock for real.',
        buttonText: canManage ? 'Book a job in' : null,
        onButtonPressed: canManage
            ? () => context.pushAppRoute(AppRoutes.createServiceJob)
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
                    label: 'Overdue',
                    value: '${provider.overdue.length}',
                    icon: Icons.schedule_rounded,
                    color: provider.overdue.isEmpty
                        ? AppTheme.successColor
                        : AppTheme.dangerColor,
                    caption: 'Past what was promised',
                    dense: true,
                    index: 0,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MetricCard(
                    label: 'Unbilled work',
                    value: Money.compactWithSymbol(
                      symbol,
                      provider.openBillableValue,
                    ),
                    icon: Icons.receipt_long_rounded,
                    color: AppTheme.infoColor,
                    caption: '${provider.awaitingParts.length} awaiting parts',
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
                for (final status in ServiceJobStatus.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(ServiceJobModel.statusLabelOf(status)),
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
              itemCount: jobs.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ServiceJobCard(
                  job: jobs[i],
                  index: i,
                  symbol: symbol,
                  onTap: () => context.pushAppRoute(
                    AppRoutes.serviceJobDetail,
                    extra: jobs[i].id,
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

/// One job, summarised.
class ServiceJobCard extends StatelessWidget {
  const ServiceJobCard({
    super.key,
    required this.job,
    required this.index,
    required this.symbol,
    this.onTap,
  });

  final ServiceJobModel job;
  final int index;
  final String symbol;
  final VoidCallback? onTap;

  static final DateFormat _dateFormat = DateFormat('dd MMM');

  static Color statusColor(ServiceJobStatus status) => switch (status) {
    ServiceJobStatus.received => AppTheme.infoColor,
    ServiceJobStatus.diagnosed => AppTheme.indigoColor,
    ServiceJobStatus.inProgress => AppTheme.violetColor,
    ServiceJobStatus.awaitingParts => AppTheme.warningColor,
    ServiceJobStatus.resolved => AppTheme.successColor,
    ServiceJobStatus.closed => AppTheme.textMuted,
    ServiceJobStatus.cancelled => AppTheme.dangerColor,
  };

  @override
  Widget build(BuildContext context) {
    final color = statusColor(job.status);

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
                      job.customerName.isEmpty
                          ? (job.productName.isEmpty
                                ? 'Service job'
                                : job.productName)
                          : job.customerName,
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
                      job.statusLabel,
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
                  if (job.jobNumber.isNotEmpty) job.jobNumber,
                  if (job.productName.isNotEmpty) job.productName,
                  if (job.serialNumber.isNotEmpty) job.serialNumber,
                  '${job.ageDays}d old',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textSec(context),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (job.isUnderWarranty
                                  ? AppTheme.successColor
                                  : AppTheme.textMuted)
                              .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      ServiceJobModel.warrantyLabelOf(job.warrantyState),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: job.isUnderWarranty
                            ? AppTheme.successColor
                            : AppTheme.textSec(context),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (job.isOverdue && job.promisedAt != null)
                    Text(
                      'promised ${_dateFormat.format(job.promisedAt!)}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.dangerColor,
                      ),
                    )
                  else if (job.billableTotal > 0)
                    Text(
                      Money.withSymbol(symbol, job.billableTotal),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
