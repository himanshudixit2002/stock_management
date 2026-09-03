import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/invoice_model.dart';
import 'package:stock_management/utils/invoice_totals.dart';

/// One invoice used to have four different balances depending on which screen
/// you asked. For a 1,000 invoice carrying a 400 credit note:
///
///   * the invoice screen said 600 (stored `amountDue`);
///   * the customer statement said 1,000 (`grandTotal - amountPaid`, and it
///     filtered credit notes out entirely);
///   * `totalAccountsReceivable` said 1,000 (same subtraction);
///   * `customerOutstanding` said 600.
///
/// [InvoiceModel.outstanding] is now the single definition, and every one of
/// those call sites derives from it.
void main() {
  InvoiceModel invoice({
    double grandTotal = 1000,
    double amountPaid = 0,
    double creditedAmount = 0,
    InvoiceStatus status = InvoiceStatus.sent,
    InvoiceType type = InvoiceType.sales,
  }) => InvoiceModel(
    id: 'i1',
    invoiceNumber: 'INV-0001',
    customerId: 'c1',
    invoiceType: type,
    status: status,
    grandTotal: grandTotal,
    amountPaid: amountPaid,
    creditedAmount: creditedAmount,
    invoiceDate: DateTime(2024, 1, 1),
    dueDate: DateTime(2024, 1, 31),
    createdAt: DateTime(2024, 1, 1),
    updatedAt: DateTime(2024, 1, 1),
  );

  group('outstanding', () {
    test('is the full amount on an untouched invoice', () {
      expect(invoice().outstanding, 1000);
    });

    test('subtracts payments', () {
      expect(invoice(amountPaid: 250).outstanding, 750);
    });

    test('subtracts credit notes — the bug', () {
      expect(invoice(creditedAmount: 400).outstanding, 600);
    });

    test('subtracts both', () {
      expect(invoice(amountPaid: 250, creditedAmount: 400).outstanding, 350);
    });

    test('a fully credited invoice owes nothing', () {
      expect(invoice(creditedAmount: 1000).outstanding, 0);
    });

    test('never goes negative when credit exceeds the balance', () {
      expect(invoice(amountPaid: 800, creditedAmount: 400).outstanding, 0);
    });

    test('a cancelled invoice owes nothing', () {
      expect(invoice(status: InvoiceStatus.cancelled).outstanding, 0);
    });

    test('a draft is not yet a claim', () {
      expect(invoice(status: InvoiceStatus.draft).outstanding, 0);
    });

    test('float residue below a cent reads as settled', () {
      // What unrounded totals used to leave behind: settled to a human, and
      // non-zero to a `> 0` check, which is how it accumulated in the reports.
      expect(invoice(grandTotal: 1000, amountPaid: 999.996).outstanding, 0);
    });
  });

  group('receivable vs payable must not be netted', () {
    test('summing outstanding per type keeps them apart', () {
      final docs = [
        invoice(grandTotal: 100000),
        invoice(grandTotal: 80000, type: InvoiceType.purchase),
      ];

      double totalFor(InvoiceType t) => docs
          .where((i) => i.invoiceType == t)
          .fold<double>(0, (s, i) => s + i.outstanding);

      expect(totalFor(InvoiceType.sales), 100000);
      expect(totalFor(InvoiceType.purchase), 80000);
      // The old report added these into one "Outstanding: 180,000", a figure
      // that rose as the workspace's own debts grew.
      expect(
        totalFor(InvoiceType.sales) + totalFor(InvoiceType.purchase),
        180000,
        reason: 'the meaningless sum, kept here to name it',
      );
    });
  });

  group('totals are rounded to the cent as they are written', () {
    test('a rate that does not divide cleanly still lands on a cent', () {
      final totals = calculateInvoiceTotals(
        lines: const [
          InvoiceTotalsLineInput(
            quantity: 3,
            unitPrice: 33.333,
            lineTaxRate: 18,
          ),
        ],
      );

      for (final value in [
        totals.subtotal,
        totals.taxableAmount,
        totals.totalTax,
        totals.grandTotal,
      ]) {
        expect(
          (value * 100 - (value * 100).round()).abs() < 1e-9,
          isTrue,
          reason: '$value is not a whole number of cents',
        );
      }
    });

    test('an invoice-level discount scales the tax with it', () {
      // The defect the Tax Collected report had: raw line tax is 180, but the
      // document stores tax scaled by the invoice discount.
      final totals = calculateInvoiceTotals(
        lines: const [
          InvoiceTotalsLineInput(
            quantity: 10,
            unitPrice: 100,
            lineTaxRate: 18,
          ),
        ],
        invoiceDiscountAmount: 100,
      );

      expect(totals.subtotal, 1000);
      expect(totals.taxableAmount, 900);
      expect(totals.totalTax, 162, reason: '18% of 900, not of 1000');
      expect(totals.grandTotal, 1062);
    });
  });
}
