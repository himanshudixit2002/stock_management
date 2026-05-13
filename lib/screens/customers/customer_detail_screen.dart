import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../models/customer_model.dart';
import '../../models/invoice_model.dart';
import '../../models/sales_order_model.dart';
import '../../providers/billing_provider.dart';
import '../../providers/billing_settings_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/sales_order_provider.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/animated_list_item.dart';
import '../../config/routes.dart';
import '../../config/app_navigation.dart';

class CustomerDetailScreen extends StatelessWidget {
  final String customerId;

  const CustomerDetailScreen({super.key, required this.customerId});

  Color _statusColor(BuildContext context, SOStatus status) => switch (status) {
    SOStatus.draft => Theme.of(context).colorScheme.outline,
    SOStatus.confirmed => AppTheme.primaryColor,
    SOStatus.dispatched => AppTheme.indigoColor,
    SOStatus.delivered => AppTheme.successColor,
    SOStatus.cancelled => AppTheme.dangerColor,
  };

  @override
  Widget build(BuildContext context) {
    final customer = context.watch<CustomerProvider>().getCustomerById(
      customerId,
    );
    if (customer == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Customer')),
        body: const Center(child: Text('Customer not found')),
      );
    }

    final allOrders = context.watch<SalesOrderProvider>().orders;
    final customerOrders = allOrders
        .where((o) => o.customerId == customerId)
        .toList();

