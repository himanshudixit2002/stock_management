import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/invoice_model.dart';
import '../../models/sales_order_model.dart';
import '../../models/user_model.dart';
import '../../providers/billing_provider.dart';
import '../../providers/sales_order_provider.dart';
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

class SalesOrderDetailScreen extends StatelessWidget {
  final String orderId;

  const SalesOrderDetailScreen({super.key, required this.orderId});

  Color _statusColor(BuildContext context, SOStatus status) => switch (status) {
    SOStatus.draft => Theme.of(context).colorScheme.outline,
    SOStatus.confirmed => AppTheme.primaryColor,
    SOStatus.dispatched => AppTheme.indigoColor,
    SOStatus.delivered => AppTheme.successColor,
    SOStatus.cancelled => AppTheme.dangerColor,
  };

  @override
  Widget build(BuildContext context) {
    final order = context.watch<SalesOrderProvider>().getOrderById(orderId);
    final user = context.watch<AuthProvider>().currentUser;
    if (order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sales Order')),
        body: const Center(child: Text('Order not found')),
      );
    }

    final dateFormat = DateFormat('dd MMM yyyy');
    final currencyFormat = NumberFormat.currency(symbol: AppTheme.currencySymbol, decimalDigits: 2);
    final statusColor = _statusColor(context, order.status);
    final linkedInvoice = order.invoiceId.isNotEmpty
        ? context.watch<BillingProvider>().getInvoiceById(order.invoiceId)
        : null;

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: AppBarTitleRow(
          icon: Icons.receipt_long_rounded,
          color: AppTheme.indigoColor,
          title: 'SO-${order.id.substring(0, 6).toUpperCase()}',
        ),
        actions: [
          if (order.invoiceId.isEmpty)
            IconButton(
              icon: const Icon(Icons.receipt_rounded),
              tooltip: 'Create Invoice',
              onPressed: () => Navigator.pushNamed(
                context,
                AppRoutes.createInvoice,
                arguments: <String, dynamic>{
                  'salesOrderId': order.id,
                  'type': InvoiceType.sales,
                },
              ),
            ),
          if (order.status == SOStatus.draft &&
              (user?.hasPermission(AppPermissions.deleteSalesOrders) ?? false))
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.dangerColor),
              onPressed: () => _confirmDelete(context, order),
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: Responsive.formMaxWidth(context)),
            child: ListView(
              padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
              children: [
                Builder(builder: (context) {
                  final section1 = GlassPanel(
                    borderRadius: 20,
                    padding: const EdgeInsets.all(20),
                    useContentVariant: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                order.customerName.isNotEmpty
                                    ? order.customerName : 'Walk-in Customer',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                                    color: AppTheme.textPri(context)),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(order.statusLabel,
                                  style: TextStyle(color: statusColor,
                                      fontWeight: FontWeight.w600, fontSize: 13)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _detailRow(context, 'Created', dateFormat.format(order.createdAt)),
                        _detailRow(context, 'Created By', order.createdByName),
                        if (order.notes.isNotEmpty) _detailRow(context, 'Notes', order.notes),
                        if (order.invoiceId.isNotEmpty) ...[
                          const Divider(height: 20),
                          InkWell(
                            onTap: () => Navigator.pushNamed(
                              context, AppRoutes.invoiceDetail,
                              arguments: order.invoiceId,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppTheme.successColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.receipt_rounded, size: 16, color: AppTheme.successColor),
                                  const SizedBox(width: 8),
                                  Text(
                                    linkedInvoice != null &&
                                            linkedInvoice.invoiceNumber.isNotEmpty
                                        ? 'Invoice: ${linkedInvoice.invoiceNumber}'
                                        : 'Invoice linked',
                                    style: TextStyle(
                                      color: AppTheme.successColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.open_in_new_rounded, size: 14, color: AppTheme.successColor),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                  final section2 = GlassPanel(
                    borderRadius: 20,
                    padding: const EdgeInsets.all(20),
                    useContentVariant: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Items',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                                color: AppTheme.textPri(context))),
                        const SizedBox(height: 12),
                        ...order.items.map((item) => Padding(
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
                                  width: 36, height: 36,
                                  decoration: BoxDecoration(
                                    color: AppTheme.indigoColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.inventory_2_rounded,
                                      color: AppTheme.indigoColor, size: 18),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item.productName,
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                      Text(
                                        'Qty: ${item.quantity} \u2022 Dispatched: ${item.dispatchedQuantity}'
                                        '${item.returnedQuantity > 0 ? ' \u2022 Returned: ${item.returnedQuantity}' : ''}',
                                        style: TextStyle(fontSize: 12, color: AppTheme.textSec(context)),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  currencyFormat.format(item.quantity * item.unitPrice),
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        )),
                        const Divider(height: 24),
                        Row(
                          children: [
                            Text('Total', style: TextStyle(fontSize: 16,
                                fontWeight: FontWeight.w700, color: AppTheme.textPri(context))),
                            const Spacer(),
                            Text(currencyFormat.format(order.totalAmount),
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                                    color: AppTheme.primaryColor)),
                          ],
                        ),
                      ],
                    ),
                  );
                  if (Responsive.isDesktop(context)) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: section1),
                        const SizedBox(width: 16),
                        Expanded(child: section2),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      section1,
                      const SizedBox(height: 16),
                      section2,
                    ],
                  );
                }),
                const SizedBox(height: 24),
                _buildActions(context, order, user),
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
          SizedBox(width: 120,
              child: Text(label, style: TextStyle(fontSize: 13,
                  color: AppTheme.textSec(context)))),
          Expanded(
              child: Text(value, style: TextStyle(fontSize: 14,
                  fontWeight: FontWeight.w500, color: AppTheme.textPri(context)))),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, SalesOrderModel order, UserModel? user) {
    final canCancel = user?.hasPermission(AppPermissions.cancelSalesOrders) ?? false;

    Widget? primaryAction;
    switch (order.status) {
      case SOStatus.draft:
        if (user?.hasPermission(AppPermissions.confirmSalesOrders) ?? false) {
          primaryAction = ElevatedButton.icon(
            onPressed: () => _confirmOrder(context, order),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Confirm Order'),
          );
        }
      case SOStatus.confirmed:
        if (user?.hasPermission(AppPermissions.dispatchSalesOrders) ?? false) {
          primaryAction = ElevatedButton.icon(
            onPressed: () => _showDispatchDialog(context, order),
            icon: const Icon(Icons.local_shipping_rounded),
            label: const Text('Dispatch'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.indigoColor),
          );
        }
      case SOStatus.dispatched:
        if (user?.hasPermission(AppPermissions.deliverSalesOrders) ?? false) {
          primaryAction = ElevatedButton.icon(
            onPressed: () => _deliverOrder(context, order),
            icon: const Icon(Icons.check_circle_rounded),
            label: const Text('Mark Delivered'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successColor),
          );
        }
      case SOStatus.delivered:
      case SOStatus.cancelled:
        break;
    }

    final showCancel = canCancel &&
        order.status != SOStatus.delivered &&
        order.status != SOStatus.cancelled;

    if (primaryAction == null && !showCancel) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (primaryAction != null) primaryAction,
        if (primaryAction != null && showCancel) const SizedBox(height: 12),
        if (showCancel)
          OutlinedButton.icon(
            onPressed: () => _confirmCancel(context, order),
            icon: const Icon(Icons.cancel_rounded, color: AppTheme.dangerColor),
            label: const Text('Cancel Order'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.dangerColor,
              side: const BorderSide(color: AppTheme.dangerColor),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmOrder(BuildContext context, SalesOrderModel order) async {
    final updated = order.copyWith(status: SOStatus.confirmed, updatedAt: DateTime.now());
    final success = await context.read<SalesOrderProvider>().updateOrder(updated);
    if (context.mounted && success) {
      HapticFeedback.mediumImpact();
      showSuccessOverlay(context, message: 'Order confirmed');
    }
  }

  Future<void> _showDispatchDialog(BuildContext context, SalesOrderModel order) async {
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
          title: const Text('Dispatch Items'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Select the location to dispatch items from:'),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () async {
                  final result = await showSearchablePicker(
                    context: context,
                    title: 'Location',
                    selectedValue: selectedLocation,
                    items: locations.map((l) => PickerItem(
                      value: l,
                      label: l,
                      icon: Icons.location_on_rounded,
                      iconColor: AppTheme.primaryColor,
                    )).toList(),
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
                      color: selectedLocation != null ? null : AppTheme.textSec(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: selectedLocation != null ? () => Navigator.pop(ctx, selectedLocation) : null,
              child: const Text('Dispatch'),
            ),
          ],
        ),
      ),
    );

    if (result == null || !context.mounted) return;
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;

    final success = await context.read<SalesOrderProvider>().dispatchOrder(
      order: order,
      userId: user.uid,
      userName: user.name,
      location: result,
      db: DatabaseService()..setCompanyId(context.read<SettingsProvider>().companyId),
    );

    if (context.mounted && success) {
      context.read<ProductProvider>().invalidateAnalytics();
      HapticFeedback.mediumImpact();
      showSuccessOverlay(context, message: 'Order dispatched');
    } else if (context.mounted) {
      showErrorSnackBar(context,
          context.read<SalesOrderProvider>().errorMessage ?? 'Dispatch failed');
    }
  }

  Future<void> _deliverOrder(BuildContext context, SalesOrderModel order) async {
    final updated = order.copyWith(status: SOStatus.delivered, updatedAt: DateTime.now());
    final success = await context.read<SalesOrderProvider>().updateOrder(updated);
    if (context.mounted && success) {
      HapticFeedback.mediumImpact();
      showSuccessOverlay(context, message: 'Order delivered');
    }
  }

  Future<void> _confirmCancel(BuildContext context, SalesOrderModel order) async {
    final wasDispatched = order.status == SOStatus.dispatched;
    final message = wasDispatched
        ? 'This will reverse the dispatched stock and cancel the order. This cannot be undone.'
        : 'This will cancel the order. This cannot be undone.';

    final confirm = await showConfirmDialog(
      context,
      title: 'Cancel Order?',
      message: message,
      confirmLabel: 'Yes, Cancel',
    );
    if (!confirm || !context.mounted) return;

    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;

    final locations = context.read<SettingsProvider>().locations;
    final defaultLoc = locations.isNotEmpty ? locations.first : 'Main';

    final success = await context.read<SalesOrderProvider>().cancelOrder(
      order: order,
      userId: user.uid,
      userName: user.name,
      defaultLocation: defaultLoc,
    );

    if (context.mounted && success) {
      context.read<ProductProvider>().invalidateAnalytics();
      HapticFeedback.mediumImpact();
      showSuccessOverlay(context, message: 'Order cancelled');
    } else if (context.mounted) {
      showErrorSnackBar(
        context,
        context.read<SalesOrderProvider>().errorMessage ?? 'Cancellation failed',
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, SalesOrderModel order) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Delete Order?',
      message: 'This action cannot be undone.',
    );
    if (!confirm || !context.mounted) return;
    final success = await context.read<SalesOrderProvider>().deleteOrder(order.id);
    if (context.mounted && success) Navigator.pop(context);
  }
}
