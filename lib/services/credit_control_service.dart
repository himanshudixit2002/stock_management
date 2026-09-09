import '../models/customer_model.dart';
import '../models/invoice_model.dart';

/// What credit control says about a customer, right now.
enum CreditVerdict {
  /// Inside the limit, nothing overdue enough to matter.
  ok,

  /// Close to the limit, or carrying something overdue. The sale goes through,
  /// with the reason on screen.
  warning,

  /// Over the limit or on hold. A further credit sale is refused.
  blocked,
}

/// One customer's credit position.
class CreditExposure {
  const CreditExposure({
    required this.customerId,
    required this.customerName,
    required this.creditLimit,
    required this.outstanding,
    required this.overdueAmount,
    required this.oldestOverdueDays,
    required this.openInvoices,
    required this.onHold,
    required this.verdict,
    required this.reason,
  });

  final String customerId;
  final String customerName;

  /// Zero means no limit has been set.
  final double creditLimit;

  final double outstanding;
  final double overdueAmount;

  /// Days past due on the oldest unpaid invoice; zero when nothing is overdue.
  final int oldestOverdueDays;

  final int openInvoices;
  final bool onHold;
  final CreditVerdict verdict;

  /// A sentence a user can act on, empty when the verdict is [CreditVerdict.ok].
  final String reason;

  bool get hasLimit => creditLimit > 0;

  /// Share of the limit used, 0..1+. Null when no limit is set — an unlimited
  /// customer has no utilisation, which is different from being at zero.
  double? get utilisation {
    if (creditLimit <= 0) return null;
    return outstanding / creditLimit;
  }

  /// What is left before the limit bites. Null when there is no limit.
  double? get headroom {
    if (creditLimit <= 0) return null;
    final left = creditLimit - outstanding;
    return left < 0 ? 0 : left;
  }

  double get overLimitBy {
    if (creditLimit <= 0) return 0;
    final over = outstanding - creditLimit;
    return over > 0 ? over : 0;
  }

  bool get isBlocked => verdict == CreditVerdict.blocked;
}

/// The whole book, for the credit control dashboard.
class CreditBook {
  const CreditBook({
    required this.exposures,
    required this.totalOutstanding,
    required this.totalOverdue,
    required this.blockedCount,
    required this.warningCount,
    required this.customersWithLimit,
  });

  /// Every customer carrying a balance or a limit, largest exposure first.
  final List<CreditExposure> exposures;

  final double totalOutstanding;
  final double totalOverdue;
  final int blockedCount;
  final int warningCount;
  final int customersWithLimit;

  List<CreditExposure> get blocked =>
      exposures.where((e) => e.verdict == CreditVerdict.blocked).toList();

  List<CreditExposure> get warnings =>
      exposures.where((e) => e.verdict == CreditVerdict.warning).toList();

  static const CreditBook empty = CreditBook(
    exposures: [],
    totalOutstanding: 0,
    totalOverdue: 0,
    blockedCount: 0,
    warningCount: 0,
    customersWithLimit: 0,
  );
}

/// Decides how much credit a customer is using and whether they may have more.
///
/// Pure and synchronous: it reads the invoices the billing provider already
/// holds, so the exposure shown here is the same balance the statement and the
/// aging report show. Anything else would mean two answers to "how much do they
/// owe", which is the one question credit control exists to answer.
class CreditControlService {
  CreditControlService._();

  /// Utilisation at which a sale still goes through, but says so.
  static const double warnAtUtilisation = 0.85;

  /// Days past due that turn a balance into a warning on its own, limit or not.
  static const int warnOverdueDays = 30;

  /// Days past due that block further credit even inside the limit. An account
  /// two months late is not a credit risk in theory, it is one in fact.
  static const int blockOverdueDays = 60;

  static bool _countsTowardsBalance(InvoiceModel invoice) =>
      invoice.isSales && !invoice.isCancelled && !invoice.isDraft;

