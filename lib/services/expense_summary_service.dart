import '../models/expense_model.dart';

/// One expense head, totalled.
class ExpenseHeadTotal {
  const ExpenseHeadTotal({
    required this.key,
    required this.label,
    required this.total,
    required this.count,
    required this.share,
  });

  /// [ExpenseModel.categoryKey] — stable across spellings of a custom head.
  final String key;
  final String label;
  final double total;
  final int count;

  /// This head as a fraction of the period's spend, 0..1.
  final double share;
}

/// One month of spend, for the trend strip.
class ExpenseMonthTotal {
  const ExpenseMonthTotal({
    required this.month,
    required this.total,
    required this.count,
  });

  /// First day of the month.
  final DateTime month;
  final double total;
  final int count;
}

/// Operating spend over a period, broken down.
class ExpenseSummary {
  const ExpenseSummary({
    required this.from,
    required this.to,
    required this.total,
    required this.taxTotal,
    required this.paidTotal,
    required this.unpaidTotal,
    required this.count,
    required this.heads,
    required this.months,
  });

  final DateTime? from;

  /// Exclusive.
  final DateTime? to;

  /// Everything that left, tax included.
  final double total;

  /// The recoverable tax component of [total], which the P&L must not treat as
  /// a cost twice once it is claimed back.
  final double taxTotal;

  final double paidTotal;
  final double unpaidTotal;
  final int count;

  /// Heads, largest first.
  final List<ExpenseHeadTotal> heads;

  /// Months, oldest first.
  final List<ExpenseMonthTotal> months;

  /// Cost net of recoverable tax — the figure the profit line should use.
  double get netCost => total - taxTotal;

  ExpenseHeadTotal? get largestHead => heads.isEmpty ? null : heads.first;

  static const ExpenseSummary empty = ExpenseSummary(
    from: null,
    to: null,
    total: 0,
    taxTotal: 0,
    paidTotal: 0,
    unpaidTotal: 0,
    count: 0,
    heads: [],
    months: [],
  );
}

/// Totals operating expenses by head and by month.
///
/// Pure and synchronous: it takes the list the provider already holds, so the
/// numbers here, on the expense screen and in the Profit & Loss report are the
/// same numbers, and it can be unit-tested without Firestore.
class ExpenseSummaryService {
  ExpenseSummaryService._();

  /// Expenses dated in `[from, to)`. Null bounds mean unbounded.
  static List<ExpenseModel> inPeriod(
    List<ExpenseModel> expenses, {
    DateTime? from,
    DateTime? to,
  }) {
    return expenses.where((e) {
      if (from != null && e.expenseDate.isBefore(from)) return false;
      if (to != null && !e.expenseDate.isBefore(to)) return false;
      return true;
    }).toList();
  }

  static ExpenseSummary summarise(
    List<ExpenseModel> expenses, {
    DateTime? from,
    DateTime? to,
  }) {
    final scoped = inPeriod(expenses, from: from, to: to);
    if (scoped.isEmpty) {
      return const ExpenseSummary(
        from: null,
        to: null,
        total: 0,
        taxTotal: 0,
        paidTotal: 0,
        unpaidTotal: 0,
        count: 0,
        heads: [],
        months: [],
      );
    }

    var total = 0.0;
    var taxTotal = 0.0;
    var paidTotal = 0.0;
    var unpaidTotal = 0.0;

    final headTotals = <String, double>{};
    final headCounts = <String, int>{};
    final headLabels = <String, String>{};
    final monthTotals = <DateTime, double>{};
    final monthCounts = <DateTime, int>{};

    for (final expense in scoped) {
      final value = expense.total;
      total += value;
      taxTotal += expense.taxAmount;
      if (expense.isPaid) {
        paidTotal += value;
      } else {
        unpaidTotal += value;
      }

      final key = expense.categoryKey;
      headTotals[key] = (headTotals[key] ?? 0) + value;
      headCounts[key] = (headCounts[key] ?? 0) + 1;
      // First label wins, so a head keeps the capitalisation it was first
      // entered with rather than flickering between two spellings.
      headLabels.putIfAbsent(key, () => expense.categoryLabel);

      final month = DateTime(
        expense.expenseDate.year,
        expense.expenseDate.month,
      );
      monthTotals[month] = (monthTotals[month] ?? 0) + value;
      monthCounts[month] = (monthCounts[month] ?? 0) + 1;
    }

    final heads =
        headTotals.entries
            .map(
              (e) => ExpenseHeadTotal(
                key: e.key,
                label: headLabels[e.key] ?? e.key,
                total: e.value,
                count: headCounts[e.key] ?? 0,
                share: total <= 0 ? 0 : e.value / total,
              ),
            )
            .toList()
          ..sort((a, b) => b.total.compareTo(a.total));

    final months =
        monthTotals.entries
            .map(
              (e) => ExpenseMonthTotal(
                month: e.key,
                total: e.value,
                count: monthCounts[e.key] ?? 0,
              ),
            )
            .toList()
          ..sort((a, b) => a.month.compareTo(b.month));

    return ExpenseSummary(
      from: from,
      to: to,
      total: total,
      taxTotal: taxTotal,
      paidTotal: paidTotal,
      unpaidTotal: unpaidTotal,
      count: scoped.length,
      heads: heads,
      months: months,
    );
  }

  /// Total spend under one head over a period, used by budget variance.
  ///
  /// An empty [categoryKey] means every head, which is how a workspace budgets
  /// "operating expenses" as a single line.
  static double totalForHead(
    List<ExpenseModel> expenses, {
    required String categoryKey,
    DateTime? from,
    DateTime? to,
  }) {
    return inPeriod(expenses, from: from, to: to)
        .where((e) => categoryKey.isEmpty || e.categoryKey == categoryKey)
        .fold(0.0, (acc, e) => acc + e.total);
  }
}
