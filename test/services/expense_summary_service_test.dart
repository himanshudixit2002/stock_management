import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/expense_model.dart';
import 'package:stock_management/services/expense_summary_service.dart';

void main() {
  ExpenseModel expense({
    required double amount,
    double tax = 0,
    ExpenseCategory category = ExpenseCategory.rent,
    String customCategory = '',
    ExpenseStatus status = ExpenseStatus.paid,
    DateTime? date,
  }) {
    final when = date ?? DateTime(2026, 3, 10);
    return ExpenseModel(
      id: 'e${when.microsecondsSinceEpoch}$amount',
      amount: amount,
      taxAmount: tax,
      category: category,
      customCategory: customCategory,
      status: status,
      expenseDate: when,
      createdAt: when,
      updatedAt: when,
    );
  }

  group('period scoping', () {
    test('the window is half-open: start is in, end is out', () {
      final expenses = [
        expense(amount: 100, date: DateTime(2026, 3, 1)),
        expense(amount: 200, date: DateTime(2026, 3, 31, 23, 59)),
        expense(amount: 400, date: DateTime(2026, 4, 1)),
        expense(amount: 800, date: DateTime(2026, 2, 28)),
      ];
      final summary = ExpenseSummaryService.summarise(
        expenses,
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 4, 1),
      );
      expect(summary.total, 300);
      expect(summary.count, 2);
    });

    test('unbounded when no dates are given', () {
      final summary = ExpenseSummaryService.summarise([
        expense(amount: 100, date: DateTime(2020, 1, 1)),
        expense(amount: 100, date: DateTime(2030, 1, 1)),
      ]);
      expect(summary.total, 200);
    });
  });

  group('totals', () {
    test('total is the amount plus its tax, netCost excludes the tax', () {
      final summary = ExpenseSummaryService.summarise([
        expense(amount: 1000, tax: 180),
      ]);
      expect(summary.total, 1180);
      expect(summary.taxTotal, 180);
      // Recoverable tax is reclaimed, not spent: a P&L that treated it as cost
      // would understate profit by the whole tax bill.
      expect(summary.netCost, 1000);
    });

    test('paid and unpaid are split', () {
      final summary = ExpenseSummaryService.summarise([
        expense(amount: 100),
        expense(amount: 250, status: ExpenseStatus.unpaid),
      ]);
      expect(summary.paidTotal, 100);
      expect(summary.unpaidTotal, 250);
    });

    test('an empty period reports zeros rather than throwing', () {
      final summary = ExpenseSummaryService.summarise(const []);
      expect(summary.total, 0);
      expect(summary.heads, isEmpty);
      expect(summary.largestHead, isNull);
    });
  });

  group('heads', () {
    test('are ranked by spend and carry their share', () {
      final summary = ExpenseSummaryService.summarise([
        expense(amount: 100, category: ExpenseCategory.utilities),
        expense(amount: 700, category: ExpenseCategory.rent),
        expense(amount: 200, category: ExpenseCategory.salaries),
      ]);
      expect(summary.heads.first.label, 'Rent & premises');
      expect(summary.heads.first.share, closeTo(0.7, 0.0001));
      expect(summary.heads.map((h) => h.total), [700, 200, 100]);
    });

    test('custom heads group case-insensitively', () {
      // Two spellings of one head would silently split a budget line in two.
      final summary = ExpenseSummaryService.summarise([
        expense(
          amount: 100,
          category: ExpenseCategory.other,
          customCategory: 'Cleaning',
        ),
        expense(
          amount: 50,
          category: ExpenseCategory.other,
          customCategory: 'cleaning ',
        ),
      ]);
      expect(summary.heads.length, 1);
      expect(summary.heads.first.total, 150);
      // The label keeps the capitalisation it was first entered with.
      expect(summary.heads.first.label, 'Cleaning');
    });

    test('a custom head is distinct from the plain Other bucket', () {
      final summary = ExpenseSummaryService.summarise([
        expense(amount: 100, category: ExpenseCategory.other),
        expense(
          amount: 50,
          category: ExpenseCategory.other,
          customCategory: 'Licences',
        ),
      ]);
      expect(summary.heads.length, 2);
    });
  });

  group('months', () {
    test('are bucketed oldest first', () {
      final summary = ExpenseSummaryService.summarise([
        expense(amount: 100, date: DateTime(2026, 3, 20)),
        expense(amount: 100, date: DateTime(2026, 1, 5)),
        expense(amount: 100, date: DateTime(2026, 3, 2)),
      ]);
      expect(summary.months.length, 2);
      expect(summary.months.first.month, DateTime(2026, 1));
      expect(summary.months.last.total, 200);
    });
  });

  group('totalForHead', () {
    test('an empty key means every head', () {
      final expenses = [
        expense(amount: 100, category: ExpenseCategory.rent),
        expense(amount: 50, category: ExpenseCategory.travel),
      ];
      expect(
        ExpenseSummaryService.totalForHead(expenses, categoryKey: ''),
        150,
      );
      expect(
        ExpenseSummaryService.totalForHead(expenses, categoryKey: 'travel'),
        50,
      );
    });
  });
}
