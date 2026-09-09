import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/customer_model.dart';
import 'package:stock_management/models/invoice_model.dart';
import 'package:stock_management/services/credit_control_service.dart';

void main() {
  final today = DateTime(2026, 3, 10);

  CustomerModel customer({
    String id = 'c1',
    double limit = 0,
    bool hold = false,
  }) => CustomerModel(
    id: id,
    name: 'Acme',
    creditLimit: limit,
    creditHold: hold,
    createdAt: today,
    updatedAt: today,
  );

  InvoiceModel invoice({
    required double total,
    double paid = 0,
    String customerId = 'c1',
    InvoiceStatus status = InvoiceStatus.sent,
    InvoiceType type = InvoiceType.sales,
    DateTime? due,
  }) => InvoiceModel(
    id: 'i$total$customerId${due ?? today}',
    invoiceType: type,
    invoiceNumber: 'INV',
    customerId: customerId,
    status: status,
    grandTotal: total,
    amountPaid: paid,
    amountDue: total - paid,
    invoiceDate: today.subtract(const Duration(days: 30)),
    dueDate: due ?? today.add(const Duration(days: 15)),
    createdAt: today,
    updatedAt: today,
  );

  group('exposure', () {
    test('sums what is unpaid on that customer only', () {
      final exposure = CreditControlService.exposureFor(
        customer: customer(),
        invoices: [
          invoice(total: 1000),
          invoice(total: 500, paid: 500, status: InvoiceStatus.paid),
          invoice(total: 9999, customerId: 'other'),
        ],
        asOf: today,
      );
      expect(exposure.outstanding, 1000);
      expect(exposure.openInvoices, 1);
    });

    test('drafts and cancellations are not credit', () {
      final exposure = CreditControlService.exposureFor(
        customer: customer(),
        invoices: [
          invoice(total: 1000, status: InvoiceStatus.draft),
          invoice(total: 2000, status: InvoiceStatus.cancelled),
        ],
        asOf: today,
      );
      expect(exposure.outstanding, 0);
    });

    test('a customer with no limit has no utilisation', () {
      // Null and zero are different facts: an unlimited account is not an
      // account at 0% of its limit.
      final exposure = CreditControlService.exposureFor(
        customer: customer(),
        invoices: [invoice(total: 1000)],
        asOf: today,
      );
      expect(exposure.utilisation, isNull);
      expect(exposure.headroom, isNull);
      expect(exposure.verdict, CreditVerdict.ok);
    });

    test('headroom and utilisation come off the limit', () {
      final exposure = CreditControlService.exposureFor(
        customer: customer(limit: 5000),
        invoices: [invoice(total: 2000)],
        asOf: today,
      );
      expect(exposure.utilisation, closeTo(0.4, 0.0001));
      expect(exposure.headroom, 3000);
      expect(exposure.verdict, CreditVerdict.ok);
    });
  });

  group('verdicts', () {
    test('a hold blocks regardless of the balance', () {
      final exposure = CreditControlService.exposureFor(
        customer: customer(hold: true),
        invoices: const [],
        asOf: today,
      );
      expect(exposure.verdict, CreditVerdict.blocked);
      expect(exposure.reason, contains('hold'));
    });

    test('at the limit is blocked, not merely warned', () {
      final exposure = CreditControlService.exposureFor(
        customer: customer(limit: 1000),
        invoices: [invoice(total: 1000)],
        asOf: today,
      );
      expect(exposure.verdict, CreditVerdict.blocked);
    });

    test('close to the limit warns', () {
      final exposure = CreditControlService.exposureFor(
        customer: customer(limit: 1000),
        invoices: [invoice(total: 900)],
        asOf: today,
      );
      expect(exposure.verdict, CreditVerdict.warning);
      expect(exposure.reason, contains('credit left'));
    });

    test('long overdue blocks even inside the limit', () {
      // An account two months late is not a theoretical risk.
      final exposure = CreditControlService.exposureFor(
        customer: customer(limit: 100000),
        invoices: [
          invoice(total: 500, due: today.subtract(const Duration(days: 70))),
        ],
        asOf: today,
      );
      expect(exposure.verdict, CreditVerdict.blocked);
      expect(exposure.oldestOverdueDays, 70);
      expect(exposure.overdueAmount, 500);
    });

    test('a month overdue warns', () {
      final exposure = CreditControlService.exposureFor(
        customer: customer(),
        invoices: [
          invoice(total: 500, due: today.subtract(const Duration(days: 35))),
        ],
        asOf: today,
      );
      expect(exposure.verdict, CreditVerdict.warning);
    });
  });

  group('exposureAfterSale', () {
    test('a sale that would break the limit is refused', () {
      // The point of the second method: a customer exactly inside their limit
      // is fine until somebody tries to sell them more.
      final current = CreditControlService.exposureFor(
        customer: customer(limit: 1000),
        invoices: [invoice(total: 800)],
        asOf: today,
      );
      // 80% of the limit is comfortable enough to say nothing about.
      expect(current.verdict, CreditVerdict.ok);

      final after = CreditControlService.exposureAfterSale(
        customer: customer(limit: 1000),
        invoices: [invoice(total: 800)],
        amount: 500,
        asOf: today,
      );
      expect(after.verdict, CreditVerdict.blocked);
      expect(after.outstanding, 1300);
      expect(after.reason, contains('over the'));
    });

    test('a sale inside the limit keeps the current verdict', () {
      final after = CreditControlService.exposureAfterSale(
        customer: customer(limit: 10000),
        invoices: [invoice(total: 800)],
        amount: 500,
        asOf: today,
      );
      expect(after.verdict, CreditVerdict.ok);
      expect(after.outstanding, 1300);
    });

    test('a zero-value sale changes nothing', () {
      final after = CreditControlService.exposureAfterSale(
        customer: customer(limit: 1000),
        invoices: [invoice(total: 900)],
        amount: 0,
        asOf: today,
      );
      expect(after.outstanding, 900);
    });
  });

  group('book', () {
    test('lists only accounts with a balance, a limit or a hold', () {
      final book = CreditControlService.book(
        customers: [
          customer(id: 'owing'),
          customer(id: 'limited', limit: 5000),
          customer(id: 'held', hold: true),
          customer(id: 'quiet'),
        ],
        invoices: [invoice(total: 1000, customerId: 'owing')],
        asOf: today,
      );
      expect(book.exposures.map((e) => e.customerId), [
        'held',
        'owing',
        'limited',
      ]);
      expect(book.totalOutstanding, 1000);
      expect(book.customersWithLimit, 1);
      expect(book.blockedCount, 1);
    });

    test('blocked accounts sort first, then by money at risk', () {
      final book = CreditControlService.book(
        customers: [
          customer(id: 'small'),
          customer(id: 'big'),
          customer(id: 'blocked', hold: true),
        ],
        invoices: [
          invoice(total: 100, customerId: 'small'),
          invoice(total: 9000, customerId: 'big'),
        ],
        asOf: today,
      );
      expect(book.exposures.first.customerId, 'blocked');
      expect(book.exposures[1].customerId, 'big');
    });
  });
}
