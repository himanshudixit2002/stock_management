import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../models/return_model.dart';
import '../../providers/return_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/database_service.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/searchable_picker.dart';
import '../../widgets/success_overlay.dart';

class ReturnDetailScreen extends StatelessWidget {
  final String returnId;

  const ReturnDetailScreen({super.key, required this.returnId});

  Color _statusColor(ReturnStatus status) => switch (status) {
    ReturnStatus.pending => AppTheme.warningColor,
    ReturnStatus.approved => AppTheme.primaryColor,
    ReturnStatus.processed => AppTheme.successColor,
    ReturnStatus.rejected => AppTheme.dangerColor,
  };

  @override
  Widget build(BuildContext context) {
    final ret = context.watch<ReturnProvider>().getReturnById(returnId);
    if (ret == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Return')),
        body: const Center(child: Text('Return not found')),
      );
    }

    final dateFormat = DateFormat('dd MMM yyyy');
    final statusColor = _statusColor(ret.status);
    final partyName = ret.type == ReturnType.customerReturn
        ? (ret.customerName.isNotEmpty ? ret.customerName : 'Unknown Customer')
        : (ret.vendorName.isNotEmpty ? ret.vendorName : 'Unknown Vendor');

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: AppBarTitleRow(
          icon: Icons.assignment_return_rounded,
          color: AppTheme.warningColor,
          title: 'RET-${ret.id.substring(0, 6).toUpperCase()}',
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Responsive.formMaxWidth(context),
            ),
            child: ListView(
              padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
              children: [
                GlassPanel(
                  borderRadius: 20,
                  padding: const EdgeInsets.all(20),
                  useContentVariant: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  partyName,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPri(context),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  ret.typeLabel,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textSec(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              ret.statusLabel,
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _detailRow(
                        context,
                        'Created',
                        dateFormat.format(ret.createdAt),
                      ),
                      _detailRow(context, 'Created By', ret.createdByName),
                      if (ret.relatedOrderId.isNotEmpty) ...[
                        if (ret.relatedOrderSummary.isNotEmpty)
                          _detailRow(
                            context,
                            'Related order',
                            ret.relatedOrderSummary,
                          ),
                        _detailRow(
                          context,
                          'Order document ID',
                          ret.relatedOrderId,
                        ),
                      ],
                      if (ret.notes.isNotEmpty)
                        _detailRow(context, 'Notes', ret.notes),
                      if (ret.refundAmount > 0)
                        _detailRow(
                          context,
                          'Refund Amount',
                          NumberFormat.currency(
                            symbol: AppTheme.currencySymbol,
                          ).format(ret.refundAmount),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                GlassPanel(
                  borderRadius: 20,
                  padding: const EdgeInsets.all(20),
                  useContentVariant: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Items',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPri(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...ret.items.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.inputFill(context),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: AppTheme.warningColor.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.inventory_2_rounded,
                                    color: AppTheme.warningColor,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.productName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        'Qty: ${item.quantity}'
                                        '${item.reason.isNotEmpty ? ' \u2022 ${item.reason}' : ''}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSec(context),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _buildActions(context, ret),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: AppTheme.textSec(context)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppTheme.textPri(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, ReturnModel ret) {
    final user = context.watch<AuthProvider>().currentUser;
    switch (ret.status) {
      case ReturnStatus.pending:
        return Row(
          children: [
            if (user?.hasPermission(AppPermissions.rejectReturns) ?? false)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _rejectReturn(context, ret),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.dangerColor,
                    side: const BorderSide(color: AppTheme.dangerColor),
                  ),
                ),
              ),
            if (user?.hasPermission(AppPermissions.rejectReturns) ?? false)
              const SizedBox(width: 12),
            if (user?.hasPermission(AppPermissions.approveReturns) ?? false)
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _approveReturn(context, ret),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Approve'),
                ),
              ),
          ],
        );
      case ReturnStatus.approved:
        return (user?.hasPermission(AppPermissions.processReturns) ?? false)
            ? ElevatedButton.icon(
                onPressed: () => _showProcessDialog(context, ret),
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Process Return'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.successColor,
                ),
              )
            : const SizedBox.shrink();
      case ReturnStatus.processed:
      case ReturnStatus.rejected:
        return const SizedBox.shrink();
    }
  }

  Future<void> _approveReturn(BuildContext context, ReturnModel ret) async {
    final updated = ret.copyWith(
      status: ReturnStatus.approved,
      updatedAt: DateTime.now(),
    );
    final success = await context.read<ReturnProvider>().updateReturn(updated);
    if (context.mounted && success) {
      HapticFeedback.mediumImpact();
      showSuccessOverlay(context, message: 'Return approved');
    }
  }

  Future<void> _rejectReturn(BuildContext context, ReturnModel ret) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Reject Return?',
      message: 'Are you sure you want to reject this return?',
      confirmLabel: 'Reject',
    );
    if (!confirm || !context.mounted) return;
    final updated = ret.copyWith(
      status: ReturnStatus.rejected,
      updatedAt: DateTime.now(),
    );
    final success = await context.read<ReturnProvider>().updateReturn(updated);
    if (context.mounted && success) {
      HapticFeedback.mediumImpact();
      showSuccessOverlay(context, message: 'Return rejected');
    }
  }

  Future<void> _showProcessDialog(BuildContext context, ReturnModel ret) async {
    final locations = context.read<SettingsProvider>().locations;
    if (locations.isEmpty) {
      showErrorSnackBar(context, 'Configure locations in Settings first');
      return;
    }

    String? selectedLocation;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Process Return'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                ret.type == ReturnType.customerReturn
                    ? 'Items will be added back to stock at:'
                    : 'Items will be removed from stock at:',
              ),
              if (ret.relatedOrderId.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  ret.type == ReturnType.customerReturn
                      ? 'The linked sales order will be updated with returned quantities (where the product lines match).'
                      : 'The linked purchase order will be updated (received quantities reduced where lines match).',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSec(context),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () async {
                  final result = await showSearchablePicker(
                    context: context,
                    title: 'Location',
                    selectedValue: selectedLocation,
                    items: locations
                        .map(
                          (l) => PickerItem(
                            value: l,
                            label: l,
                            icon: Icons.location_on_rounded,
                            iconColor: AppTheme.primaryColor,
                          ),
                        )
                        .toList(),
                  );
                  if (result != null) {
                    setDialogState(() => selectedLocation = result);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Location',
                    prefixIcon: Icon(Icons.location_on_rounded),
                  ),
                  child: Text(
                    selectedLocation ?? 'Tap to select',
                    style: TextStyle(
                      color: selectedLocation != null
                          ? null
                          : AppTheme.textSec(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selectedLocation != null
                  ? () => Navigator.pop(ctx, selectedLocation)
                  : null,
              child: const Text('Process'),
            ),
          ],
        ),
      ),
    );

    if (result == null || !context.mounted) return;
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;

    final success = await context.read<ReturnProvider>().processReturn(
      returnModel: ret,
      userId: user.uid,
      userName: user.name,
      location: result,
      db: DatabaseService()
        ..setCompanyId(context.read<SettingsProvider>().companyId),
    );

    if (context.mounted && success) {
      context.read<ProductProvider>().invalidateAnalytics();
      HapticFeedback.mediumImpact();
      showSuccessOverlay(context, message: 'Return processed');
    } else if (context.mounted) {
      showErrorSnackBar(
        context,
        context.read<ReturnProvider>().errorMessage ?? 'Processing failed',
      );
    }
  }
}
