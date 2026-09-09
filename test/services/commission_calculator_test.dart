import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/commission_plan_model.dart';
import 'package:stock_management/models/invoice_model.dart';
import 'package:stock_management/models/product_model.dart';
import 'package:stock_management/services/commission_calculator.dart';

void main() {
  final march = DateTime(2026, 3, 10);
  final from = DateTime(2026, 3, 1);
  final to = DateTime(2026, 4, 1);

  ProductModel product({
    String id = 'p1',
    String categoryId = 'cat1',
    double cost = 60,
  }) => ProductModel(
    id: id,
    name: 'Widget',
    categoryId: categoryId,
    categoryName: 'Widgets',
    quantity: 10,
    costPrice: cost,
    sellingPrice: 100,
    createdAt: march,
    updatedAt: march,
  );

  CommissionPlanModel plan({
    String id = 'plan1',
    String name = 'House scheme',
    CommissionBasis basis = CommissionBasis.revenue,
    double percent = 10,
    List<String> userIds = const [],
    bool includeUnpaid = true,
    double minimum = 0,
    bool active = true,
    List<CommissionRate> rates = const [],
    DateTime? updated,
  }) => CommissionPlanModel(
    id: id,
    name: name,
    basis: basis,
    defaultPercent: percent,
    categoryRates: rates,
    userIds: userIds,
    includeUnpaid: includeUnpaid,
    minimumSaleValue: minimum,
    isActive: active,
    createdAt: march,
    updatedAt: updated ?? march,
  );

  InvoiceModel invoice({
    required List<InvoiceItem> items,
    String createdBy = 'u1',
    double paid = 0,
    DateTime? date,
    InvoiceStatus status = InvoiceStatus.sent,
    InvoiceType type = InvoiceType.sales,
    double invoiceDiscount = 0,
  }) {
    final subtotal = items.fold(
      0.0,
      (acc, i) => acc + (i.quantity * i.unitPrice),
    );
    final lineDiscount = items.fold(
      0.0,
      (acc, i) => acc + (i.quantity * i.unitPrice * (i.discountPercent / 100)),
    );
    final total = subtotal - lineDiscount - invoiceDiscount;
    final when = date ?? march;
    return InvoiceModel(
      id: 'i${when.microsecondsSinceEpoch}$createdBy$total',
      invoiceType: type,
      invoiceNumber: 'INV',
      customerId: 'c1',
      customerName: 'Acme',
      status: status,
      items: items,
      subtotal: subtotal,
      totalDiscount: lineDiscount,
      invoiceDiscount: invoiceDiscount,
      grandTotal: total,
      amountPaid: paid,
      amountDue: total - paid,
      invoiceDate: when,
      dueDate: when,
      createdBy: createdBy,
      createdByName: 'Rep One',
      createdAt: when,
      updatedAt: when,
    );
  }

  InvoiceItem line({
    String productId = 'p1',
    int quantity = 10,
    double price = 100,
    double discount = 0,
  }) => InvoiceItem(
    productId: productId,
    productName: 'Widget',
    quantity: quantity,
    unitPrice: price,
    discountPercent: discount,
  );

  group('plan selection', () {
    test('a plan naming the user beats the everybody plan', () {
      final chosen = CommissionCalculator.planFor(
        plans: [
          plan(id: 'all', name: 'House'),
          plan(id: 'mine', name: 'Star seller', userIds: ['u1']),
        ],
        userId: 'u1',
        date: march,
      );
      expect(chosen?.id, 'mine');
    });

    test('among equally specific plans the most recently updated wins', () {
      final chosen = CommissionCalculator.planFor(
        plans: [
          plan(id: 'old', updated: DateTime(2026, 1, 1)),
          plan(id: 'new', updated: DateTime(2026, 2, 1)),
        ],
        userId: 'u1',
        date: march,
      );
      expect(chosen?.id, 'new');
    });

    test('inactive plans and plans outside their window are skipped', () {
      expect(
        CommissionCalculator.planFor(
          plans: [plan(active: false)],
          userId: 'u1',
          date: march,
        ),
        isNull,
      );
      final expired = plan().copyWith(effectiveTo: DateTime(2026, 1, 31));
      expect(
        CommissionCalculator.planFor(
          plans: [expired],
          userId: 'u1',
          date: march,
        ),
        isNull,
      );
    });
  });

  group('base', () {
    test('revenue is net of line discounts', () {
      final base = CommissionCalculator.baseFor(
        invoice: invoice(items: [line(discount: 10)]),
        basis: CommissionBasis.revenue,
        productsById: {'p1': product()},
      );
      expect(base, 900);
    });

    test('margin subtracts the product cost', () {
      final base = CommissionCalculator.baseFor(
        invoice: invoice(items: [line()]),
        basis: CommissionBasis.margin,
        productsById: {'p1': product(cost: 60)},
      );
      expect(base, 400);
    });

    test('a whole-invoice discount is spread across the lines', () {
      // 10% off the bottom of the invoice must not leave the commission base
      // untouched.
      final base = CommissionCalculator.baseFor(
        invoice: invoice(items: [line()], invoiceDiscount: 100),
        basis: CommissionBasis.revenue,
        productsById: {'p1': product()},
      );
      expect(base, 900);
    });

    test('a deleted product contributes its full revenue as margin', () {
      final base = CommissionCalculator.baseFor(
        invoice: invoice(items: [line()]),
        basis: CommissionBasis.margin,
        productsById: const {},
      );
      expect(base, 1000);
    });
  });

  group('rate', () {
    test('a category override applies', () {
      final rate = CommissionCalculator.rateFor(
        invoice: invoice(items: [line()]),
        plan: plan(
          rates: const [CommissionRate(categoryId: 'cat1', percent: 4)],
        ),
        productsById: {'p1': product()},
      );
      expect(rate, 4);
    });

    test('a mixed invoice uses a value-weighted mean of the rates', () {
      final rate = CommissionCalculator.rateFor(
        invoice: invoice(
          items: [
            line(productId: 'p1', quantity: 10, price: 100),
            line(productId: 'p2', quantity: 10, price: 100),
          ],
        ),
        plan: plan(
          percent: 10,
          rates: const [CommissionRate(categoryId: 'cat1', percent: 4)],
        ),
        productsById: {
          'p1': product(),
          'p2': product(id: 'p2', categoryId: 'cat2'),
        },
      );
      expect(rate, 7);
    });
  });

  group('run', () {
    test('pays the plan rate on qualifying invoices', () {
      final run = CommissionCalculator.run(
        invoices: [invoice(items: [line()])],
        plans: [plan(percent: 10)],
        products: [product()],
        from: from,
        to: to,
      );
      expect(run.statements.single.commissionTotal, 100);
      expect(run.statements.single.userName, 'Rep One');
      expect(run.totalCommission, 100);
    });

    test('collection-based plans pay only on what was collected', () {
      final run = CommissionCalculator.run(
        invoices: [invoice(items: [line()], paid: 250)],
        plans: [plan(percent: 10, includeUnpaid: false)],
        products: [product()],
        from: from,
        to: to,
      );
      // A quarter collected earns a quarter of the commission.
      expect(run.statements.single.commissionTotal, 25);
      expect(run.statements.single.lines.single.collectedShare, 0.25);
    });

    test('an unpaid invoice earns nothing on a collection plan', () {
      final run = CommissionCalculator.run(
        invoices: [invoice(items: [line()])],
        plans: [plan(includeUnpaid: false)],
        products: [product()],
        from: from,
        to: to,
      );
      expect(run.statements, isEmpty);
    });

    test('a loss-making margin sale earns nothing rather than clawing back', () {
      final run = CommissionCalculator.run(
        invoices: [
          invoice(items: [line(price: 100)]),
          invoice(items: [line(productId: 'p2', price: 10)], createdBy: 'u1'),
        ],
        plans: [plan(basis: CommissionBasis.margin, percent: 10)],
        products: [product(), product(id: 'p2', cost: 60)],
        from: from,
        to: to,
      );
      // The good sale earns; the loss-maker contributes zero, not a negative.
      expect(run.statements.single.commissionTotal, 40);
    });

    test('invoices below the plan minimum are counted and skipped', () {
      final run = CommissionCalculator.run(
        invoices: [invoice(items: [line(quantity: 1)])],
        plans: [plan(minimum: 500)],
        products: [product()],
        from: from,
        to: to,
      );
      expect(run.statements, isEmpty);
      expect(run.invoicesBelowMinimum, 1);
    });

    test('sales by somebody no plan covers are surfaced, not swallowed', () {
      final run = CommissionCalculator.run(
        invoices: [invoice(items: [line()], createdBy: 'stranger')],
        plans: [plan(userIds: ['u1'])],
        products: [product()],
        from: from,
        to: to,
      );
      expect(run.statements, isEmpty);
      expect(run.invoicesWithoutPlan, 1);
      expect(run.invoicesConsidered, 1);
    });

    test('drafts, cancellations and other periods are out of scope', () {
      final run = CommissionCalculator.run(
        invoices: [
          invoice(items: [line()], status: InvoiceStatus.draft),
          invoice(items: [line()], status: InvoiceStatus.cancelled),
          invoice(items: [line()], date: DateTime(2026, 2, 10)),
          invoice(items: [line()], type: InvoiceType.purchase),
        ],
        plans: [plan()],
        products: [product()],
        from: from,
        to: to,
      );
      expect(run.invoicesConsidered, 0);
      expect(run.totalCommission, 0);
    });

    test('statements are ranked by what each person earned', () {
      final run = CommissionCalculator.run(
        invoices: [
          invoice(items: [line(quantity: 1)], createdBy: 'small'),
          invoice(items: [line(quantity: 50)], createdBy: 'big'),
        ],
        plans: [plan()],
        products: [product()],
        from: from,
        to: to,
        userNames: const {'small': 'Small', 'big': 'Big'},
      );
      expect(run.statements.first.userName, 'Big');
      expect(run.statements.first.effectiveRate, closeTo(10, 0.001));
    });
  });
}
