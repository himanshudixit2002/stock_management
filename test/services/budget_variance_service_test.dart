import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/budget_model.dart';
import 'package:stock_management/models/expense_model.dart';
import 'package:stock_management/models/invoice_model.dart';
import 'package:stock_management/models/purchase_order_model.dart';
import 'package:stock_management/services/budget_variance_service.dart';

void main() {
  final march = DateTime(2026, 3, 1);

  BudgetModel budget({
    BudgetPeriod period = BudgetPeriod.month,
    required List<BudgetLine> lines,
    DateTime? start,
  }) => BudgetModel(
    id: 'b1',
    name: 'March plan',
    period: period,
    periodStart: start ?? march,
    lines: lines,
    createdAt: march,
    updatedAt: march,
  );

  InvoiceModel invoice({
    required double total,
    double tax = 0,
    DateTime? date,
    InvoiceStatus status = InvoiceStatus.sent,
    InvoiceType type = InvoiceType.sales,
  }) {
    final when = date ?? DateTime(2026, 3, 10);
    return InvoiceModel(
      id: 'i${when.microsecondsSinceEpoch}$total',
      invoiceType: type,
      invoiceNumber: 'INV',
      customerId: 'c1',
      status: status,
      grandTotal: total,
      totalTax: tax,
      amountDue: total,
      invoiceDate: when,
      dueDate: when,
      createdAt: when,
      updatedAt: when,
    );
  }

  PurchaseOrderModel purchase({
    required double total,
    DateTime? date,
    POStatus status = POStatus.sent,
  }) {
    final when = date ?? DateTime(2026, 3, 12);
    return PurchaseOrderModel(
      id: 'po${when.microsecondsSinceEpoch}$total',
      vendorId: 'v1',
      status: status,
      totalAmount: total,
      expectedDate: when,
      createdAt: when,
      updatedAt: when,
    );
  }

  ExpenseModel expense({
    required double amount,
    ExpenseCategory category = ExpenseCategory.rent,
    DateTime? date,
  }) {
    final when = date ?? DateTime(2026, 3, 5);
    return ExpenseModel(
      id: 'e${when.microsecondsSinceEpoch}$amount$category',
      amount: amount,
      category: category,
      expenseDate: when,
      createdAt: when,
      updatedAt: when,
    );
  }

  group('actuals', () {
    test('revenue excludes tax collected for the state', () {
      final report = BudgetVarianceService.analyse(
        budget: budget(
          lines: const [
            BudgetLine(type: BudgetLineType.revenue, amount: 100000),
          ],
        ),
        invoices: [invoice(total: 11800, tax: 1800)],
        purchaseOrders: const [],
        expenses: const [],
        asOf: DateTime(2026, 3, 31),
      );
      expect(report.revenueActual, 10000);
    });

    test('purchases are counted when the order was raised', () {
      final report = BudgetVarianceService.analyse(
        budget: budget(
          lines: const [
            BudgetLine(type: BudgetLineType.purchases, amount: 50000),
          ],
        ),
        invoices: const [],
        purchaseOrders: [
          purchase(total: 20000),
          purchase(total: 5000, status: POStatus.cancelled),
          purchase(total: 9999, date: DateTime(2026, 4, 2)),
        ],
        expenses: const [],
        asOf: DateTime(2026, 3, 31),
      );
      expect(report.spendActual, 20000);
    });

    test('an expense line with no head covers every head', () {
      final report = BudgetVarianceService.analyse(
        budget: budget(
          lines: const [
            BudgetLine(type: BudgetLineType.expense, amount: 10000),
          ],
        ),
        invoices: const [],
        purchaseOrders: const [],
        expenses: [
          expense(amount: 3000),
          expense(amount: 2000, category: ExpenseCategory.travel),
        ],
        asOf: DateTime(2026, 3, 31),
      );
      expect(report.spendActual, 5000);
    });

    test('a head-specific line only counts that head', () {
      final report = BudgetVarianceService.analyse(
        budget: budget(
          lines: const [
            BudgetLine(
              type: BudgetLineType.expense,
              categoryKey: 'rent',
              amount: 10000,
            ),
          ],
        ),
        invoices: const [],
        purchaseOrders: const [],
        expenses: [
          expense(amount: 3000),
          expense(amount: 2000, category: ExpenseCategory.travel),
        ],
        asOf: DateTime(2026, 3, 31),
      );
      expect(report.spendActual, 3000);
    });

    test('nothing outside the period counts', () {
      final report = BudgetVarianceService.analyse(
        budget: budget(
          lines: const [
            BudgetLine(type: BudgetLineType.revenue, amount: 1000),
            BudgetLine(type: BudgetLineType.expense, amount: 1000),
          ],
        ),
        invoices: [invoice(total: 5000, date: DateTime(2026, 2, 28))],
        purchaseOrders: const [],
        expenses: [expense(amount: 5000, date: DateTime(2026, 4, 1))],
        asOf: DateTime(2026, 3, 31),
      );
      expect(report.revenueActual, 0);
      expect(report.spendActual, 0);
    });
  });

  group('variance signing', () {
    test('positive is good on both kinds of line', () {
      final report = BudgetVarianceService.analyse(
        budget: budget(
          lines: const [
            BudgetLine(type: BudgetLineType.revenue, amount: 10000),
            BudgetLine(type: BudgetLineType.expense, amount: 5000),
          ],
        ),
        invoices: [invoice(total: 12000)],
        purchaseOrders: const [],
        expenses: [expense(amount: 3000)],
        asOf: DateTime(2026, 3, 31),
      );
      // Beat the revenue target by 2000, came in 2000 under on spend.
      expect(report.lines.first.variance, 2000);
      expect(report.lines.last.variance, 2000);
      expect(report.netVariance, 4000);
    });
  });

  group('pace', () {
    test('a line half spent in the first week is ahead of pace', () {
      final report = BudgetVarianceService.analyse(
        budget: budget(
          lines: const [
            BudgetLine(type: BudgetLineType.expense, amount: 10000),
          ],
        ),
        invoices: const [],
        purchaseOrders: const [],
        expenses: [expense(amount: 5000, date: DateTime(2026, 3, 2))],
        asOf: DateTime(2026, 3, 5),
      );
      final line = report.lines.single;
      expect(line.isOverBudget, isFalse);
      expect(line.isAheadOfPace, isTrue);
      expect(line.usage, closeTo(0.5, 0.001));
      expect(line.expectedByNow, lessThan(2000));
      expect(report.aheadOfPace, hasLength(1));
    });

    test('the same spend late in the period is not', () {
      final report = BudgetVarianceService.analyse(
        budget: budget(
          lines: const [
            BudgetLine(type: BudgetLineType.expense, amount: 10000),
          ],
        ),
        invoices: const [],
        purchaseOrders: const [],
        expenses: [expense(amount: 5000, date: DateTime(2026, 3, 2))],
        asOf: DateTime(2026, 3, 28),
      );
      expect(report.lines.single.isAheadOfPace, isFalse);
      expect(report.hasProblems, isFalse);
    });

    test('over budget is over budget whatever the pace', () {
      final report = BudgetVarianceService.analyse(
        budget: budget(
          lines: const [
            BudgetLine(type: BudgetLineType.expense, amount: 1000),
          ],
        ),
        invoices: const [],
        purchaseOrders: const [],
        expenses: [expense(amount: 1500)],
        asOf: DateTime(2026, 3, 31),
      );
      expect(report.lines.single.isOverBudget, isTrue);
      expect(report.overBudget, hasLength(1));
      expect(report.spendUsage, closeTo(1.5, 0.001));
    });

    test('a line with no budget has no usage percentage', () {
      final report = BudgetVarianceService.analyse(
        budget: budget(
          lines: const [BudgetLine(type: BudgetLineType.expense)],
        ),
        invoices: const [],
        purchaseOrders: const [],
        expenses: [expense(amount: 500)],
        asOf: DateTime(2026, 3, 15),
      );
      expect(report.lines.single.usage, isNull);
      expect(report.lines.single.isOverBudget, isFalse);
    });
  });

  group('periods', () {
    test('a quarter starts on the quarter, whatever day was picked', () {
      expect(
        BudgetModel.normalizeStart(DateTime(2026, 8, 17), BudgetPeriod.quarter),
        DateTime(2026, 7, 1),
      );
      expect(
        BudgetModel.normalizeStart(DateTime(2026, 8, 17), BudgetPeriod.year),
        DateTime(2026, 1, 1),
      );
      expect(
        BudgetModel.normalizeStart(DateTime(2026, 8, 17), BudgetPeriod.month),
        DateTime(2026, 8, 1),
      );
    });

    test('period labels read the way a user would say them', () {
      expect(
        budget(
          period: BudgetPeriod.quarter,
          start: DateTime(2026, 7, 1),
          lines: const [],
        ).periodLabel,
        'Q3 2026',
      );
      expect(budget(lines: const []).periodLabel, 'Mar 2026');
    });

    test('a quarterly budget covers three months', () {
      final q = budget(
        period: BudgetPeriod.quarter,
        start: DateTime(2026, 7, 1),
        lines: const [],
      );
      expect(q.periodEnd, DateTime(2026, 10, 1));
      expect(q.covers(DateTime(2026, 9, 30)), isTrue);
      expect(q.covers(DateTime(2026, 10, 1)), isFalse);
    });
  });
}
