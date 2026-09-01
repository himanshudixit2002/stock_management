import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/invoice_model.dart';
import 'package:stock_management/services/aging_service.dart';

InvoiceModel _inv({
  required String number,
  required DateTime dueDate,
  double amountDue = 100,
  InvoiceType type = InvoiceType.sales,
  InvoiceStatus status = InvoiceStatus.sent,
  String customerId = 'c1',
  String customerName = 'Acme',
  String vendorId = '',
  String vendorName = '',
}) {
  final now = DateTime(2026, 1, 1);
  return InvoiceModel(
    id: number,
    invoiceType: type,
    invoiceNumber: number,
    customerId: customerId,
    customerName: customerName,
    vendorId: vendorId,
    vendorName: vendorName,
    status: status,
    grandTotal: amountDue,
    amountDue: amountDue,
    invoiceDate: now,
    dueDate: dueDate,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  const service = AgingService();
  final asOf = DateTime(2026, 6, 1);

  group('AgingService.bucketFor', () {
    test('maps day counts to the standard buckets', () {
      expect(AgingService.bucketFor(0), AgingBucket.current);
      expect(AgingService.bucketFor(-5), AgingBucket.current);
      expect(AgingService.bucketFor(1), AgingBucket.days30);
      expect(AgingService.bucketFor(30), AgingBucket.days30);
      expect(AgingService.bucketFor(31), AgingBucket.days60);
      expect(AgingService.bucketFor(60), AgingBucket.days60);
      expect(AgingService.bucketFor(61), AgingBucket.days90);
      expect(AgingService.bucketFor(90), AgingBucket.days90);
      expect(AgingService.bucketFor(91), AgingBucket.days90Plus);
    });
  });

  group('AgingService.build', () {
    test('buckets an invoice by how overdue it is', () {
      final rows = service.build(
        [_inv(number: 'A', dueDate: asOf.subtract(const Duration(days: 45)))],
        sales: true,
        asOf: asOf,
      );
      expect(rows, hasLength(1));
      expect(rows.first.amountIn(AgingBucket.days60), 100);
      expect(rows.first.total, 100);
    });

    test('groups several invoices under one party', () {
      final rows = service.build(
        [
          _inv(number: 'A', dueDate: asOf.add(const Duration(days: 10))),
          _inv(number: 'B', dueDate: asOf.subtract(const Duration(days: 100))),
        ],
        sales: true,
        asOf: asOf,
      );
      expect(rows, hasLength(1));
      expect(rows.first.amountIn(AgingBucket.current), 100);
      expect(rows.first.amountIn(AgingBucket.days90Plus), 100);
      expect(rows.first.total, 200);
    });

    test('never mixes receivables with payables', () {
      final invoices = [
        _inv(number: 'AR', dueDate: asOf),
        _inv(
          number: 'AP',
          dueDate: asOf,
          type: InvoiceType.purchase,
          customerId: '',
          customerName: '',
          vendorId: 'v1',
          vendorName: 'Supplier',
        ),
      ];
      final receivable = service.build(invoices, sales: true, asOf: asOf);
      final payable = service.build(invoices, sales: false, asOf: asOf);

      expect(receivable, hasLength(1));
      expect(receivable.first.partyName, 'Acme');
      expect(payable, hasLength(1));
      expect(payable.first.partyName, 'Supplier');
    });

    test('excludes cancelled, draft and settled invoices', () {
      final rows = service.build(
        [
          _inv(
            number: 'CANCELLED',
            dueDate: asOf,
            status: InvoiceStatus.cancelled,
          ),
          _inv(number: 'DRAFT', dueDate: asOf, status: InvoiceStatus.draft),
          _inv(number: 'SETTLED', dueDate: asOf, amountDue: 0),
        ],
        sales: true,
        asOf: asOf,
      );
      expect(rows, isEmpty);
    });

    test('sorts parties by the largest balance first', () {
      final rows = service.build(
        [
          _inv(
            number: 'S',
            dueDate: asOf,
            amountDue: 50,
            customerId: 'small',
            customerName: 'Small',
          ),
          _inv(
            number: 'B',
            dueDate: asOf,
            amountDue: 900,
            customerId: 'big',
            customerName: 'Big',
          ),
        ],
        sales: true,
        asOf: asOf,
      );
      expect(rows.map((r) => r.partyName), ['Big', 'Small']);
    });

    test('totals sum each bucket across parties', () {
      final rows = service.build(
        [
          _inv(
            number: 'A',
            dueDate: asOf.subtract(const Duration(days: 10)),
            customerId: 'a',
            customerName: 'A',
          ),
          _inv(
            number: 'B',
            dueDate: asOf.subtract(const Duration(days: 10)),
            customerId: 'b',
            customerName: 'B',
          ),
        ],
        sales: true,
        asOf: asOf,
      );
      expect(service.totals(rows)[AgingBucket.days30], 200);
    });
  });
}
