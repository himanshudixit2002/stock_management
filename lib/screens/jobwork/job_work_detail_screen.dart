import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/app_navigation.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/job_work_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/job_work_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/currency.dart';
import '../../utils/dialogs.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/not_found_state.dart';
import '../../widgets/permission_gate.dart';
import 'job_work_list_screen.dart' show JobWorkCard;

/// One job work order: issue it, receive it, close it.
class JobWorkDetailScreen extends StatefulWidget {
  const JobWorkDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<JobWorkDetailScreen> createState() => _JobWorkDetailScreenState();
}

class _JobWorkDetailScreenState extends State<JobWorkDetailScreen> {
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

  Future<void> _issue(JobWorkOrderModel order) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Send the components out?',
      message:
          '${order.issueQuantities.values.fold(0, (a, b) => a + b)} unit(s) '
          'move from ${order.issueLocation} into the "At vendor" bucket. They '
          'stay on your books and in your valuation the whole time.',
      confirmLabel: 'Issue',
      icon: Icons.outbox_rounded,
      iconColor: AppTheme.violetColor,
    );
    if (!confirmed || !mounted) return;

    final user = context.read<AuthProvider>().currentUser;
    final provider = context.read<JobWorkProvider>();
    final ok = await provider.issue(
      order: order,
      userId: user?.uid ?? '',
      userName: user?.name ?? '',
    );
    if (!mounted) return;
    if (ok) {
      context.read<ProductProvider>().invalidateAnalytics();
      HapticFeedback.mediumImpact();
      showSuccessSnackBar(context, 'Components issued to ${order.vendorName}.');
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Could not issue.');
    }
  }

  Future<void> _receive(JobWorkOrderModel order) async {
    final controller = TextEditingController(text: '${order.remainingOutput}');
    var closeShort = false;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
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
                'Receive finished goods',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Receiving consumes the components the vendor used, in '
                'proportion to what came back.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textSec(sheetCtx),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Units received',
                  helperText: '${order.remainingOutput} still expected',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: closeShort,
                onChanged: (value) => setSheet(() => closeShort = value),
                title: const Text('Close the job with this receipt'),
                subtitle: const Text(
                  'Use when the rest will never arrive',
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetCtx, true),
                  child: const Text('Receive'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final units = int.tryParse(controller.text.trim()) ?? 0;
    controller.dispose();
    if (confirmed != true || !mounted || units <= 0) return;

    final user = context.read<AuthProvider>().currentUser;
    final provider = context.read<JobWorkProvider>();
    final unitCost = await provider.receive(
      order: order,
      units: units,
      userId: user?.uid ?? '',
      userName: user?.name ?? '',
      closeShort: closeShort,
    );
    if (!mounted) return;
    if (unitCost == null) {
      showErrorSnackBar(context, provider.errorMessage ?? 'Could not receive.');
      return;
    }
    context.read<ProductProvider>().invalidateAnalytics();
    HapticFeedback.mediumImpact();
    showSuccessSnackBar(
      context,
      'Received $units unit(s) at '
      '${Money.of(context, unitCost, listen: false)} each.',
    );
  }

  Future<void> _close(JobWorkOrderModel order) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Close this job?',
      message: order.componentUnitsAtVendor > 0
          ? '${order.componentUnitsAtVendor} component unit(s) still with the '
                'vendor are returned to ${order.issueLocation}, so nothing is '
                'left stranded in the vendor bucket.'
          : 'The job is closed with what has already come back.',
      confirmLabel: 'Close job',
      icon: Icons.inventory_rounded,
      iconColor: AppTheme.warningColor,
    );
    if (!confirmed || !mounted) return;

    final user = context.read<AuthProvider>().currentUser;
    final provider = context.read<JobWorkProvider>();
    final ok = await provider.close(
      order: order,
      userId: user?.uid ?? '',
      userName: user?.name ?? '',
    );
    if (!mounted) return;
    if (ok) {
      context.read<ProductProvider>().invalidateAnalytics();
      showSuccessSnackBar(context, 'Job closed.');
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Could not close.');
    }
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
    final order = provider.byId(widget.orderId);
    final symbol = Money.symbolOf(context);

    if (order == null) {
      return AppScreenScaffold(
        icon: Icons.handyman_rounded,
        title: 'Job work',
        iconColor: AppTheme.violetColor,
        isLoading: provider.isLoading,
        body: const NotFoundState(
          icon: Icons.handyman_rounded,
          title: 'Job not found',
          message: 'It may have been deleted since this link was opened.',
        ),
      );
    }

    final user = context.watch<AuthProvider>().currentUser;
    final canManage = user?.hasPermission(AppPermissions.manageJobWork) ?? false;
    final canIssue = user?.hasPermission(AppPermissions.issueJobWork) ?? false;
    final canReceive =
        user?.hasPermission(AppPermissions.receiveJobWork) ?? false;
    final busy = provider.isBusy;

    return AppScreenScaffold(
      icon: Icons.handyman_rounded,
      title: order.referenceNumber.isEmpty
          ? order.outputProductName
          : order.referenceNumber,
      subtitle: order.vendorName,
      iconColor: JobWorkCard.statusColor(order.status),
      actions: [
        if (canManage && order.canEdit)
          IconButton(
            tooltip: 'Edit',
            onPressed: () =>
                context.pushAppRoute(AppRoutes.createJobWork, extra: order),
            icon: const Icon(Icons.edit_rounded),
          ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          GlassPanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.statusLabel,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: JobWorkCard.statusColor(order.status),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _Stat(
                        label: 'Expected',
                        value: '${order.outputQuantity}',
                      ),
                    ),
                    Expanded(
                      child: _Stat(
                        label: 'Received',
                        value: '${order.receivedQuantity}',
                      ),
                    ),
                    Expanded(
                      child: _Stat(
                        label: 'At vendor',
                        value: '${order.componentUnitsAtVendor}',
                        caption: 'component units',
                      ),
                    ),
                    Expanded(
                      child: _Stat(
                        label: 'Charge',
                        value: Money.compactWithSymbol(
                          symbol,
                          order.chargesPlanned,
                        ),
                        caption:
                            '${Money.withSymbol(symbol, order.chargePerOutputUnit)}/unit',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '${order.issueLocation} → At vendor → ${order.receiveLocation}'
                  '${order.expectedAt == null ? '' : ' · due ${order.expectedAt!.day}/${order.expectedAt!.month}/${order.expectedAt!.year}'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: order.isOverdue
                        ? AppTheme.dangerColor
                        : AppTheme.textSec(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GlassSectionCard(
            title: 'Components',
            icon: Icons.outbox_rounded,
            child: Column(
              children: [
                for (final component in order.components)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                component.productName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${component.quantityPerOutput} per unit · '
                                'issued ${component.issuedQuantity} · '
                                'used ${component.consumedQuantity}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: AppTheme.textSec(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (component.atVendorQuantity > 0)
                          Text(
                            '${component.atVendorQuantity} out',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.violetColor,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (order.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            GlassSectionCard(
              title: 'Notes',
              icon: Icons.notes_rounded,
              child: Text(order.notes),
            ),
          ],
          const SizedBox(height: 16),
          if (canIssue && order.canIssue)
            _ActionButton(
              icon: Icons.outbox_rounded,
              label: 'Issue components to ${order.vendorName}',
              color: AppTheme.violetColor,
              onPressed: busy ? null : () => _issue(order),
            ),
          if (canReceive && order.canReceive)
            _ActionButton(
              icon: Icons.move_to_inbox_rounded,
              label: 'Receive finished goods',
              color: AppTheme.successColor,
              onPressed: busy ? null : () => _receive(order),
            ),
          if (canManage && order.canClose)
            _ActionButton(
              icon: Icons.assignment_turned_in_rounded,
              label: order.componentUnitsAtVendor > 0
                  ? 'Close and take the rest back'
                  : 'Close job',
              color: AppTheme.warningColor,
              onPressed: busy ? null : () => _close(order),
            ),
          if (order.canIssue && !canIssue)
            Text(
              'This job is ready to go out. Issuing it needs the Issue Job '
              'Work permission.',
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
  const _Stat({required this.label, required this.value, this.caption});

  final String label;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11.5, color: AppTheme.textSec(context)),
        ),
        if (caption != null)
          Text(
            caption!,
            style: TextStyle(fontSize: 10, color: AppTheme.textSec(context)),
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
