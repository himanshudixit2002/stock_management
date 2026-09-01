import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/utils/invoice_totals.dart';

void main() {
  group('calculateInvoiceTotals', () {
    test('scales tax to the amount actually billed', () {
      final totals = calculateInvoiceTotals(
        lines: const [
          InvoiceTotalsLineInput(
            quantity: 10,
            unitPrice: 100,
            lineDiscountPercent: 5,
            lineTaxRate: 18,
          ),
          InvoiceTotalsLineInput(
            quantity: 2,
            unitPrice: 50,
            lineDiscountPercent: 0,
            lineTaxRate: 18,
          ),
        ],
        invoiceDiscountPercent: 10,
        invoiceDiscountAmount: 20,
        taxEnabled: true,
        discountEnabled: true,
      );

      expect(totals.subtotal, closeTo(1100.0, 0.0001));
      expect(totals.lineDiscount, closeTo(50.0, 0.0001));
      expect(totals.invoiceDiscount, closeTo(125.0, 0.0001));
      expect(totals.totalDiscount, closeTo(175.0, 0.0001));
      expect(totals.taxableAmount, closeTo(925.0, 0.0001));
      // Every line is at 18%, so tax must equal 18% of the taxable amount.
      // The previous implementation scaled tax by the percentage discount only
      // and returned 170.1 — tax on 945, which was never billed.
      expect(totals.totalTax, closeTo(925.0 * 0.18, 0.0001));
      expect(totals.grandTotal, closeTo(1091.5, 0.0001));
    });

    test('a flat invoice discount reduces tax too', () {
      // 100 @ 10% tax, then 50 off. Taxable 50, so tax must be 5 — not 10.
      final totals = calculateInvoiceTotals(
        lines: const [
          InvoiceTotalsLineInput(
            quantity: 1,
            unitPrice: 100,
            lineTaxRate: 10,
          ),
        ],
        invoiceDiscountAmount: 50,
      );

      expect(totals.invoiceDiscount, closeTo(50.0, 0.0001));
      expect(totals.taxableAmount, closeTo(50.0, 0.0001));
      expect(totals.totalTax, closeTo(5.0, 0.0001));
      expect(totals.grandTotal, closeTo(55.0, 0.0001));
    });

    test('a flat discount larger than the subtotal cannot go negative', () {
      final totals = calculateInvoiceTotals(
        lines: const [
          InvoiceTotalsLineInput(
            quantity: 1,
            unitPrice: 100,
            lineTaxRate: 18,
          ),
        ],
        invoiceDiscountAmount: 500,
      );

      expect(totals.invoiceDiscount, closeTo(100.0, 0.0001));
      expect(totals.taxableAmount, closeTo(0.0, 0.0001));
      expect(totals.totalTax, closeTo(0.0, 0.0001));
      expect(totals.grandTotal, closeTo(0.0, 0.0001));
      expect(totals.grandTotal, greaterThanOrEqualTo(0.0));
    });

    test('percentage and flat invoice discounts combine', () {
      // 200 subtotal, 10% = 20, plus 30 flat = 50 total invoice discount.
      final totals = calculateInvoiceTotals(
        lines: const [
          InvoiceTotalsLineInput(quantity: 2, unitPrice: 100, lineTaxRate: 5),
        ],
        invoiceDiscountPercent: 10,
        invoiceDiscountAmount: 30,
      );

      expect(totals.invoiceDiscount, closeTo(50.0, 0.0001));
      expect(totals.taxableAmount, closeTo(150.0, 0.0001));
      expect(totals.totalTax, closeTo(7.5, 0.0001));
      expect(totals.grandTotal, closeTo(157.5, 0.0001));
    });

    test('ignores zero and negative quantity lines', () {
      final totals = calculateInvoiceTotals(
        lines: const [
          InvoiceTotalsLineInput(quantity: 0, unitPrice: 999, lineTaxRate: 18),
          InvoiceTotalsLineInput(quantity: -5, unitPrice: 999, lineTaxRate: 18),
          InvoiceTotalsLineInput(quantity: 1, unitPrice: 100, lineTaxRate: 0),
        ],
      );

      expect(totals.subtotal, closeTo(100.0, 0.0001));
      expect(totals.grandTotal, closeTo(100.0, 0.0001));
    });

    test('treats a negative tax rate as zero', () {
      final totals = calculateInvoiceTotals(
        lines: const [
          InvoiceTotalsLineInput(quantity: 1, unitPrice: 100, lineTaxRate: -18),
        ],
      );

      expect(totals.totalTax, closeTo(0.0, 0.0001));
      expect(totals.grandTotal, closeTo(100.0, 0.0001));
    });

    test('clamps a line discount above 100 percent', () {
      final totals = calculateInvoiceTotals(
        lines: const [
          InvoiceTotalsLineInput(
            quantity: 1,
            unitPrice: 100,
            lineDiscountPercent: 250,
          ),
        ],
      );

      expect(totals.lineDiscount, closeTo(100.0, 0.0001));
      expect(totals.grandTotal, closeTo(0.0, 0.0001));
    });

    test('disables tax and discounts when feature flags are off', () {
      final totals = calculateInvoiceTotals(
        lines: const [
          InvoiceTotalsLineInput(
            quantity: 2,
            unitPrice: 40,
            lineDiscountPercent: 50,
            lineTaxRate: 18,
          ),
        ],
        invoiceDiscountPercent: 20,
        invoiceDiscountAmount: 10,
        taxEnabled: false,
        discountEnabled: false,
      );

      expect(totals.subtotal, 80.0);
      expect(totals.totalDiscount, 0.0);
      expect(totals.totalTax, 0.0);
      expect(totals.grandTotal, 80.0);
    });
  });
}
