import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/invoice_model.dart';
import 'package:stock_management/models/register_session_model.dart';
import 'package:stock_management/services/register_tally_service.dart';

void main() {
  final opened = DateTime(2026, 3, 10, 9);

  RegisterSessionModel session({
    double float = 500,
    List<CashMovement> movements = const [],
    String id = 's1',
  }) => RegisterSessionModel(
    id: id,
    registerName: 'Counter 1',
    openingFloat: float,
    movements: movements,
    openedAt: opened,
  );

  InvoiceModel sale({
    required double total,
    double paid = 0,
    String method = 'cash',
    String sessionId = 's1',
    InvoiceType type = InvoiceType.sales,
    InvoiceStatus status = InvoiceStatus.paid,
  }) => InvoiceModel(
    id: 'i$total$method$sessionId',
    invoiceType: type,
    invoiceNumber: 'INV',
    customerId: 'c1',
    status: status,
    registerSessionId: sessionId,
    grandTotal: total,
    amountPaid: paid,
    amountDue: total - paid,
    payments: paid <= 0
        ? const []
        : [
            PaymentRecord(
              id: 'p',
              amount: paid,
              date: opened,
              method: method,
            ),
          ],
    invoiceDate: opened,
    dueDate: opened,
    createdAt: opened,
    updatedAt: opened,
  );

  group('cash method detection', () {
    test('matches loosely, because tills are configured by hand', () {
      expect(RegisterTallyService.isCashMethod('cash'), isTrue);
      expect(RegisterTallyService.isCashMethod('  CASH '), isTrue);
      expect(RegisterTallyService.isCashMethod('Cash on hand'), isTrue);
      expect(RegisterTallyService.isCashMethod('card'), isFalse);
      expect(RegisterTallyService.isCashMethod('UPI'), isFalse);
    });

    test('an unrecorded method counts as cash', () {
      // An old POS sale with no method recorded was cash; treating it as
      // "other" would make every historical drawer look short.
      expect(RegisterTallyService.isCashMethod(''), isTrue);
    });
  });

  group('tally', () {
    test('expected cash is float plus cash takings plus movements', () {
      final tally = RegisterTallyService.tally(
        session: session(
          movements: [
            CashMovement(id: 'm1', amount: -2000, reason: 'drop', at: opened),
            CashMovement(id: 'm2', amount: 100, reason: 'top-up', at: opened),
          ],
        ),
        invoices: [
          sale(total: 3000, paid: 3000),
          sale(total: 1000, paid: 1000, method: 'card'),
        ],
      );
      expect(tally.cashTakings, 3000);
      expect(tally.otherTakings, 1000);
      expect(tally.movementTotal, -1900);
      expect(tally.expectedCash, 500 + 3000 - 1900);
    });

    test('a credit sale is counted as sales but not as cash', () {
      final tally = RegisterTallyService.tally(
        session: session(),
        invoices: [sale(total: 2000, paid: 0, status: InvoiceStatus.sent)],
      );
      expect(tally.salesTotal, 2000);
      expect(tally.creditSales, 2000);
      expect(tally.cashTakings, 0);
      expect(tally.expectedCash, 500);
    });

    test('a credit note rung up on the shift takes cash back out', () {
      final tally = RegisterTallyService.tally(
        session: session(),
        invoices: [
          sale(total: 1000, paid: 1000),
          sale(total: 300, paid: 300, type: InvoiceType.creditNote),
        ],
      );
      expect(tally.refundTotal, 300);
      expect(tally.cashTakings, 700);
      expect(tally.expectedCash, 1200);
    });

    test('only invoices stamped with this shift are counted', () {
      final tally = RegisterTallyService.tally(
        session: session(),
        invoices: [
          sale(total: 1000, paid: 1000),
          sale(total: 9999, paid: 9999, sessionId: 'other'),
          sale(total: 5555, paid: 5555, sessionId: ''),
        ],
      );
      expect(tally.invoiceCount, 1);
      expect(tally.cashTakings, 1000);
    });

    test('a cancelled invoice is ignored', () {
      final tally = RegisterTallyService.tally(
        session: session(),
        invoices: [
          sale(total: 1000, paid: 1000, status: InvoiceStatus.cancelled),
        ],
      );
      expect(tally.invoiceCount, 0);
      expect(tally.expectedCash, 500);
    });

    test('takings are broken down by method, normalised', () {
      final tally = RegisterTallyService.tally(
        session: session(),
        invoices: [
          sale(total: 100, paid: 100, method: 'Cash'),
          sale(total: 200, paid: 200, method: 'cash'),
          sale(total: 300, paid: 300, method: 'UPI'),
        ],
      );
      expect(tally.takingsByMethod['cash'], 300);
      expect(tally.takingsByMethod['upi'], 300);
    });

    test('variance is counted minus expected', () {
      final tally = RegisterTallyService.tally(
        session: session(),
        invoices: [sale(total: 1000, paid: 1000)],
      );
      expect(tally.expectedCash, 1500);
      expect(tally.varianceFor(1450), -50);
      expect(tally.varianceFor(1520), 20);
    });

    test('a shift with no id tallies nothing rather than everything', () {
      // An unsaved session must not claim every unstamped sale in the
      // workspace.
      final tally = RegisterTallyService.tally(
        session: session(id: ''),
        invoices: [sale(total: 1000, paid: 1000, sessionId: '')],
      );
      expect(tally.invoiceCount, 0);
    });
  });

  group('session model', () {
    test('register keys collapse case and whitespace', () {
      expect(RegisterSessionModel.keyFor('Counter 1'), 'counter 1');
      expect(RegisterSessionModel.keyFor('  counter   1 '), 'counter 1');
      expect(RegisterSessionModel.keyFor(''), 'main');
    });

    test('movement totals split drops from top-ups', () {
      final s = session(
        movements: [
          CashMovement(id: 'a', amount: -500, at: opened),
          CashMovement(id: 'b', amount: 200, at: opened),
        ],
      );
      expect(s.cashDrops, 500);
      expect(s.cashAdded, 200);
      expect(s.movementTotal, -300);
    });

    test('a balanced close is within a rounding cent', () {
      final closed = session().copyWith(
        expectedCash: 1000,
        countedCash: 1000.004,
      );
      expect(closed.isBalanced, isTrue);
      expect(closed.copyWith(countedCash: 990).isBalanced, isFalse);
      expect(closed.copyWith(countedCash: 990).variance, -10);
    });
  });
}
