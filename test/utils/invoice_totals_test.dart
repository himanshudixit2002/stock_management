import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/utils/invoice_totals.dart';

void main() {
  group('calculateInvoiceTotals', () {
    test('matches existing invoice tax and discount behavior', () {
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
      expect(totals.totalTax, closeTo(170.1, 0.0001));
      expect(totals.grandTotal, closeTo(1095.1, 0.0001));
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
