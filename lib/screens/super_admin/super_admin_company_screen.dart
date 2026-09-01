import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../models/company_model.dart';
import '../../models/company_plan_model.dart';
import '../../providers/super_admin_provider.dart';
import '../../utils/date_formats.dart';
import '../../utils/dialogs.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';

/// One workspace, as the platform operator sees it: counts, plan, and the
/// lifecycle controls.
///
/// Deletion here is deliberately two-stage. This project has no backups, so a
/// soft delete (reversible, revokes access immediately) is the default action,
/// and the irreversible purge is only reachable once a company is already
/// deleted. That ordering means a purge can never be a slip.
class SuperAdminCompanyScreen extends StatelessWidget {
  const SuperAdminCompanyScreen({super.key, required this.company});

  final CompanyModel company;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SuperAdminProvider>();

    if (!provider.isSuperAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Company')),
        body: const EmptyStateWidget(
          icon: Icons.lock_rounded,
          title: 'Not available',
          subtitle: 'This area is restricted to platform administrators.',
        ),
      );
    }

    // Prefer the streamed copy so edits made here are reflected at once.
    final current = provider.companyById(company.id) ?? company;
    final stats = provider.statsFor(current.id);
    if (stats == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => provider.loadStats(current.id),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitleRow(
          icon: Icons.business_rounded,
          color: AppTheme.infoColor,
          title: current.displayName,
          subtitle: current.id,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatusCard(company: current),
            const SizedBox(height: 12),
            _StatsCard(stats: stats),
            const SizedBox(height: 12),
            _PlanCard(company: current),
            const SizedBox(height: 12),
            _DangerZone(company: current),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.company});

  final CompanyModel company;

  @override
  Widget build(BuildContext context) {
    final color = switch (company.status) {
      CompanyStatus.active => AppTheme.successColor,
      CompanyStatus.suspended => AppTheme.warningColor,
      CompanyStatus.deleted => AppTheme.dangerColor,
    };

    return GlassPanel(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.circle, size: 10, color: color),
                const SizedBox(width: 8),
                Text(
                  company.statusLabel,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
            if (company.statusNote.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(company.statusNote,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            const Divider(height: 20),
            _Row(label: 'Workspace id', value: company.id),
            if (company.permanentJoinCode.isNotEmpty)
              _Row(label: 'Join code', value: company.permanentJoinCode),
            if (company.adminUid.isNotEmpty)
              _Row(label: 'Owner uid', value: company.adminUid),
            if (company.createdAt != null)
              _Row(
                label: 'Created',
                value: AppDates.day.format(company.createdAt!),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats});

  final CompanyStats? stats;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Usage',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    )),
            const SizedBox(height: 8),
            if (stats == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Loading counts…'),
              )
            else ...[
              _Row(label: 'Users', value: '${stats!.users}'),
              _Row(label: 'Products', value: '${stats!.products}'),
              _Row(label: 'Invoices', value: '${stats!.invoices}'),
              _Row(label: 'Sales orders', value: '${stats!.salesOrders}'),
              _Row(label: 'Purchase orders', value: '${stats!.purchaseOrders}'),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.company});

  final CompanyModel company;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Plan',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    )),
            const SizedBox(height: 8),
            ...PlanCatalog.all.map((plan) {
              final selected = company.plan.planId == plan.id;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? AppTheme.primaryColor : null,
                ),
                title: Text(plan.label),
                subtitle: Text(plan.description),
                enabled: !selected,
                onTap: selected
                    ? null
                    : () async {
                        final provider = context.read<SuperAdminProvider>();
                        final ok = await provider.setPlan(
                          companyId: company.id,
                          planId: plan.id,
                        );
                        if (!context.mounted) return;
                        if (ok) {
                          showSuccessSnackBar(
                            context,
                            'Plan changed to ${plan.label}',
                          );
                        } else {
                          showErrorSnackBar(
                            context,
                            provider.errorMessage ?? 'Could not change plan',
                          );
                        }
                      },
              );
            }),
            if (PlanCatalog.all.length == 1)
              Text(
                'Only the free plan exists today. Paid tiers can be added to '
                'PlanCatalog without a data migration.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _DangerZone extends StatelessWidget {
  const _DangerZone({required this.company});

  final CompanyModel company;

  Future<void> _setStatus(
    BuildContext context,
    CompanyStatus status,
    String note,
  ) async {
    final provider = context.read<SuperAdminProvider>();
    final ok = await provider.setStatus(
      companyId: company.id,
      status: status,
      note: note,
    );
    if (!context.mounted) return;
    if (ok) {
      showSuccessSnackBar(context, 'Workspace ${status.name}');
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Update failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Lifecycle',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppTheme.dangerColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Suspending stops this workspace writing new data. Its members '
              'keep read access and see the reason.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),

            if (company.isActive)
              _ActionButton(
                icon: Icons.pause_circle_rounded,
                label: 'Suspend workspace',
                color: AppTheme.warningColor,
                onPressed: () async {
                  final confirmed = await showConfirmDialog(
                    context,
                    title: 'Suspend workspace?',
                    message:
                        '${company.displayName} will stop being able to add '
                        'or change data. This is reversible.',
                    confirmLabel: 'Suspend',
                  );
                  if (!confirmed || !context.mounted) return;
                  await _setStatus(
                    context,
                    CompanyStatus.suspended,
                    'Suspended by platform admin',
                  );
                },
              ),

            if (company.isSuspended)
              _ActionButton(
                icon: Icons.play_circle_rounded,
                label: 'Reactivate workspace',
                color: AppTheme.successColor,
                onPressed: () =>
                    _setStatus(context, CompanyStatus.active, ''),
              ),

            if (!company.isDeleted) ...[
              const SizedBox(height: 8),
              _ActionButton(
                icon: Icons.delete_outline_rounded,
                label: 'Delete workspace',
                color: AppTheme.dangerColor,
                onPressed: () async {
                  final ok = await _confirmByName(
                    context,
                    title: 'Delete workspace?',
                    message:
                        'This marks ${company.displayName} deleted and revokes '
                        'access immediately. Data is kept and this can be '
                        'undone.',
                    company: company,
                    confirmLabel: 'Delete',
                  );
                  if (!ok || !context.mounted) return;
                  await _setStatus(
                    context,
                    CompanyStatus.deleted,
                    'Deleted by platform admin',
                  );
                },
              ),
            ],

            // Purge is reachable only from an already-deleted workspace, so it
            // always takes two deliberate decisions.
            if (company.isDeleted) ...[
              const SizedBox(height: 8),
              _ActionButton(
                icon: Icons.restore_from_trash_rounded,
                label: 'Restore workspace',
                color: AppTheme.successColor,
                onPressed: () =>
                    _setStatus(context, CompanyStatus.active, ''),
              ),
              const Divider(height: 24),
              Text(
                'Permanently erase everything in this workspace. There are no '
                'backups on this project — this cannot be undone.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.dangerColor,
                ),
              ),
              const SizedBox(height: 8),
              _ActionButton(
                icon: Icons.local_fire_department_rounded,
                label: 'Purge permanently',
                color: AppTheme.dangerColor,
                onPressed: () => _purge(context),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _purge(BuildContext context) async {
    final ok = await _confirmByName(
      context,
      title: 'Purge permanently?',
      message:
          'Every product, invoice, order and ledger entry in '
          '${company.displayName} will be erased. There are no backups. This '
          'cannot be undone.',
      company: company,
      confirmLabel: 'Purge forever',
    );
    if (!ok || !context.mounted) return;

    final provider = context.read<SuperAdminProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Purging…')),
          ],
        ),
      ),
    );

    final purged = await provider.purgeCompany(companyId: company.id);

    if (navigator.canPop()) navigator.pop(); // close the progress dialog
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          purged
              ? 'Workspace purged'
              : provider.errorMessage ?? 'Purge failed',
        ),
      ),
    );
    if (purged && navigator.canPop()) navigator.pop(); // leave the detail page
  }

  /// Requires the operator to type the workspace name. Used for both delete
  /// and purge so a destructive action can never be a stray tap.
  Future<bool> _confirmByName(
    BuildContext context, {
    required String title,
    required String message,
    required CompanyModel company,
    required String confirmLabel,
  }) async {
    final controller = TextEditingController();
    final expected = company.displayName.trim();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final matches = controller.text.trim() == expected;
          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                const SizedBox(height: 16),
                Text('Type "$expected" to confirm:',
                    style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(height: 6),
                TextField(
                  controller: controller,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.dangerColor,
                ),
                onPressed: matches ? () => Navigator.pop(ctx, true) : null,
                child: Text(confirmLabel),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    return result == true;
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: color),
        label: Text(label, style: TextStyle(color: color)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color.withValues(alpha: 0.5)),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label,
                style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
