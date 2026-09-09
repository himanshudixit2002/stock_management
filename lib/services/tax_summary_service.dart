import '../models/invoice_model.dart';

/// A period the tax summary can be run for.
enum TaxPeriodKind { month, quarter, financialYear, custom }

/// A date range plus the label it is shown under.
class TaxPeriod {
  const TaxPeriod({
    required this.start,
    required this.end,
    required this.label,
    this.kind = TaxPeriodKind.custom,
  });

  /// Inclusive start, at midnight.
  final DateTime start;

  /// Exclusive end. Held exclusive so an invoice timed 23:59:59 on the last day
  /// of the period is inside it — a half-open range has no "last microsecond"
  /// gap for a document to fall through.
  final DateTime end;

  final String label;
  final TaxPeriodKind kind;

  bool contains(DateTime when) => !when.isBefore(start) && when.isBefore(end);

  /// The calendar month containing [anchor].
  factory TaxPeriod.month(DateTime anchor) {
    final start = DateTime(anchor.year, anchor.month, 1);
    final end = DateTime(anchor.year, anchor.month + 1, 1);
    return TaxPeriod(
      start: start,
      end: end,
      label: '${_monthNames[start.month - 1]} ${start.year}',
      kind: TaxPeriodKind.month,
    );
  }

  /// The calendar quarter containing [anchor].
  factory TaxPeriod.quarter(DateTime anchor) {
    final firstMonth = ((anchor.month - 1) ~/ 3) * 3 + 1;
    final start = DateTime(anchor.year, firstMonth, 1);
    final end = DateTime(anchor.year, firstMonth + 3, 1);
    return TaxPeriod(
      start: start,
      end: end,
      label: 'Q${(firstMonth - 1) ~/ 3 + 1} ${start.year}',
      kind: TaxPeriodKind.quarter,
    );
  }

  /// The Indian financial year (1 April – 31 March) containing [anchor].
  ///
  /// April rather than January because that is the year this app's tax figures
  /// are actually filed against.
  factory TaxPeriod.financialYear(DateTime anchor) {
    final startYear = anchor.month >= 4 ? anchor.year : anchor.year - 1;
    final start = DateTime(startYear, 4, 1);
    final end = DateTime(startYear + 1, 4, 1);
    final shortEnd = ((startYear + 1) % 100).toString().padLeft(2, '0');
    return TaxPeriod(
      start: start,
      end: end,
      label: 'FY $startYear-$shortEnd',
      kind: TaxPeriodKind.financialYear,
    );
  }

  static const List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// This period shifted by [steps] whole periods (negative goes back).
  TaxPeriod shift(int steps) {
    if (steps == 0) return this;
    switch (kind) {
      case TaxPeriodKind.month:
        return TaxPeriod.month(DateTime(start.year, start.month + steps, 1));
      case TaxPeriodKind.quarter:
        return TaxPeriod.quarter(
          DateTime(start.year, start.month + steps * 3, 1),
        );
      case TaxPeriodKind.financialYear:
        return TaxPeriod.financialYear(DateTime(start.year + steps, 4, 1));
      case TaxPeriodKind.custom:
        return this;
    }
  }
}

/// One tax rate's contribution within a period.
class TaxSlab {
  const TaxSlab({
    required this.rate,
    required this.taxableValue,
    required this.taxAmount,
    required this.documentCount,
  });

  final double rate;
  final double taxableValue;
  final double taxAmount;
  final int documentCount;

  TaxSlab _plus(double taxable, double tax) => TaxSlab(
    rate: rate,
    taxableValue: taxableValue + taxable,
    taxAmount: taxAmount + tax,
    documentCount: documentCount + 1,
  );
}

/// One side of the return: sales (output) or purchases (input).
class TaxSide {
  const TaxSide({
    required this.slabs,
    required this.taxableValue,
    required this.taxAmount,
    required this.documentCount,
  });

  /// Rate slabs, highest rate first.
  final List<TaxSlab> slabs;
  final double taxableValue;
  final double taxAmount;
  final int documentCount;

  double get total => taxableValue + taxAmount;

  static const TaxSide empty = TaxSide(
    slabs: [],
    taxableValue: 0,
    taxAmount: 0,
    documentCount: 0,
  );
}

/// Output tax, input tax, credits, and the net position between them.
class TaxSummary {
  const TaxSummary({
    required this.period,
    required this.output,
    required this.input,
    required this.credits,
    required this.excludedCount,
  });

  final TaxPeriod period;

  /// Sales invoices.
  final TaxSide output;

  /// Purchase invoices.
  final TaxSide input;

  /// Credit notes, which reduce output tax.
  final TaxSide credits;

  /// Documents in the period that were skipped: drafts and cancellations owe
  /// nothing, so counting them would overstate the liability. Surfaced rather
  /// than silently dropped so the figure can be reconciled against the invoice
  /// list.
  final int excludedCount;

  /// Output tax less credits — what was actually collected.
  double get netOutputTax => output.taxAmount - credits.taxAmount;

