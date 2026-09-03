class InvoiceTotalsLineInput {
  final int quantity;
  final double unitPrice;
  final double lineDiscountPercent;
  final double lineTaxRate;

  const InvoiceTotalsLineInput({
    required this.quantity,
    required this.unitPrice,
    this.lineDiscountPercent = 0,
    this.lineTaxRate = 0,
  });
}

class InvoiceTotals {
  final double subtotal;
  final double lineDiscount;
  final double invoiceDiscount;
  final double totalDiscount;
  final double taxableAmount;
  final double totalTax;
  final double grandTotal;

  const InvoiceTotals({
    required this.subtotal,
    required this.lineDiscount,
    required this.invoiceDiscount,
    required this.totalDiscount,
    required this.taxableAmount,
    required this.totalTax,
    required this.grandTotal,
  });
}

InvoiceTotals calculateInvoiceTotals({
  required List<InvoiceTotalsLineInput> lines,
  double invoiceDiscountPercent = 0,
  double invoiceDiscountAmount = 0,
  bool taxEnabled = true,
  bool discountEnabled = true,
}) {
  var subtotal = 0.0;
  var totalLineDiscount = 0.0;
  var totalTax = 0.0;

  for (final line in lines) {
    if (line.quantity <= 0) continue;
    final lineSubtotal = line.quantity * line.unitPrice;
    subtotal += lineSubtotal;

    final lineDiscountPct = discountEnabled
        ? line.lineDiscountPercent.clamp(0, 100)
        : 0.0;
    final lineDiscount = lineSubtotal * lineDiscountPct / 100;
    totalLineDiscount += lineDiscount;

    if (taxEnabled) {
      final taxableAfterLineDiscount = lineSubtotal - lineDiscount;
      final taxRate = line.lineTaxRate < 0 ? 0.0 : line.lineTaxRate;
      totalTax += taxableAfterLineDiscount * taxRate / 100;
    }
  }

  final invoicePct = discountEnabled ? invoiceDiscountPercent.clamp(0, 100) : 0.0;
  final invoiceFlat = discountEnabled ? invoiceDiscountAmount : 0.0;
  
  final preInvoiceTaxable = subtotal - totalLineDiscount;
  double invoiceDiscount =
      preInvoiceTaxable * invoicePct / 100 + invoiceFlat;
  
  // Clamp invoice discount so it doesn't exceed the remaining amount
  if (invoiceDiscount > preInvoiceTaxable) {
    invoiceDiscount = preInvoiceTaxable;
  }
  if (invoiceDiscount < 0) {
    invoiceDiscount = 0;
  }

  final totalDiscount = totalLineDiscount + invoiceDiscount;
  final taxableAmount = subtotal - totalDiscount;
  
  if (taxEnabled) {
    if (preInvoiceTaxable > 0) {
      totalTax *= (taxableAmount / preInvoiceTaxable);
    } else {
      totalTax = 0;
    }
  } else {
    totalTax = 0;
  }
  
  final grandTotal = taxableAmount + totalTax;

  // Rounded to the cent as it leaves. These figures are persisted and then
  // compared against payments, so binary-float residue accumulates: an invoice
  // could sit at amountDue ~0.004 — settled to a human, non-zero to the code —
  // and thousands of those add up in the reports' outstanding totals. Rounding
  // once here, at the point the numbers become the document, keeps every later
  // comparison exact. The epsilons elsewhere stay as a second line of defence
  // for documents written before this.
  return InvoiceTotals(
    subtotal: _cents(subtotal),
    lineDiscount: _cents(totalLineDiscount),
    invoiceDiscount: _cents(invoiceDiscount),
    totalDiscount: _cents(totalDiscount),
    taxableAmount: _cents(taxableAmount),
    totalTax: _cents(totalTax),
    grandTotal: _cents(grandTotal),
  );
}

/// Rounds to two decimal places, the smallest unit any of this is billed in.
double _cents(double value) => (value * 100).roundToDouble() / 100;
