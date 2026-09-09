import '../models/invoice_model.dart';
import '../models/register_session_model.dart';

/// What a shift took, and what the drawer should therefore hold.
class RegisterTally {
  const RegisterTally({
    required this.openingFloat,
    required this.cashTakings,
    required this.otherTakings,
    required this.creditSales,
    required this.salesTotal,
    required this.refundTotal,
    required this.invoiceCount,
    required this.takingsByMethod,
    required this.movementTotal,
    required this.expectedCash,
  });

  final double openingFloat;

  /// Payments taken in cash, net of cash refunds.
  final double cashTakings;

  /// Payments taken by every other method.
  final double otherTakings;

  /// Rung up but not paid — a credit sale leaves the drawer alone.
  final double creditSales;

  /// Face value of the shift's sales documents.
  final double salesTotal;

  /// Value refunded through credit notes rung up on this shift.
  final double refundTotal;

  final int invoiceCount;

  /// Takings keyed by payment method, in the spelling the tills used.
  final Map<String, double> takingsByMethod;

  /// Net of drops and payouts.
  final double movementTotal;

  /// Float + cash takings + movements. What should be in the drawer.
  final double expectedCash;

  double get totalTakings => cashTakings + otherTakings;

  /// Counted minus expected: negative is short, positive is over.
  double varianceFor(double countedCash) => countedCash - expectedCash;

  static const RegisterTally empty = RegisterTally(
    openingFloat: 0,
    cashTakings: 0,
    otherTakings: 0,
    creditSales: 0,
    salesTotal: 0,
    refundTotal: 0,
    invoiceCount: 0,
    takingsByMethod: {},
    movementTotal: 0,
    expectedCash: 0,
  );
}

/// Turns a shift's invoices into the figures a cash-up needs.
///
/// Pure and synchronous, and deliberately so: the close screen shows the
/// operator's counted figure first and only then reveals these, so the numbers
/// must be derivable from data already on the device rather than fetched at the
/// moment of reveal.
class RegisterTallyService {
  RegisterTallyService._();

  /// Payment methods that put notes in the drawer.
  ///
  /// Matched loosely on purpose: tills are configured by hand, and "Cash",
  /// "CASH " and "cash on hand" are the same thing to a drawer. An empty method
  /// counts as cash, because that is what an old POS sale with no method
  /// recorded actually was.
  static bool isCashMethod(String method) {
    final normalised = method.trim().toLowerCase();
    if (normalised.isEmpty) return true;
    return normalised.contains('cash');
  }

  /// Sales documents stamped with [sessionId].
  static List<InvoiceModel> invoicesForSession(
    List<InvoiceModel> invoices,
    String sessionId,
  ) {
    if (sessionId.isEmpty) return const [];
    return invoices.where((i) => i.registerSessionId == sessionId).toList();
  }

  static RegisterTally tally({
    required RegisterSessionModel session,
    required List<InvoiceModel> invoices,
  }) {
    final scoped = session.id.isEmpty
        ? const <InvoiceModel>[]
        : invoicesForSession(invoices, session.id);

    var cashTakings = 0.0;
    var otherTakings = 0.0;
    var creditSales = 0.0;
    var salesTotal = 0.0;
    var refundTotal = 0.0;
    final byMethod = <String, double>{};

    for (final invoice in scoped) {
      if (invoice.isCancelled) continue;
      // A credit note rung up at the till is money going the other way, so its
      // payments are refunds out of the same drawer.
      final sign = invoice.isCreditNote ? -1.0 : 1.0;

      if (invoice.isCreditNote) {
        refundTotal += invoice.grandTotal;
      } else {
        salesTotal += invoice.grandTotal;
        creditSales += invoice.outstanding;
      }

      for (final payment in invoice.payments) {
        final amount = payment.amount * sign;
        final method = payment.method.trim().isEmpty
            ? 'cash'
            : payment.method.trim().toLowerCase();
        byMethod[method] = (byMethod[method] ?? 0) + amount;
        if (isCashMethod(payment.method)) {
          cashTakings += amount;
        } else {
          otherTakings += amount;
        }
      }
    }

    final movementTotal = session.movementTotal;

    return RegisterTally(
      openingFloat: session.openingFloat,
      cashTakings: cashTakings,
      otherTakings: otherTakings,
      creditSales: creditSales,
      salesTotal: salesTotal,
      refundTotal: refundTotal,
      invoiceCount: scoped.where((i) => !i.isCancelled).length,
      takingsByMethod: byMethod,
      movementTotal: movementTotal,
      expectedCash: session.openingFloat + cashTakings + movementTotal,
    );
  }
}
