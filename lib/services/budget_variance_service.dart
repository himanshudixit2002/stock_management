import '../models/budget_model.dart';
import '../models/expense_model.dart';
import '../models/invoice_model.dart';
import '../models/purchase_order_model.dart';
import 'expense_summary_service.dart';

/// One budget line against what actually happened.
class BudgetLineVariance {
  const BudgetLineVariance({
    required this.line,
    required this.actual,
    required this.elapsedShare,
  });

  final BudgetLine line;

  /// What the workspace actually earned or spent under this head.
  final double actual;

  /// Share of the period gone, 0..1. Carried on every line so a row can judge
  /// itself without reaching back to the budget.
  final double elapsedShare;

  double get budget => line.amount;

  /// Signed the way a reader expects: positive is good. Under budget on a spend
  /// line and over target on a revenue line both read as a positive variance.
  double get variance =>
      line.isSpend ? budget - actual : actual - budget;

  /// Share of the budget consumed, 0..1+. Null when nothing was budgeted — a
  /// line with no budget has no percentage, which is different from 0%.
  double? get usage {
    if (budget <= 0) return null;
    return actual / budget;
  }

  /// What should have been spent or earned by now at an even pace.
  double get expectedByNow => budget * elapsedShare;

  /// Spending faster than the period is passing. This is the figure that turns
  /// "60% spent" from a fact into a warning, or leaves it alone.
  bool get isAheadOfPace => line.isSpend && actual > expectedByNow;

  bool get isOverBudget => budget > 0 && line.isSpend && actual > budget;

  /// A revenue line falling behind its own pace.
  bool get isBehindTarget =>
      !line.isSpend && budget > 0 && actual < expectedByNow;

  /// How far past the even pace, as a share of the budget. Zero when on pace.
  double get paceGap {
    if (budget <= 0) return 0;
    final gap = (actual - expectedByNow) / budget;
    return line.isSpend ? (gap > 0 ? gap : 0) : (gap < 0 ? -gap : 0);
  }
}

/// A whole budget, measured.
class BudgetVarianceReport {
  const BudgetVarianceReport({
    required this.budget,
    required this.lines,
    required this.revenueBudget,
    required this.revenueActual,
    required this.spendBudget,
    required this.spendActual,
    required this.elapsedShare,
  });

  final BudgetModel budget;

  /// In the order the budget lists them, spend lines worst-first within type.
  final List<BudgetLineVariance> lines;

  final double revenueBudget;
  final double revenueActual;
  final double spendBudget;
  final double spendActual;
  final double elapsedShare;

  double get plannedNet => revenueBudget - spendBudget;

  double get actualNet => revenueActual - spendActual;

  double get netVariance => actualNet - plannedNet;

  List<BudgetLineVariance> get overBudget =>
      lines.where((l) => l.isOverBudget).toList();

  List<BudgetLineVariance> get aheadOfPace =>
      lines.where((l) => l.isAheadOfPace && !l.isOverBudget).toList();

  bool get hasProblems => overBudget.isNotEmpty || aheadOfPace.isNotEmpty;

  /// Share of total spend budget used, 0..1+.
  double? get spendUsage {
    if (spendBudget <= 0) return null;
    return spendActual / spendBudget;
  }
}

/// Measures a budget against the invoices, orders and expenses already
/// recorded.
///
/// Pure and synchronous. Every actual it reports is drawn from a collection the
/// app already keeps, which is the constraint that shaped [BudgetLineType]: a
/// budget head nothing can measure would report zero forever and look like
/// perfect discipline.
class BudgetVarianceService {
  BudgetVarianceService._();

  /// Sales revenue in `[from, to)`, net of tax.
  ///
  /// Tax collected on behalf of the state was never revenue, and a budget built
  /// on tax-inclusive totals would look met a month early.
  static double revenueIn({
    required List<InvoiceModel> invoices,
    required DateTime from,
    required DateTime to,
  }) {
    var total = 0.0;
    for (final invoice in invoices) {
      if (!invoice.isSales) continue;
      if (invoice.isCancelled || invoice.isDraft) continue;
      final date = invoice.invoiceDate;
      if (date.isBefore(from) || !date.isBefore(to)) continue;
      total += invoice.grandTotal - invoice.totalTax;
    }
    return total;
  }

  /// Purchase commitment in `[from, to)`, by the date the order was raised.
  ///
  /// Raised, not received: a budget is about committing money, and an order
  /// placed in March against the March budget is March's whether or not the
  /// goods turn up in April.
  static double purchasesIn({
    required List<PurchaseOrderModel> orders,
    required DateTime from,
    required DateTime to,
  }) {
    var total = 0.0;
    for (final order in orders) {
      if (order.status == POStatus.cancelled) continue;
      final date = order.createdAt;
      if (date.isBefore(from) || !date.isBefore(to)) continue;
      total += order.totalAmount;
    }
    return total;
  }

  static BudgetVarianceReport analyse({
    required BudgetModel budget,
    required List<InvoiceModel> invoices,
    required List<PurchaseOrderModel> purchaseOrders,
    required List<ExpenseModel> expenses,
    DateTime? asOf,
  }) {
    final from = budget.periodStart;
    final to = budget.periodEnd;
    final now = asOf ?? DateTime.now();

    // The same pace calculation as BudgetModel.elapsedShare, but honouring an
    // explicit [asOf] so a test — or a report run for a past period — is not
    // measured against today.
    double elapsed;
    if (now.isBefore(from)) {
      elapsed = 0;
    } else if (!now.isBefore(to)) {
      elapsed = 1;
    } else {
      final total = to.difference(from).inSeconds;
      elapsed = total <= 0 ? 1 : now.difference(from).inSeconds / total;
    }

    final lines = <BudgetLineVariance>[];
    var revenueBudget = 0.0;
    var revenueActual = 0.0;
    var spendBudget = 0.0;
    var spendActual = 0.0;

    for (final line in budget.lines) {
      final actual = switch (line.type) {
        BudgetLineType.revenue => revenueIn(
          invoices: invoices,
          from: from,
          to: to,
        ),
        BudgetLineType.purchases => purchasesIn(
          orders: purchaseOrders,
          from: from,
          to: to,
        ),
        BudgetLineType.expense => ExpenseSummaryService.totalForHead(
          expenses,
          categoryKey: line.categoryKey,
          from: from,
          to: to,
        ),
      };

      lines.add(
        BudgetLineVariance(line: line, actual: actual, elapsedShare: elapsed),
      );

      if (line.isSpend) {
        spendBudget += line.amount;
        spendActual += actual;
      } else {
        revenueBudget += line.amount;
        revenueActual += actual;
      }
    }

    return BudgetVarianceReport(
      budget: budget,
      lines: lines,
      revenueBudget: revenueBudget,
      revenueActual: revenueActual,
      spendBudget: spendBudget,
      spendActual: spendActual,
      elapsedShare: elapsed,
    );
  }
}
