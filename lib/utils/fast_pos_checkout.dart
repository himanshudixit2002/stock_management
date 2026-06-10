import '../models/billing_settings_model.dart';
import '../models/customer_model.dart';
import '../models/invoice_model.dart';
import '../models/product_model.dart';
import 'invoice_totals.dart';

enum FastCheckoutMode { paidNow, credit }

class FastPosCartEntry {
  final ProductModel product;
  final int quantity;
  final double unitPrice;
  final double discountPercent;
  final String location;

  const FastPosCartEntry({
    required this.product,
    required this.quantity,
    required this.unitPrice,
    this.discountPercent = 0,
    this.location = '',
  });
}

class FastPosCheckoutPayload {
  final InvoiceModel invoice;
  final InvoiceTotals totals;

  const FastPosCheckoutPayload({required this.invoice, required this.totals});
}

FastPosCheckoutPayload buildFastPosInvoice({
  required List<FastPosCartEntry> cartEntries,
  required BillingSettings billingSettings,
  required String invoiceNumber,
  required DateTime now,
  required String userId,
  required String userName,
  CustomerModel? customer,
  required FastCheckoutMode mode,
  String paymentMethod = 'cash',
}) {
  final lineInputs = cartEntries
      .map(
        (entry) => InvoiceTotalsLineInput(
          quantity: entry.quantity,
          unitPrice: entry.unitPrice,
          lineDiscountPercent: billingSettings.enableDiscounts
              ? entry.discountPercent
              : 0,
          lineTaxRate: billingSettings.enableTax ? billingSettings.defaultTaxRate : 0,
        ),
      )
      .toList();
  final totals = calculateInvoiceTotals(
    lines: lineInputs,
    taxEnabled: billingSettings.enableTax,
    discountEnabled: billingSettings.enableDiscounts,
  );

  final items = cartEntries
      .map(
        (entry) => InvoiceItem(
          productId: entry.product.id,
          productName: entry.product.name,
          quantity: entry.quantity,
          unit: entry.product.baseUnit,
          unitPrice: entry.unitPrice,
          discountPercent: billingSettings.enableDiscounts
              ? entry.discountPercent
              : 0,
          taxRate: billingSettings.enableTax ? billingSettings.defaultTaxRate : 0,
          location: entry.location,
        ),
      )
      .toList();

  final dueDate = now.add(Duration(days: billingSettings.defaultPaymentTermDays));
  final isPaid = mode == FastCheckoutMode.paidNow;
  final paidAmount = isPaid ? totals.grandTotal : 0.0;
  final dueAmount = isPaid ? 0.0 : totals.grandTotal;
  final payments = isPaid
      ? [
          PaymentRecord(
            id: 'pay-${now.microsecondsSinceEpoch}',
            amount: totals.grandTotal,
            date: now,
            method: paymentMethod,
          ),
        ]
      : const <PaymentRecord>[];

  return FastPosCheckoutPayload(
    totals: totals,
    invoice: InvoiceModel(
      id: '',
      invoiceType: InvoiceType.sales,
      invoiceNumber: invoiceNumber,
      customerId: customer?.id ?? '',
      customerName: customer?.name ?? 'Walk-in Customer',
      customerPhone: customer?.phone ?? '',
      customerAddress: customer?.address ?? '',
      status: isPaid ? InvoiceStatus.paid : InvoiceStatus.sent,
      items: items,
      taxLabel: billingSettings.taxLabel,
      subtotal: totals.subtotal,
      totalDiscount: totals.totalDiscount,
      totalTax: totals.totalTax,
      grandTotal: totals.grandTotal,
      amountPaid: paidAmount,
      amountDue: dueAmount,
      payments: payments,
      invoiceDate: now,
      dueDate: dueDate,
      termsText: billingSettings.invoiceFooter,
      createdBy: userId,
      createdByName: userName,
      createdAt: now,
      updatedAt: now,
    ),
  );
}