    final dateFormat = DateFormat('dd MMM yyyy');
    final currencyFormat = NumberFormat.currency(
      symbol: AppTheme.currencySymbol,
      decimalDigits: 2,
    );

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: AppBarTitleRow(
          icon: Icons.person_rounded,
          color: AppTheme.primaryColor,
          title: customer.name,
        ),
        actions: [
          if (context.watch<AuthProvider>().currentUser?.hasPermission(AppPermissions.editCustomers) ?? false)
            IconButton(
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => context.pushAppRoute(AppRoutes.editCustomer,
                extra: customer,
              ),
            ),
          if (context.watch<AuthProvider>().currentUser?.hasPermission(AppPermissions.deleteCustomers) ?? false)
            IconButton(
              icon: const Icon(Icons.delete_rounded),
              onPressed: () => _confirmDelete(context, customer),
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
                  final section1 = Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Center(
                                    child: Text(
                                      customer.name.isNotEmpty
                                          ? customer.name[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.primaryColor,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        customer.name,
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.textPri(context),
                                        ),
                                      ),
                                      if (customer.company.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          customer.company,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: AppTheme.textSec(context),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: customer.isActive
                                        ? AppTheme.successColor.withValues(
                                            alpha: 0.12,
                                          )
                                        : AppTheme.dangerColor.withValues(
                                            alpha: 0.12,
                                          ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    customer.isActive ? 'Active' : 'Inactive',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: customer.isActive
                                          ? AppTheme.successColor
                                          : AppTheme.dangerColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            if (customer.email.isNotEmpty)
                              _contactRow(
                                context,
                                Icons.email_rounded,
                                customer.email,
                              ),
                            if (customer.phone.isNotEmpty)
                              _contactRow(
                                context,
                                Icons.phone_rounded,
                                customer.phone,
                              ),
                            if (customer.address.isNotEmpty)
                              _contactRow(
                                context,
                                Icons.location_on_rounded,
                                customer.address,
                              ),
                            if (customer.notes.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _contactRow(
                                context,
                                Icons.note_rounded,
                                customer.notes,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _statCard(
                              context,
                              'Total Orders',
                              '${customer.totalOrders}',
                              AppTheme.indigoColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _statCard(
                              context,
                              'Total Spent',
                              currencyFormat.format(customer.totalSpent),
                              AppTheme.primaryColor,
                            ),
                          ),
                        ],
                      ),
                      if (context
                          .watch<BillingSettingsProvider>()
                          .billingEnabled) ...[
                        const SizedBox(height: 16),
                        _buildBillingSection(
                          context,
                          customerId,
                          customer.name,
                          currencyFormat,
                        ),
                      ],
                    ],
                  );
                  final section2 = customerOrders.isEmpty
                      ? const SizedBox.shrink()
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                'Recent Orders (${customerOrders.length})',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPri(context),
                                ),
                              ),
                            ),
                            ...List.generate(
                              customerOrders.length > 10
                                  ? 10
                                  : customerOrders.length,
                              (index) {
                                final order = customerOrders[index];
                                final statusColor = _statusColor(context, order.status);
                                return AnimatedListItem(
                                  index: index,
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: GlassCard(
                                      onTap: () => context.pushAppRoute(AppRoutes.salesOrderDetail,
                                        extra: order.id,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(14),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 36,
                                              height: 36,
                                              decoration: BoxDecoration(
                                                color: statusColor.withValues(
                                                  alpha: 0.12,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Icon(
                                                Icons.receipt_long_rounded,
                                                color: statusColor,
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
                                                    'SO-${order.id.substring(0, 6).toUpperCase()}',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  Text(
                                                    '${order.items.length} items \u2022 ${dateFormat.format(order.createdAt)}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color:
                                                          AppTheme.textSec(
                                                            context,
                                                          ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  currencyFormat.format(
                                                    order.totalAmount,
                                                  ),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: statusColor
                                                        .withValues(
                                                          alpha: 0.12,
                                                        ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      6,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    order.statusLabel,
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: statusColor,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        );
                  if (Responsive.isDesktop(context) &&
                      customerOrders.isNotEmpty) {
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
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBillingSection(
    BuildContext context,
    String customerId,
    String customerName,
    NumberFormat currencyFormat,
  ) {
    final billing = context.watch<BillingProvider>();
    final bs = context.watch<BillingSettingsProvider>().settings;
    final sym = bs.currencySymbol.isNotEmpty ? bs.currencySymbol : '₹';
    final numFmt = NumberFormat('#,##0.00');
    final dateFmt = DateFormat('dd MMM yyyy');
    final outstanding = billing.customerOutstanding(customerId);
    final custInvoices = billing.invoicesForCustomer(customerId);
    final recent = custInvoices.take(5).toList();

    return GlassPanel(
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      useContentVariant: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.receipt_long_rounded,
                size: 18,
                color: AppTheme.primaryColor,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Invoices',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: outstanding > 0
                      ? AppTheme.dangerColor.withValues(alpha: 0.1)
                      : AppTheme.successColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Due: $sym${numFmt.format(outstanding)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: outstanding > 0
                        ? AppTheme.dangerColor
                        : AppTheme.successColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (recent.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No invoices yet',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textTer(context),
                ),
              ),
            )
          else
            ...recent.map(
              (inv) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => context.pushAppRoute(AppRoutes.invoiceDetail,
                      extra: inv.id,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  inv.invoiceNumber,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  '${dateFmt.format(inv.invoiceDate)} · ${inv.statusLabel}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textTer(context),
                                  ),
                                ),
                                if (inv.amountDue > 0 &&
                                    !inv.isPaid &&
                                    !inv.isCancelled)
                                  Text(
                                    'Due: $sym${numFmt.format(inv.amountDue)}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.dangerColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '$sym${numFmt.format(inv.grandTotal)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: AppTheme.textTer(context),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      context.pushAppRoute(AppRoutes.customerStatement),
                  icon: const Icon(Icons.description_rounded, size: 16),
                  label: const Text(
                    'Statement',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => context.pushAppRoute(AppRoutes.createInvoice,
                    extra: <String, dynamic>{
                      'type': InvoiceType.sales,
                      'customerId': customerId,
                      'customerName': customerName,
                    },
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text(
                    'Create Invoice',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _contactRow(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.textTer(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14, color: AppTheme.textPri(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) {
    return GlassPanel(
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      useContentVariant: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: AppTheme.textSec(context)),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, CustomerModel customer) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete Customer',
      message:
          'Are you sure you want to delete "${customer.name}"? This cannot be undone.',
      confirmLabel: 'Delete',
      icon: Icons.delete_forever_rounded,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await context.read<CustomerProvider>().deleteCustomer(customer.id);
    if (!context.mounted) return;
    if (ok) {
      Navigator.pop(context);
      showSuccessSnackBar(context, 'Customer deleted');
    } else {
      showErrorSnackBar(
        context,
        context.read<CustomerProvider>().errorMessage ?? 'Failed to delete',
      );
    }
  }
}