  /// What is owed after offsetting input tax. Negative means a refund position.
  double get netPayable => netOutputTax - input.taxAmount;

  bool get isEmpty =>
      output.documentCount == 0 &&
      input.documentCount == 0 &&
      credits.documentCount == 0;
}

/// Builds a period tax summary from invoices.
///
/// Pure and synchronous: it takes the documents the billing provider already
/// streams rather than querying, so it can be unit-tested and so its numbers
/// are the same ones the invoice list shows.
class TaxSummaryService {
  TaxSummaryService._();

  /// Invoice statuses that owe no tax. A draft is not yet a claim and a
  /// cancelled document is void.
  static const Set<InvoiceStatus> _excludedStatuses = {
    InvoiceStatus.draft,
    InvoiceStatus.cancelled,
  };

  static TaxSummary build(List<InvoiceModel> invoices, TaxPeriod period) {
    final output = <double, TaxSlab>{};
    final input = <double, TaxSlab>{};
    final credits = <double, TaxSlab>{};
    var outputDocs = 0;
    var inputDocs = 0;
    var creditDocs = 0;
    var excluded = 0;

    for (final invoice in invoices) {
      if (!period.contains(invoice.invoiceDate)) continue;
      if (_excludedStatuses.contains(invoice.status)) {
        excluded++;
        continue;
      }

      final lines = _slabLinesOf(invoice);
      if (lines.isEmpty) continue;

      final target = switch (invoice.invoiceType) {
        InvoiceType.sales => output,
        InvoiceType.purchase => input,
        InvoiceType.creditNote => credits,
      };
      switch (invoice.invoiceType) {
        case InvoiceType.sales:
          outputDocs++;
        case InvoiceType.purchase:
          inputDocs++;
        case InvoiceType.creditNote:
          creditDocs++;
      }

      // One entry per rate per invoice, so every rate this document touches
      // counts it exactly once.
      for (final entry in lines.entries) {
        final rate = entry.key;
        final existing =
            target[rate] ??
            TaxSlab(
              rate: rate,
              taxableValue: 0,
              taxAmount: 0,
              documentCount: 0,
            );
        target[rate] = existing._plus(entry.value.taxable, entry.value.tax);
      }
    }

    return TaxSummary(
      period: period,
      output: _sideOf(output, outputDocs),
      input: _sideOf(input, inputDocs),
      credits: _sideOf(credits, creditDocs),
      excludedCount: excluded,
    );
  }

  static TaxSide _sideOf(Map<double, TaxSlab> slabs, int documentCount) {
    if (slabs.isEmpty) return TaxSide.empty;
    final list = slabs.values.toList()
      ..sort((a, b) => b.rate.compareTo(a.rate));
    return TaxSide(
      slabs: list,
      taxableValue: list.fold(0.0, (acc, s) => acc + s.taxableValue),
      taxAmount: list.fold(0.0, (acc, s) => acc + s.taxAmount),
      documentCount: documentCount,
    );
  }

  /// Taxable value and tax per rate for one invoice.
  ///
  /// Mirrors [calculateInvoiceTotals] exactly, including the step that scales
  /// tax down by the invoice-level discount. Recomputing the split from the
  /// items and then applying the same scale is what keeps the slab totals
  /// adding up to the invoice's own stored `totalTax` — a report that
  /// disagreed with the document it came from would be worse than no report.
  static Map<double, _SlabLine> _slabLinesOf(InvoiceModel invoice) {
    final out = <double, _SlabLine>{};
    var preDiscountTaxable = 0.0;

    for (final item in invoice.items) {
      if (item.quantity <= 0) continue;
      final lineSubtotal = item.quantity * item.unitPrice;
      final discount = lineSubtotal * item.discountPercent.clamp(0, 100) / 100;
      final taxable = lineSubtotal - discount;
      if (taxable <= 0) continue;
      preDiscountTaxable += taxable;
      final rate = item.taxRate < 0 ? 0.0 : item.taxRate;
      final existing = out[rate];
      out[rate] = _SlabLine(
        taxable: (existing?.taxable ?? 0) + taxable,
        tax: 0,
      );
    }

    if (out.isEmpty || preDiscountTaxable <= 0) return const {};

    // The invoice-level discount reduces every line's taxable value pro rata.
    // Read from the stored fields so a document whose totals were computed
    // under different settings still reconciles to what it says it is.
    final afterInvoiceDiscount = preDiscountTaxable - invoice.invoiceDiscount;
    final scale = afterInvoiceDiscount <= 0
        ? 0.0
        : afterInvoiceDiscount / preDiscountTaxable;

    return out.map((rate, line) {
      final taxable = line.taxable * scale;
      return MapEntry(rate, _SlabLine(taxable: taxable, tax: taxable * rate / 100));
    });
  }
}

class _SlabLine {
  const _SlabLine({required this.taxable, required this.tax});

  final double taxable;
  final double tax;
}
