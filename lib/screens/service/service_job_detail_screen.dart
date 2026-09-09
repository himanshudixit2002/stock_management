import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../models/service_job_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/service_job_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/currency.dart';
import '../../utils/dialogs.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/not_found_state.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/product_picker.dart';
import 'service_job_list_screen.dart' show ServiceJobCard;

/// One repair: diagnose it, fit parts, charge for it, hand it back.
class ServiceJobDetailScreen extends StatefulWidget {
  const ServiceJobDetailScreen({super.key, required this.jobId});

  final String jobId;

  @override
  State<ServiceJobDetailScreen> createState() => _ServiceJobDetailScreenState();
}

class _ServiceJobDetailScreenState extends State<ServiceJobDetailScreen> {
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

  Future<void> _addPart(ServiceJobModel job) async {
    final products = context.read<ProductProvider>().analyticsProducts;
    final picked = await showProductPicker(
      context: context,
      products: products,
      title: 'Which part?',
    );
    if (picked == null || !mounted) return;

    final quantityController = TextEditingController(text: '1');
    final priceController = TextEditingController(
      text: job.isUnderWarranty ? '0' : picked.sellingPrice.toStringAsFixed(2),
    );
    var chargeable = !job.isUnderWarranty;

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
              Text(
                picked.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: quantityController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(labelText: 'Qty'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: priceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Charged per unit',
                      ),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: chargeable,
                onChanged: (value) => setSheet(() => chargeable = value),
                title: const Text('Charge the customer'),
                subtitle: const Text(
                  'A warranty part still leaves stock, but nobody pays for it',
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetCtx, true),
                  child: const Text('Add part'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final quantity = int.tryParse(quantityController.text.trim()) ?? 0;
    final price = double.tryParse(priceController.text.trim()) ?? 0;
    quantityController.dispose();
    priceController.dispose();
    if (confirmed != true || !mounted || quantity <= 0) return;

    final provider = context.read<ServiceJobProvider>();
    final ok = await provider.updateJob(
      job.copyWith(
        parts: [
          ...job.parts,
          ServicePart(
            productId: picked.id,
            productName: picked.name,
            unit: picked.baseUnit,
            quantity: quantity,
            unitPrice: price,
            chargeable: chargeable,
          ),
        ],
        updatedAt: DateTime.now(),
      ),
    );
    if (!mounted) return;
    if (ok) {
      showSuccessSnackBar(context, 'Part added. Issue it to take it out of stock.');
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Could not add.');
    }
  }

  Future<void> _addCharge(ServiceJobModel job) async {
    final labelController = TextEditingController(text: 'Labour');
    final amountController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a charge'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelController,
              decoration: const InputDecoration(labelText: 'What for'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Amount'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    final label = labelController.text.trim();
    final amount = double.tryParse(amountController.text.trim()) ?? 0;
    labelController.dispose();
    amountController.dispose();
    if (confirmed != true || !mounted || amount <= 0) return;

    final provider = context.read<ServiceJobProvider>();
    final ok = await provider.updateJob(
      job.copyWith(
        charges: [
          ...job.charges,
          ServiceCharge(label: label.isEmpty ? 'Charge' : label, amount: amount),
        ],
        updatedAt: DateTime.now(),
      ),
    );
    if (!mounted) return;
    if (ok) {
      showSuccessSnackBar(context, 'Charge added.');
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Could not add.');
    }
  }

  Future<void> _issueParts(ServiceJobModel job) async {
    final locations = context.read<SettingsProvider>().locations;
    var location = locations.isNotEmpty ? locations.first : 'Main';

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Issue parts from stock',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '${job.unissuedParts.length} part line(s) will come out of '
                'stock for good.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textSec(sheetCtx),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: locations.contains(location) ? location : null,
                decoration: const InputDecoration(labelText: 'Take from'),
                items: [
                  for (final l in locations)
                    DropdownMenuItem(value: l, child: Text(l)),
                ],
                onChanged: (value) {
                  if (value != null) setSheet(() => location = value);
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetCtx, true),
                  child: const Text('Issue parts'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final user = context.read<AuthProvider>().currentUser;
    final provider = context.read<ServiceJobProvider>();
    final units = await provider.issueParts(
      job: job,
      location: location,
      userId: user?.uid ?? '',
      userName: user?.name ?? '',
    );
    if (!mounted) return;
    if (units == null) {
      showErrorSnackBar(
        context,
        provider.errorMessage ?? 'Could not issue the parts.',
      );
      return;
    }
    context.read<ProductProvider>().invalidateAnalytics();
    showSuccessSnackBar(context, 'Issued $units part unit(s) from $location.');
  }

  Future<void> _setStatus(
    ServiceJobModel job,
    ServiceJobStatus status, {
    bool askResolution = false,
  }) async {
    var resolution = '';
    if (askResolution) {
      final controller = TextEditingController(text: job.resolution);
      final entered = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('What was done?'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Replaced the board, cleaned the heads…',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Resolve'),
            ),
          ],
        ),
      );
      resolution = (entered ?? '').trim();
      controller.dispose();
      if (entered == null || !mounted) return;
    }

    final user = context.read<AuthProvider>().currentUser;
    final provider = context.read<ServiceJobProvider>();
    final ok = await provider.setStatus(
      job: job,
      status: status,
      userId: user?.uid ?? '',
      userName: user?.name ?? '',
      resolution: resolution,
    );
    if (!mounted) return;
    if (ok) {
      showSuccessSnackBar(
        context,
        'Job ${ServiceJobModel.statusLabelOf(status).toLowerCase()}.',
      );
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Could not update.');
    }
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
    final job = provider.byId(widget.jobId);
    final symbol = Money.symbolOf(context);

    if (job == null) {
      return AppScreenScaffold(
        icon: Icons.build_circle_rounded,
        title: 'Service job',
        iconColor: AppTheme.infoColor,
        isLoading: provider.isLoading,
        body: const NotFoundState(
          icon: Icons.build_circle_rounded,
          title: 'Job not found',
          message: 'It may have been deleted since this link was opened.',
        ),
      );
    }

    final user = context.watch<AuthProvider>().currentUser;
    final canManage =
        user?.hasPermission(AppPermissions.manageServiceJobs) ?? false;
    final canClose =
        user?.hasPermission(AppPermissions.closeServiceJobs) ?? false;
    final busy = provider.isBusy;

    return AppScreenScaffold(
      icon: Icons.build_circle_rounded,
      title: job.jobNumber.isEmpty ? 'Service job' : job.jobNumber,
      subtitle: job.customerName.isEmpty ? job.productName : job.customerName,
      iconColor: ServiceJobCard.statusColor(job.status),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          GlassPanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        job.statusLabel,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: ServiceJobCard.statusColor(job.status),
                        ),
                      ),
                    ),
                    Text(
                      Money.withSymbol(symbol, job.billableTotal),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _Row(
                  label: 'Warranty',
                  value: ServiceJobModel.warrantyLabelOf(job.warrantyState),
                  warn: !job.isUnderWarranty,
                ),
                if (job.serialNumber.isNotEmpty)
                  _Row(label: 'Serial', value: job.serialNumber),
                if (job.productName.isNotEmpty)
                  _Row(label: 'Product', value: job.productName),
                if (job.technicianName.isNotEmpty)
                  _Row(label: 'Technician', value: job.technicianName),
                _Row(label: 'Age', value: '${job.ageDays} days'),
                if (job.promisedAt != null)
                  _Row(
                    label: 'Promised',
                    value:
                        '${job.promisedAt!.day}/${job.promisedAt!.month}/${job.promisedAt!.year}',
                    warn: job.isOverdue,
                  ),
                if (job.faultDescription.isNotEmpty)
                  _Row(label: 'Fault', value: job.faultDescription),
                if (job.resolution.isNotEmpty)
                  _Row(label: 'Resolution', value: job.resolution),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GlassSectionCard(
            title: 'Parts',
            icon: Icons.settings_rounded,
            trailing: canManage && job.canEdit
                ? TextButton.icon(
                    onPressed: busy ? null : () => _addPart(job),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Add'),
                  )
                : null,
            child: Column(
              children: [
                if (job.parts.isEmpty)
                  Text(
                    'No parts fitted.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.textSec(context),
                    ),
                  )
                else
                  for (final part in job.parts)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Icon(
                            part.issued
                                ? Icons.check_circle_rounded
                                : Icons.pending_rounded,
                            size: 16,
                            color: part.issued
                                ? AppTheme.successColor
                                : AppTheme.warningColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  part.productName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                                Text(
                                  '${part.quantity} ${part.unit}'
                                  '${part.chargeable ? '' : ' · under warranty'}'
                                  '${part.issued ? ' · issued' : ' · not yet issued'}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textSec(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            Money.withSymbol(symbol, part.lineTotal),
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GlassSectionCard(
            title: 'Charges',
            icon: Icons.receipt_long_rounded,
            trailing: canManage && job.canEdit
                ? TextButton.icon(
                    onPressed: busy ? null : () => _addCharge(job),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Add'),
                  )
                : null,
            child: Column(
              children: [
                if (job.charges.isEmpty)
                  Text(
                    'No labour or other charges.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.textSec(context),
                    ),
                  )
                else
                  for (final charge in job.charges)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(child: Text(charge.label)),
                          Text(
                            Money.withSymbol(symbol, charge.amount),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (canManage && job.canIssueParts)
            _ActionButton(
              icon: Icons.outbox_rounded,
              label: 'Issue ${job.unissuedParts.length} part line(s) from stock',
              color: AppTheme.warningColor,
              onPressed: busy ? null : () => _issueParts(job),
            ),
          if (canManage &&
              job.isOpen &&
              job.status == ServiceJobStatus.received)
            _ActionButton(
              icon: Icons.search_rounded,
              label: 'Mark diagnosed',
              onPressed: busy
                  ? null
                  : () => _setStatus(job, ServiceJobStatus.diagnosed),
            ),
          if (canManage &&
              job.isOpen &&
              job.status != ServiceJobStatus.awaitingParts &&
              job.status != ServiceJobStatus.resolved)
            _ActionButton(
              icon: Icons.hourglass_top_rounded,
              label: 'Waiting on parts',
              onPressed: busy
                  ? null
                  : () => _setStatus(job, ServiceJobStatus.awaitingParts),
            ),
          if (canManage && job.canResolve)
            _ActionButton(
              icon: Icons.done_all_rounded,
              label: 'Resolve',
              color: AppTheme.successColor,
              onPressed: busy
                  ? null
                  : () => _setStatus(
                      job,
                      ServiceJobStatus.resolved,
                      askResolution: true,
                    ),
            ),
          if (canClose && job.canClose)
            _ActionButton(
              icon: Icons.task_alt_rounded,
              label: 'Close and hand back',
              color: AppTheme.violetColor,
              onPressed: busy
                  ? null
                  : () => _setStatus(job, ServiceJobStatus.closed),
            ),
          if (canManage && job.canCancel)
            _ActionButton(
              icon: Icons.cancel_rounded,
              label: 'Cancel job',
              color: AppTheme.dangerColor,
              onPressed: busy
                  ? null
                  : () => _setStatus(job, ServiceJobStatus.cancelled),
            ),
          if (job.isOpen && job.hasUnissuedParts)
            Text(
              'Parts have to be issued before a job can be resolved — that is '
              'what keeps the stock on the shelf and the stock in the app the '
              'same number.',
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

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.warn = false});

  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.textSec(context),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: warn ? AppTheme.warningColor : null,
              ),
            ),
          ),
        ],
      ),
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
