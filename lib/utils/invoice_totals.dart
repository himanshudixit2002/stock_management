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
      totalTax += taxableAfterLineDiscount * line.lineTaxRate / 100;
    }
  }

  final invoicePct = discountEnabled ? invoiceDiscountPercent.clamp(0, 100) : 0.0;
  final invoiceFlat = discountEnabled ? invoiceDiscountAmount : 0.0;
  final invoiceDiscount =
      (subtotal - totalLineDiscount) * invoicePct / 100 + invoiceFlat;

  final totalDiscount = totalLineDiscount + invoiceDiscount;
  final taxableAmount = subtotal - totalDiscount;
  if (taxEnabled && invoicePct > 0) {
    totalTax *= (1 - invoicePct / 100);
  } else if (!taxEnabled) {
    totalTax = 0;
  }
  final grandTotal = taxableAmount + totalTax;

  return InvoiceTotals(
    subtotal: subtotal,
    lineDiscount: totalLineDiscount,
    invoiceDiscount: invoiceDiscount,
    totalDiscount: totalDiscount,
    taxableAmount: taxableAmount,
    totalTax: totalTax,
    grandTotal: grandTotal,
  );
}
