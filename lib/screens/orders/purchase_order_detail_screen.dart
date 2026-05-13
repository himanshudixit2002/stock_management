import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../models/purchase_order_model.dart';
import '../../models/user_model.dart';
import '../../providers/billing_provider.dart';
import '../../providers/purchase_order_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/billing_settings_provider.dart';
import '../../config/routes.dart';
import '../../models/invoice_model.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/searchable_picker.dart';
import '../../widgets/success_overlay.dart';

class PurchaseOrderDetailScreen extends StatelessWidget {
  final String orderId;

  const PurchaseOrderDetailScreen({super.key, required this.orderId});

  Color _statusColor(BuildContext context, POStatus status) => switch (status) {
    POStatus.draft => Theme.of(context).colorScheme.outline,
    POStatus.sent => AppTheme.infoColor,
    POStatus.partial => AppTheme.warningColor,
    POStatus.received => AppTheme.successColor,
    POStatus.cancelled => AppTheme.dangerColor,
  };

  @override
  Widget build(BuildContext context) {
    final order = context.watch<PurchaseOrderProvider>().getOrderById(orderId);
    final user = context.watch<AuthProvider>().currentUser;
    if (order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Purchase Order')),
        body: const Center(child: Text('Order not found')),
      );
    }

    final dateFormat = DateFormat('dd MMM yyyy');
    final currencyFormat = NumberFormat.currency(
      symbol: AppTheme.currencySymbol,
      decimalDigits: 2,
    );
    final statusColor = _statusColor(context, order.status);
    final linkedInvoice = order.invoiceId.isNotEmpty
        ? context.watch<BillingProvider>().getInvoiceById(order.invoiceId)
        : null;

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: AppBarTitleRow(
          icon: Icons.shopping_cart_rounded,
          color: AppTheme.primaryColor,
          title: 'PO-${order.id.substring(0, 6).toUpperCase()}',
        ),
        actions: [
          if (order.invoiceId.isEmpty &&
              context.watch<BillingSettingsProvider>().billingEnabled)
            IconButton(
              icon: const Icon(Icons.receipt_rounded),
              tooltip: 'Create Bill',
              onPressed: () => Navigator.pushNamed(
                context,
                AppRoutes.createInvoice,
                arguments: <String, dynamic>{
                  'purchaseOrderId': order.id,
                  'type': InvoiceType.purchase,
                },
              ),
            ),
          if (order.status == POStatus.draft &&
              (user?.hasPermission(AppPermissions.deletePurchaseOrders) ?? false))
            IconButton(
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: AppTheme.dangerColor,
              ),
              onPressed: () => _confirmDelete(context, order),
            ),
        ],
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
                                order.vendorName.isNotEmpty
                                    ? order.vendorName
                                    : 'Unknown Vendor',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPri(context),
                                ),
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
                                order.statusLabel,
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
                          'Expected Date',
                          dateFormat.format(order.expectedDate),
                        ),
                        if (order.receivedDate != null)
                          _detailRow(
                            context,
                            'Received Date',
                            dateFormat.format(order.receivedDate!),
                          ),
                        _detailRow(
                          context,
                          'Created',
                          dateFormat.format(order.createdAt),
                        ),
                        _detailRow(context, 'Created By', order.createdByName),
                        if (order.notes.isNotEmpty)
                          _detailRow(context, 'Notes', order.notes),
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
                                        ? 'Bill: ${linkedInvoice.invoiceNumber}'
                                        : 'Bill linked',
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
                        Text(
                          'Items',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPri(context),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...order.items.map(
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
                                      color: AppTheme.primaryColor.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.inventory_2_rounded,
                                      color: AppTheme.primaryColor,
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
                                          'Qty: ${item.quantity} \u2022 Received: ${item.receivedQuantity}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.textSec(context),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    currencyFormat.format(
                                      item.quantity * item.unitPrice,
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Divider(height: 24),
                        Row(
                          children: [
                            Text(
                              'Total',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPri(context),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              currencyFormat.format(order.totalAmount),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primaryColor,
                              ),
                            ),
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

  Widget _buildActions(BuildContext context, PurchaseOrderModel order, UserModel? user) {
    final canCancel = user?.hasPermission(AppPermissions.cancelPurchaseOrders) ?? false;

    Widget? primaryAction;
    switch (order.status) {
      case POStatus.draft:
        if (user?.hasPermission(AppPermissions.approvePurchaseOrders) ?? false) {
          primaryAction = ElevatedButton.icon(
            onPressed: () => _sendOrder(context, order),
            icon: const Icon(Icons.send_rounded),
            label: const Text('Send to Vendor'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.infoColor),
          );
        }
      case POStatus.sent:
      case POStatus.partial:
        if (user?.hasPermission(AppPermissions.receivePurchaseOrders) ?? false) {
          primaryAction = ElevatedButton.icon(
            onPressed: () => _showReceiveDialog(context, order),
            icon: const Icon(Icons.check_circle_rounded),
            label: const Text('Receive Items'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successColor),
          );
        }
      case POStatus.received:
      case POStatus.cancelled:
        break;
    }

    final showCancel = canCancel &&
        order.status != POStatus.received &&
        order.status != POStatus.cancelled;

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

  Future<void> _sendOrder(
    BuildContext context,
    PurchaseOrderModel order,
  ) async {
    final updated = order.copyWith(
      status: POStatus.sent,
      updatedAt: DateTime.now(),
    );
    final success = await context.read<PurchaseOrderProvider>().updateOrder(
      updated,
    );
    if (context.mounted && success) {
      HapticFeedback.mediumImpact();
      showSuccessOverlay(context, message: 'Purchase order sent');
    }
  }

  Future<void> _showReceiveDialog(
    BuildContext context,
    PurchaseOrderModel order,
  ) async {
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
          title: const Text('Receive Items'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Select the location to receive items into:'),
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
              child: const Text('Receive'),
            ),
          ],
        ),
      ),
    );

    if (result == null || !context.mounted) return;
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;

    final success = await context.read<PurchaseOrderProvider>().receiveOrder(
      po: order,
      userId: user.uid,
      userName: user.name,
      location: result,
    );

    if (context.mounted && success) {
      context.read<ProductProvider>().invalidateAnalytics();
      HapticFeedback.mediumImpact();
      showSuccessOverlay(context, message: 'Items received successfully');
    }
  }

  Future<void> _confirmCancel(
    BuildContext context,
    PurchaseOrderModel order,
  ) async {
    final wasReceived = order.status == POStatus.received ||
        order.status == POStatus.partial;
    final message = wasReceived
        ? 'This will reverse the received stock and cancel the order. This cannot be undone.'
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

    final success = await context.read<PurchaseOrderProvider>().cancelOrder(
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
        context.read<PurchaseOrderProvider>().errorMessage ?? 'Cancellation failed',
      );
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    PurchaseOrderModel order,
  ) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Delete Order?',
      message: 'This action cannot be undone.',
    );
    if (!confirm || !context.mounted) return;
    final success = await context.read<PurchaseOrderProvider>().deleteOrder(
      order.id,
    );
    if (context.mounted && success) Navigator.pop(context);
  }
}