  /// One customer's position against their limit.
  static CreditExposure exposureFor({
    required CustomerModel customer,
    required List<InvoiceModel> invoices,
    DateTime? asOf,
  }) {
    final now = asOf ?? DateTime.now();
    var outstanding = 0.0;
    var overdueAmount = 0.0;
    var oldestOverdueDays = 0;
    var openInvoices = 0;

    for (final invoice in invoices) {
      if (invoice.customerId != customer.id) continue;
      if (!_countsTowardsBalance(invoice)) continue;
      final due = invoice.outstanding;
      if (due <= 0) continue;
      outstanding += due;
      openInvoices++;
      if (invoice.dueDate.isBefore(now)) {
        overdueAmount += due;
        final days = now.difference(invoice.dueDate).inDays;
        if (days > oldestOverdueDays) oldestOverdueDays = days;
      }
    }

    final limit = customer.creditLimit;
    var verdict = CreditVerdict.ok;
    var reason = '';

    if (customer.creditHold) {
      verdict = CreditVerdict.blocked;
      reason = 'This account is on credit hold.';
    } else if (limit > 0 && outstanding >= limit) {
      verdict = CreditVerdict.blocked;
      reason =
          'Over the credit limit by ${(outstanding - limit).toStringAsFixed(2)}.';
    } else if (oldestOverdueDays >= blockOverdueDays) {
      verdict = CreditVerdict.blocked;
      reason = '$oldestOverdueDays days past due on an open invoice.';
    } else if (limit > 0 && outstanding >= limit * warnAtUtilisation) {
      verdict = CreditVerdict.warning;
      final left = limit - outstanding;
      reason = 'Only ${left.toStringAsFixed(2)} of credit left.';
    } else if (oldestOverdueDays >= warnOverdueDays) {
      verdict = CreditVerdict.warning;
      reason = '$oldestOverdueDays days past due on an open invoice.';
    }

    return CreditExposure(
      customerId: customer.id,
      customerName: customer.name,
      creditLimit: limit,
      outstanding: outstanding,
      overdueAmount: overdueAmount,
      oldestOverdueDays: oldestOverdueDays,
      openInvoices: openInvoices,
      onHold: customer.creditHold,
      verdict: verdict,
      reason: reason,
    );
  }

  /// Would adding [amount] of new credit break this customer's limit?
  ///
  /// Separate from [exposureFor] because the two questions differ: a customer
  /// exactly at their limit is fine until somebody tries to sell them more.
  static CreditExposure exposureAfterSale({
    required CustomerModel customer,
    required List<InvoiceModel> invoices,
    required double amount,
    DateTime? asOf,
  }) {
    final current = exposureFor(
      customer: customer,
      invoices: invoices,
      asOf: asOf,
    );
    if (amount <= 0) return current;

    final projected = current.outstanding + amount;
    final limit = current.creditLimit;

    var verdict = current.verdict;
    var reason = current.reason;

    if (!customer.creditHold &&
        limit > 0 &&
        projected > limit &&
        verdict != CreditVerdict.blocked) {
      verdict = CreditVerdict.blocked;
      reason =
          'This sale would take the balance ${(projected - limit).toStringAsFixed(2)} '
          'over the ${limit.toStringAsFixed(2)} limit.';
    }

    return CreditExposure(
      customerId: current.customerId,
      customerName: current.customerName,
      creditLimit: limit,
      outstanding: projected,
      overdueAmount: current.overdueAmount,
      oldestOverdueDays: current.oldestOverdueDays,
      openInvoices: current.openInvoices,
      onHold: current.onHold,
      verdict: verdict,
      reason: reason,
    );
  }

  /// The whole customer book, ranked by exposure.
  ///
  /// Customers with neither a balance nor a limit are left out: a list of every
  /// customer who has never bought on credit is not a credit report.
  static CreditBook book({
    required List<CustomerModel> customers,
    required List<InvoiceModel> invoices,
    DateTime? asOf,
  }) {
    final exposures = <CreditExposure>[];
    var totalOutstanding = 0.0;
    var totalOverdue = 0.0;
    var blocked = 0;
    var warnings = 0;
    var withLimit = 0;

    for (final customer in customers) {
      final exposure = exposureFor(
        customer: customer,
        invoices: invoices,
        asOf: asOf,
      );
      if (exposure.creditLimit > 0) withLimit++;
      if (exposure.outstanding <= 0 &&
          exposure.creditLimit <= 0 &&
          !exposure.onHold) {
        continue;
      }
      exposures.add(exposure);
      totalOutstanding += exposure.outstanding;
      totalOverdue += exposure.overdueAmount;
      if (exposure.verdict == CreditVerdict.blocked) blocked++;
      if (exposure.verdict == CreditVerdict.warning) warnings++;
    }

    exposures.sort((a, b) {
      // Blocked accounts first, then by how much money is at risk.
      if (a.isBlocked != b.isBlocked) return a.isBlocked ? -1 : 1;
      return b.outstanding.compareTo(a.outstanding);
    });

    return CreditBook(
      exposures: exposures,
      totalOutstanding: totalOutstanding,
      totalOverdue: totalOverdue,
      blockedCount: blocked,
      warningCount: warnings,
      customersWithLimit: withLimit,
    );
  }

  static String verdictLabel(CreditVerdict verdict) => switch (verdict) {
    CreditVerdict.ok => 'Within terms',
    CreditVerdict.warning => 'Watch',
    CreditVerdict.blocked => 'Blocked',
  };
}
