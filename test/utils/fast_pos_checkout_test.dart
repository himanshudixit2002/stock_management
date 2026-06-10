import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/billing_settings_model.dart';
import 'package:stock_management/models/customer_model.dart';
import 'package:stock_management/models/invoice_model.dart';
import 'package:stock_management/models/product_model.dart';
import 'package:stock_management/utils/fast_pos_checkout.dart';

ProductModel _product({
  required String id,
  required String name,
  double price = 100,
}) {
  final now = DateTime(2026, 1, 1);
  return ProductModel(
    id: id,
    name: name,
    categoryId: 'cat-1',
    quantity: 100,
    sellingPrice: price,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('buildFastPosInvoice', () {
    const settings = BillingSettings(
      enableTax: true,
      enableDiscounts: true,
      defaultTaxRate: 18,
      defaultPaymentTermDays: 15,
      taxLabel: 'GST',
    );
    final now = DateTime(2026, 6, 1, 12, 0);

    test('creates paid invoice with embedded payment in paid now mode', () {
      final payload = buildFastPosInvoice(
        cartEntries: [
          FastPosCartEntry(product: _product(id: 'p1', name: 'Tea'), quantity: 2, unitPrice: 50),
        ],
        billingSettings: settings,
        invoiceNumber: 'INV-1',
        now: now,
        userId: 'u1',
        userName: 'Cashier',
        mode: FastCheckoutMode.paidNow,
        paymentMethod: 'upi',
      );

      expect(payload.invoice.status, InvoiceStatus.paid);
      expect(payload.invoice.amountDue, 0);
      expect(payload.invoice.amountPaid, closeTo(payload.totals.grandTotal, 0.0001));
      expect(payload.invoice.payments, hasLength(1));
      expect(payload.invoice.payments.first.method, 'upi');
      expect(payload.invoice.linkedSalesOrderId, isEmpty);
      expect(payload.invoice.items, hasLength(1));
      expect(payload.invoice.items.first.quantity, 2);
    });

    test('carries per-entry location onto each invoice item', () {
      final payload = buildFastPosInvoice(
        cartEntries: [
          FastPosCartEntry(
            product: _product(id: 'p1', name: 'Tea'),
            quantity: 1,
            unitPrice: 50,
            location: 'Warehouse A',
          ),
          FastPosCartEntry(
            product: _product(id: 'p1', name: 'Tea'),
            quantity: 2,
            unitPrice: 50,
            location: 'Shop Front',
          ),
          FastPosCartEntry(
            product: _product(id: 'p2', name: 'Sugar'),
            quantity: 1,
            unitPrice: 40,
          ),
        ],
        billingSettings: settings,
        invoiceNumber: 'INV-LOC',
        now: now,
        userId: 'u1',
        userName: 'Cashier',
        mode: FastCheckoutMode.paidNow,
      );

      expect(payload.invoice.items, hasLength(3));
      expect(payload.invoice.items[0].location, 'Warehouse A');
      expect(payload.invoice.items[1].location, 'Shop Front');
      expect(payload.invoice.items[2].location, isEmpty);
    });

    test('creates credit invoice with outstanding due', () {
      final customer = CustomerModel(
        id: 'c1',
        name: 'Rahul Stores',
        phone: '9999999999',
        createdAt: now,
        updatedAt: now,
      );
      final payload = buildFastPosInvoice(
        cartEntries: [
          FastPosCartEntry(product: _product(id: 'p1', name: 'Tea'), quantity: 1, unitPrice: 100),
        ],
        billingSettings: settings,
        invoiceNumber: 'INV-2',
        now: now,
        userId: 'u1',
        userName: 'Cashier',
        customer: customer,
        mode: FastCheckoutMode.credit,
      );

      expect(payload.invoice.status, InvoiceStatus.sent);
      expect(payload.invoice.amountPaid, 0);
      expect(payload.invoice.amountDue, closeTo(payload.totals.grandTotal, 0.0001));
      expect(payload.invoice.payments, isEmpty);
      expect(payload.invoice.customerId, 'c1');
      expect(payload.invoice.customerName, 'Rahul Stores');
      expect(
        payload.invoice.dueDate,
        now.add(const Duration(days: 15)),
      );
    });
  });
}
