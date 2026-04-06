import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../models/invoice_model.dart';
import '../../providers/billing_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/billing_settings_provider.dart';
import '../../services/billing_pdf_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/glass_panel.dart';
import 'record_payment_sheet.dart';

class InvoiceDetailScreen extends StatelessWidget {
  final String invoiceId;
  const InvoiceDetailScreen({super.key, required this.invoiceId});

  static final _dateFormat = DateFormat('dd MMM yyyy');
  static final _numFormat = NumberFormat('#,##0.00');

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final billing = context.watch<BillingProvider>();
    final invoice = billing.getInvoiceById(invoiceId);
    final bs = context.watch<BillingSettingsProvider>().settings;
    final sym = bs.currencySymbol.isNotEmpty ? bs.currencySymbol : '₹';

    if (invoice == null) {
      if (billing.isLoading) {
        return Scaffold(
          appBar: AppBar(title: const Text('Invoice')),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Invoice')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: billing.errorMessage != null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.cloud_off_rounded,
                          size: 48,
                          color: AppTheme.textSec(context),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          billing.errorMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.textPri(context),
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: () {
                            final cid =
                                context.read<ProductProvider>().companyId;
                            if (cid.isNotEmpty) {
                              billing.initialize(companyId: cid);
                            }
                          },
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry'),
                        ),
                      ],
                    )
                  : Text(
                      'Invoice not found',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textPri(context)),
                    ),
            ),
          ),
        ),
      );
    }

    if (user != null && !user.hasPermission(AppPermissions.viewInvoices)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Invoice')),
        body: const Center(
          child: Text('You do not have permission to access this feature.'),
        ),
      );
    }

    final canEdit = user?.hasPermission(AppPermissions.editInvoices) ?? false;
    final canDelete = user?.hasPermission(AppPermissions.deleteInvoices) ?? false;
    final canRecordPayments =
        user?.hasPermission(AppPermissions.recordPayments) ?? false;
    final canCreate = user?.hasPermission(AppPermissions.createInvoices) ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(invoice.invoiceNumber),
            if (invoice.partyName.isNotEmpty)
              Text(
                invoice.partyName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: Theme.of(context).appBarTheme.foregroundColor?.withValues(alpha: 0.85),
                ),
              ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Invoice actions',
            onSelected: (v) => _handleAction(context, v, invoice, bs),
            itemBuilder: (_) => [
              if (invoice.isDraft && canEdit)
                const PopupMenuItem(value: 'send', child: Text('Mark as Sent')),
              if (!invoice.isPaid && !invoice.isCancelled && canRecordPayments)
                const PopupMenuItem(
                  value: 'payment',
                  child: Text('Record Payment'),
                ),
              const PopupMenuItem(value: 'print', child: Text('Print Invoice')),
              const PopupMenuItem(
                value: 'receipt',
                child: Text('Print Receipt'),
              ),
              const PopupMenuItem(value: 'share', child: Text('Share PDF')),
              if (canCreate)
                const PopupMenuItem(
                  value: 'duplicate',
                  child: Text('Duplicate Invoice'),
                ),
              if (!invoice.isPaid && !invoice.isCancelled && canEdit)
                const PopupMenuItem(
                  value: 'cancel',
                  child: Text('Cancel Invoice'),
                ),
              if (invoice.isDraft && canDelete)
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.formMaxWidth(context),
          ),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              Responsive.horizontalPadding(context),
              12,
              Responsive.horizontalPadding(context),
              80,
            ),
            children: [
              _buildStatusBanner(context, invoice),
              const SizedBox(height: 16),
              invoice.isPurchase
                  ? _buildVendorCard(context, invoice)
                  : _buildCustomerCard(context, invoice),
              const SizedBox(height: 12),
              _buildDatesCard(context, invoice),
              const SizedBox(height: 12),
              _buildDocumentIdRow(context, invoice),
              const SizedBox(height: 12),
              _buildItemsCard(context, invoice, bs, sym),
              const SizedBox(height: 12),
              _buildTotalsCard(context, invoice, bs, sym),
              if (bs.enablePaymentTracking && invoice.payments.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildPaymentsCard(context, invoice, sym),
              ],
              if (invoice.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildNotesCard(context, invoice),
              ],
              if (invoice.linkedSalesOrderId.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildLinkedSalesOrder(context, invoice),
              ],
              if (invoice.linkedPurchaseOrderId.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildLinkedPurchaseOrder(context, invoice),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar:
          (!invoice.isPaid &&
              !invoice.isCancelled &&
              bs.enablePaymentTracking &&
              canRecordPayments)
          ? SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  Responsive.horizontalPadding(context),
                  8,
                  Responsive.horizontalPadding(context),
                  8,
                ),
                child: ElevatedButton.icon(
                  onPressed: () => _showPaymentSheet(context, invoice),
                  icon: const Icon(Icons.payment_rounded),
                  label: Text(
                    'Record Payment (${sym}${_numFormat.format(invoice.amountDue)} due)',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildStatusBanner(BuildContext context, InvoiceModel invoice) {
    final color = _statusColor(invoice.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(_statusIcon(invoice.status), color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invoice.statusLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: color,
                    fontSize: 15,
                  ),
                ),
                if (invoice.overdueDays > 0)
                  Text(
                    '${invoice.overdueDays} days overdue',
                    style: TextStyle(fontSize: 12, color: color),
                  ),
              ],
            ),
          ),
          Text(
            _numFormat.format(invoice.grandTotal),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerCard(BuildContext context, InvoiceModel invoice) {
    return GlassPanel(
      borderRadius: 14,
      useContentVariant: true,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.person_rounded,
              color: AppTheme.primaryColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invoice.customerName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                if (invoice.customerPhone.isNotEmpty)
                  Text(
                    invoice.customerPhone,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSec(context),
                    ),
                  ),
                if (invoice.customerAddress.isNotEmpty)
                  Text(
                    invoice.customerAddress,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textTer(context),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVendorCard(BuildContext context, InvoiceModel invoice) {
    return GlassPanel(
      borderRadius: 14,
      useContentVariant: true,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.warningColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.store_rounded,
              color: AppTheme.warningColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      invoice.vendorName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.warningColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Purchase',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.warningColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentIdRow(BuildContext context, InvoiceModel invoice) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Clipboard.setData(ClipboardData(text: invoice.id));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Document ID copied')),
          );
        },
        child: GlassPanel(
          borderRadius: 14,
          useContentVariant: true,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Document ID',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.textTer(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      invoice.id,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSec(context),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.copy_rounded,
                size: 18,
                color: AppTheme.textTer(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDatesCard(BuildContext context, InvoiceModel invoice) {
    return GlassPanel(
      borderRadius: 14,
      useContentVariant: true,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: _miniInfo(
              'Invoice Date',
              _dateFormat.format(invoice.invoiceDate),
              context,
            ),
          ),
          Expanded(
            child: _miniInfo(
              'Due Date',
              _dateFormat.format(invoice.dueDate),
              context,
            ),
          ),
          Expanded(
            child: _miniInfo('Created By', invoice.createdByName, context),
          ),
        ],
      ),
    );
  }

  Widget _miniInfo(String label, String value, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: AppTheme.textTer(context),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildItemsCard(
    BuildContext context,
    InvoiceModel invoice,
    dynamic bs,
    String sym,
  ) {
    return GlassPanel(
      borderRadius: 14,
      useContentVariant: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Items (${invoice.items.length})',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textTer(context),
            ),
          ),
          const SizedBox(height: 8),
          ...invoice.items.asMap().entries.map((e) {
            final i = e.key;
            final item = e.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${i + 1}.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textTer(context),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.productName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '${item.quantity} ${item.unit} x $sym${_numFormat.format(item.unitPrice)}'
                          '${item.discountPercent > 0 ? ' - ${item.discountPercent}% disc' : ''}'
                          '${item.taxRate > 0 ? ' + ${item.taxRate}% tax' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSec(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '$sym${_numFormat.format(item.lineTotal)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTotalsCard(
    BuildContext context,
    InvoiceModel invoice,
    dynamic bs,
    String sym,
  ) {
    return GlassPanel(
      borderRadius: 14,
      useContentVariant: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          _row(
            'Subtotal',
            '$sym${_numFormat.format(invoice.subtotal)}',
            context,
          ),
          if (invoice.totalDiscount > 0)
            _row(
              'Discount',
              '- $sym${_numFormat.format(invoice.totalDiscount)}',
              context,
              color: AppTheme.dangerColor,
            ),
          if (invoice.totalTax > 0)
            _row(
              invoice.taxLabel,
              '$sym${_numFormat.format(invoice.totalTax)}',
              context,
            ),
          const Divider(height: 16),
          _row(
            'Grand Total',
            '$sym${_numFormat.format(invoice.grandTotal)}',
            context,
            bold: true,
            size: 16,
          ),
          if (bs.enablePaymentTracking) ...[
            const SizedBox(height: 4),
            _row(
              'Paid',
              '$sym${_numFormat.format(invoice.amountPaid)}',
              context,
              color: AppTheme.successColor,
            ),
            _row(
              'Due',
              '$sym${_numFormat.format(invoice.amountDue)}',
              context,
              bold: true,
              color: invoice.amountDue > 0
                  ? AppTheme.dangerColor
                  : AppTheme.successColor,
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(
    String label,
    String value,
    BuildContext context, {
    bool bold = false,
    double size = 13,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: size,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: size,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentsCard(
    BuildContext context,
    InvoiceModel invoice,
    String sym,
  ) {
    return GlassPanel(
      borderRadius: 14,
      useContentVariant: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Payment History',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textTer(context),
            ),
          ),
          const SizedBox(height: 8),
          ...invoice.payments.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.successColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      color: AppTheme.successColor,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$sym${_numFormat.format(p.amount)} via ${p.methodLabel}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '${_dateFormat.format(p.date)}${p.referenceNumber.isNotEmpty ? ' • Ref: ${p.referenceNumber}' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textTer(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesCard(BuildContext context, InvoiceModel invoice) {
    return GlassPanel(
      borderRadius: 14,
      useContentVariant: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Notes',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textTer(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(invoice.notes, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildLinkedSalesOrder(BuildContext context, InvoiceModel invoice) {
    return GlassPanel(
      borderRadius: 14,
      useContentVariant: true,
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          leading: const Icon(Icons.link_rounded, color: AppTheme.infoColor),
          title: const Text(
            'Linked Sales Order',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            invoice.linkedSalesOrderId,
            style: const TextStyle(fontSize: 11),
          ),
          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
          onTap: () => Navigator.pushNamed(
            context,
            AppRoutes.salesOrderDetail,
            arguments: invoice.linkedSalesOrderId,
          ),
        ),
      ),
    );
  }

  Widget _buildLinkedPurchaseOrder(BuildContext context, InvoiceModel invoice) {
    return GlassPanel(
      borderRadius: 14,
      useContentVariant: true,
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          leading: const Icon(Icons.link_rounded, color: AppTheme.warningColor),
          title: const Text(
            'Linked Purchase Order',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            invoice.linkedPurchaseOrderId,
            style: const TextStyle(fontSize: 11),
          ),
          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
          onTap: () => Navigator.pushNamed(
            context,
            AppRoutes.purchaseOrderDetail,
            arguments: invoice.linkedPurchaseOrderId,
          ),
        ),
      ),
    );
  }

  Color _statusColor(InvoiceStatus s) => switch (s) {
    InvoiceStatus.draft => Colors.grey,
    InvoiceStatus.sent => AppTheme.infoColor,
    InvoiceStatus.partiallyPaid => AppTheme.warningColor,
    InvoiceStatus.paid => AppTheme.successColor,
    InvoiceStatus.overdue => AppTheme.dangerColor,
    InvoiceStatus.cancelled => Colors.grey.shade600,
    InvoiceStatus.refunded => AppTheme.indigoColor,
  };

  IconData _statusIcon(InvoiceStatus s) => switch (s) {
    InvoiceStatus.draft => Icons.edit_note_rounded,
    InvoiceStatus.sent => Icons.send_rounded,
    InvoiceStatus.partiallyPaid => Icons.hourglass_bottom_rounded,
    InvoiceStatus.paid => Icons.check_circle_rounded,
    InvoiceStatus.overdue => Icons.warning_amber_rounded,
    InvoiceStatus.cancelled => Icons.cancel_rounded,
    InvoiceStatus.refunded => Icons.replay_rounded,
  };

  void _handleAction(
    BuildContext context,
    String action,
    InvoiceModel invoice,
    dynamic bs,
  ) async {
    final billing = context.read<BillingProvider>();
    final user = context.read<AuthProvider>().currentUser;
    final pdfService = BillingPdfService();

    switch (action) {
      case 'send':
        await billing.markAsSent(invoice.id);
        break;
      case 'payment':
        _showPaymentSheet(context, invoice);
        break;
      case 'print':
        try {
          await pdfService.printInvoice(invoice, bs);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Print failed: $e'),
                backgroundColor: AppTheme.dangerColor,
              ),
            );
          }
        }
        break;
      case 'receipt':
        try {
          await pdfService.printReceipt(invoice, bs);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Print failed: $e'),
                backgroundColor: AppTheme.dangerColor,
              ),
            );
          }
        }
        break;
      case 'share':
        try {
          await pdfService.shareInvoice(invoice, bs);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('PDF shared successfully'),
                backgroundColor: AppTheme.successColor,
              ),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Share failed: $e'),
                backgroundColor: AppTheme.dangerColor,
              ),
            );
          }
        }
        break;
      case 'duplicate':
        final prefix = invoice.isPurchase
            ? bs.purchasePrefix
            : bs.invoicePrefix;
        final num = await billing.getNextInvoiceNumber(
          prefix,
          type: invoice.invoiceType,
        );
        if (num != null) {
          final dup = billing.duplicateInvoice(
            source: invoice,
            invoiceNumber: num,
          );
          await billing.addInvoice(
            dup,
            userId: user?.uid ?? '',
            userName: user?.name ?? '',
            autoCreateStandaloneSalesOrder: false,
            autoCreateStandalonePurchaseOrder: false,
          );
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Invoice $num created'),
                backgroundColor: AppTheme.successColor,
              ),
            );
          }
        }
        break;
      case 'cancel':
        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Cancel Invoice?'),
            content: const Text('This action cannot be undone.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('No'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Yes, Cancel'),
              ),
            ],
          ),
        );
        if (confirm == true) {
          await billing.markAsCancelled(
            invoice.id,
            userId: user?.uid ?? '',
            userName: user?.name ?? '',
          );
        }
        break;
      case 'delete':
        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete Invoice?'),
            content: const Text(
              'This will permanently delete this draft invoice.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('No'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: AppTheme.dangerColor),
                ),
              ),
            ],
          ),
        );
        if (confirm == true) {
          await billing.deleteInvoice(invoice.id);
          if (context.mounted) Navigator.pop(context);
        }
        break;
    }
  }

  void _showPaymentSheet(BuildContext context, InvoiceModel invoice) {
    showModalBottomSheet(
      context: context,
      constraints: Responsive.sheetConstraints(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => RecordPaymentSheet(
        invoiceId: invoice.id,
        invoiceNumber: invoice.invoiceNumber,
        amountDue: invoice.amountDue,
        currencySymbol: context
            .read<BillingSettingsProvider>()
            .settings
            .currencySymbol,
      ),
    );
  }
}

/// Resolves [routeArgument] as either a Firestore document id or a display invoice number.
class InvoiceDetailRouteEntry extends StatelessWidget {
  const InvoiceDetailRouteEntry({super.key, required this.routeArgument});

  final String routeArgument;

  @override
  Widget build(BuildContext context) {
    final billing = context.watch<BillingProvider>();
    final byId = billing.getInvoiceById(routeArgument);
    final resolvedId = byId != null
        ? routeArgument
        : (billing.getInvoiceByInvoiceNumber(routeArgument)?.id ??
            routeArgument);
    return InvoiceDetailScreen(invoiceId: resolvedId);
  }
}
