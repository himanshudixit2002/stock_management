import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/invoice_model.dart';
import 'package:stock_management/services/tax_summary_service.dart';
import 'package:stock_management/utils/invoice_totals.dart';

void main() {
  /// Builds an invoice whose stored totals were produced by the same code the
  /// app uses, so the summary is tested against real documents rather than
  /// hand-written numbers that could never occur.
  InvoiceModel invoice({
    required List<InvoiceItem> items,
    InvoiceType type = InvoiceType.sales,
    InvoiceStatus status = InvoiceStatus.sent,
    double invoiceDiscountPercent = 0,
    DateTime? date,
  }) {
    final totals = calculateInvoiceTotals(
      lines: items
          .map(
            (i) => InvoiceTotalsLineInput(
              quantity: i.quantity,
              unitPrice: i.unitPrice,
              lineDiscountPercent: i.discountPercent,
              lineTaxRate: i.taxRate,
            ),
          )
          .toList(),
      invoiceDiscountPercent: invoiceDiscountPercent,
      discountEnabled: true,
    );
    final when = date ?? DateTime(2026, 3, 10);
    return InvoiceModel(
      id: 'i1',
      invoiceType: type,
      invoiceNumber: 'INV-1',
      customerId: 'c1',
      status: status,
      items: items,
      subtotal: totals.subtotal,
      totalDiscount: totals.totalDiscount,
      invoiceDiscount: totals.invoiceDiscount,
      totalTax: totals.totalTax,
      grandTotal: totals.grandTotal,
      invoiceDate: when,
      dueDate: when,
      createdAt: when,
      updatedAt: when,
    );
  }

  InvoiceItem item({
    required int quantity,
    required double price,
    required double tax,
    double discount = 0,
  }) => InvoiceItem(
    productId: 'p',
    productName: 'p',
    quantity: quantity,
    unitPrice: price,
    taxRate: tax,
    discountPercent: discount,
  );

  final march = TaxPeriod.month(DateTime(2026, 3, 15));

  group('TaxPeriod', () {
    test('a month runs from the 1st to the 1st of the next', () {
      expect(march.start, DateTime(2026, 3, 1));
      expect(march.end, DateTime(2026, 4, 1));
      expect(march.label, 'March 2026');
    });

    test('the end is exclusive, so the last day is still inside', () {
      expect(march.contains(DateTime(2026, 3, 31, 23, 59, 59)), isTrue);
      expect(march.contains(DateTime(2026, 4, 1)), isFalse);
    });

    test('a quarter covers three months from its first', () {
      final q = TaxPeriod.quarter(DateTime(2026, 5, 20));
      expect(q.start, DateTime(2026, 4, 1));
      expect(q.end, DateTime(2026, 7, 1));
      expect(q.label, 'Q2 2026');
    });

    test('the financial year starts in April, not January', () {
      expect(
        TaxPeriod.financialYear(DateTime(2026, 3, 31)).start,
        DateTime(2025, 4, 1),
      );
      expect(
        TaxPeriod.financialYear(DateTime(2026, 4, 1)).start,
        DateTime(2026, 4, 1),
      );
      expect(TaxPeriod.financialYear(DateTime(2026, 5, 1)).label, 'FY 2026-27');
    });

    test('shifting a month steps across a year boundary', () {
      final january = TaxPeriod.month(DateTime(2026, 1, 10));
      expect(january.shift(-1).start, DateTime(2025, 12, 1));
    });
  });

  group('build', () {
    test('splits output tax by rate', () {
      final summary = TaxSummaryService.build([
        invoice(
          items: [
            item(quantity: 1, price: 1000, tax: 18),
            item(quantity: 1, price: 500, tax: 5),
          ],
        ),
      ], march);

      expect(summary.output.slabs.length, 2);
      // Highest rate first.
      expect(summary.output.slabs.first.rate, 18);
      expect(summary.output.slabs.first.taxableValue, 1000);
      expect(summary.output.slabs.first.taxAmount, 180);
      expect(summary.output.slabs.last.taxAmount, 25);
      expect(summary.output.taxAmount, 205);
    });

    test('slab tax adds up to the invoice total it came from', () {
      // The whole point of recomputing the split from the items: it must not
      // disagree with the document. An invoice-level discount scales tax down,
      // and the slabs have to scale with it.
      final doc = invoice(
        items: [
          item(quantity: 2, price: 1000, tax: 18),
          item(quantity: 1, price: 400, tax: 12),
        ],
        invoiceDiscountPercent: 10,
      );
      final summary = TaxSummaryService.build([doc], march);
      expect(summary.output.taxAmount, closeTo(doc.totalTax, 0.02));
    });

    test('a line discount reduces the taxable value it contributes', () {
      final summary = TaxSummaryService.build([
        invoice(
          items: [item(quantity: 1, price: 1000, tax: 18, discount: 50)],
        ),
      ], march);
      expect(summary.output.taxableValue, 500);
      expect(summary.output.taxAmount, 90);
    });

    test('purchases land on the input side and offset the net payable', () {
      final summary = TaxSummaryService.build([
        invoice(items: [item(quantity: 1, price: 1000, tax: 18)]),
        invoice(
          items: [item(quantity: 1, price: 500, tax: 18)],
          type: InvoiceType.purchase,
        ),
      ], march);

      expect(summary.output.taxAmount, 180);
      expect(summary.input.taxAmount, 90);
      expect(summary.netPayable, 90);
    });

    test('credit notes reduce output tax rather than adding to it', () {
      final summary = TaxSummaryService.build([
        invoice(items: [item(quantity: 1, price: 1000, tax: 18)]),
        invoice(
          items: [item(quantity: 1, price: 200, tax: 18)],
          type: InvoiceType.creditNote,
        ),
      ], march);

      expect(summary.output.taxAmount, 180);
      expect(summary.credits.taxAmount, 36);
      expect(summary.netOutputTax, 144);
      expect(summary.netPayable, 144);
    });

    test('drafts and cancellations are excluded and counted, not silently dropped', () {
      final summary = TaxSummaryService.build([
        invoice(
          items: [item(quantity: 1, price: 1000, tax: 18)],
          status: InvoiceStatus.draft,
        ),
        invoice(
          items: [item(quantity: 1, price: 1000, tax: 18)],
          status: InvoiceStatus.cancelled,
        ),
      ], march);

      expect(summary.isEmpty, isTrue);
      expect(summary.excludedCount, 2);
    });

    test('invoices outside the period are ignored entirely', () {
      final summary = TaxSummaryService.build([
        invoice(
          items: [item(quantity: 1, price: 1000, tax: 18)],
          date: DateTime(2026, 2, 28),
        ),
      ], march);
      expect(summary.isEmpty, isTrue);
      expect(summary.excludedCount, 0);
    });

    test('a negative net payable means a refund position', () {
      final summary = TaxSummaryService.build([
        invoice(
          items: [item(quantity: 1, price: 5000, tax: 18)],
          type: InvoiceType.purchase,
        ),
      ], march);
      expect(summary.netPayable, lessThan(0));
    });

    test('zero-rated lines still appear, as a 0% slab', () {
      final summary = TaxSummaryService.build([
        invoice(items: [item(quantity: 1, price: 1000, tax: 0)]),
      ], march);
      expect(summary.output.slabs.single.rate, 0);
      expect(summary.output.slabs.single.taxableValue, 1000);
      expect(summary.output.taxAmount, 0);
    });

    test('two invoices at the same rate merge into one slab, counted twice', () {
      final summary = TaxSummaryService.build([
        invoice(items: [item(quantity: 1, price: 1000, tax: 18)]),
        invoice(items: [item(quantity: 1, price: 2000, tax: 18)]),
      ], march);
      expect(summary.output.slabs.single.documentCount, 2);
      expect(summary.output.slabs.single.taxableValue, 3000);
    });
  });
}
