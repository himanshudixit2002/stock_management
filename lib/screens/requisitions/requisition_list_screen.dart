import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/app_navigation.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/requisition_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/requisition_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/currency.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/provider_error_banner.dart';

/// Requests to buy, and the approval queue over them.
class RequisitionListScreen extends StatefulWidget {
  const RequisitionListScreen({super.key});

  @override
  State<RequisitionListScreen> createState() => _RequisitionListScreenState();
}

class _RequisitionListScreenState extends State<RequisitionListScreen> {
  /// True while the approval queue is showing rather than the whole list. The
  /// queue is the default view for anyone who can approve, because that is the
  /// job this screen exists to unblock.
  bool _queueOnly = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final companyId = context.read<SettingsProvider>().companyId;
      if (companyId.isNotEmpty) {
        context.read<RequisitionProvider>().initialize(companyId: companyId);
      }
      final canApprove =
          context.read<AuthProvider>().currentUser?.hasPermission(
                AppPermissions.approveRequisitions,
              ) ??
          false;
      if (canApprove) setState(() => _queueOnly = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewRequisitions,
      featureName: 'Requisitions',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final provider = context.watch<RequisitionProvider>();
    final canCreate = context.select<AuthProvider, bool>(
      (a) =>
          a.currentUser?.hasPermission(AppPermissions.createRequisitions) ??
          false,
    );
    final pending = provider.pendingApproval;
    final rows = _queueOnly ? pending : provider.requisitions;

    return AppScreenScaffold(
      icon: Icons.assignment_rounded,
      title: 'Requisitions',
      subtitle: pending.isEmpty
          ? 'Nothing awaiting approval'
          : '${pending.length} awaiting approval'
                '${provider.staleCount > 0 ? ' · ${provider.staleCount} overdue' : ''}',
      iconColor: AppTheme.indigoColor,
      isLoading: provider.isLoading && provider.requisitions.isEmpty,
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () =>
                  context.pushAppRoute(AppRoutes.createRequisition),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Request'),
            )
          : null,
      isEmpty: provider.requisitions.isEmpty && !provider.isLoading,
      emptyState: EmptyStateWidget(
        icon: Icons.assignment_rounded,
        title: 'No requisitions yet',
        subtitle:
            'Ask for stock without raising a purchase order. An approver turns '
            'the request into an order once it is agreed.',
        buttonText: canCreate ? 'Raise a request' : null,
        onButtonPressed: canCreate
            ? () => context.pushAppRoute(AppRoutes.createRequisition)
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
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: true,
                  label: Text('Queue (${pending.length})'),
                  icon: const Icon(Icons.pending_actions_rounded, size: 16),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('All (${provider.requisitions.length})'),
                  icon: const Icon(Icons.list_rounded, size: 16),
                ),
              ],
              selected: {_queueOnly},
              onSelectionChanged: (value) =>
                  setState(() => _queueOnly = value.first),
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _queueOnly
                            ? 'Nothing is waiting on a decision.'
                            : 'No requisitions match.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textSec(context)),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: rows.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: RequisitionCard(
                        requisition: rows[i],
                        index: i,
                        onTap: () => context.pushAppRoute(
                          AppRoutes.requisitionDetail,
                          extra: rows[i],
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

/// One requisition, summarised.
class RequisitionCard extends StatelessWidget {
  const RequisitionCard({
    super.key,
    required this.requisition,
    required this.index,
    this.onTap,
  });

  final RequisitionModel requisition;
  final int index;
  final VoidCallback? onTap;

  static final DateFormat _dateFormat = DateFormat('dd MMM');

  static Color statusColor(RequisitionStatus status) => switch (status) {
    RequisitionStatus.draft => AppTheme.textMuted,
    RequisitionStatus.submitted => AppTheme.warningColor,
    RequisitionStatus.approved => AppTheme.successColor,
    RequisitionStatus.rejected => AppTheme.dangerColor,
    RequisitionStatus.converted => AppTheme.indigoColor,
    RequisitionStatus.cancelled => AppTheme.textMuted,
  };

  static Color urgencyColor(RequisitionUrgency urgency) => switch (urgency) {
    RequisitionUrgency.low => AppTheme.textMuted,
    RequisitionUrgency.normal => AppTheme.infoColor,
    RequisitionUrgency.high => AppTheme.warningColor,
    RequisitionUrgency.critical => AppTheme.dangerColor,
  };

  @override
  Widget build(BuildContext context) {
    final symbol = Money.symbolOf(context);
    final color = statusColor(requisition.status);
    final stale = requisition.isStale();

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
                      requisition.title.isEmpty
                          ? 'Untitled request'
                          : requisition.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (requisition.urgency != RequisitionUrgency.normal)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        Icons.flag_rounded,
                        size: 14,
                        color: urgencyColor(requisition.urgency),
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
                      requisition.statusLabel,
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
                  if (requisition.referenceNumber.isNotEmpty)
                    requisition.referenceNumber,
                  '${requisition.lines.length} line'
                      '${requisition.lines.length == 1 ? '' : 's'}',
                  '${requisition.totalQuantity} units',
                  if (requisition.estimatedTotal > 0)
                    '~${Money.withSymbol(symbol, requisition.estimatedTotal)}',
                  if (requisition.requestedByName.isNotEmpty)
                    requisition.requestedByName,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textSec(context),
                ),
              ),
              if (stale || requisition.neededBy != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      stale
                          ? Icons.hourglass_bottom_rounded
                          : Icons.event_rounded,
                      size: 14,
                      color: stale
                          ? AppTheme.dangerColor
                          : AppTheme.textSec(context),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      [
                        if (stale) 'Waiting since submission',
                        if (requisition.neededBy != null)
                          'needed by ${_dateFormat.format(requisition.neededBy!)}',
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: stale
                            ? AppTheme.dangerColor
                            : AppTheme.textSec(context),
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
