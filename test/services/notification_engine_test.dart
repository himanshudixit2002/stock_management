import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/batch_model.dart';
import 'package:stock_management/models/invoice_model.dart';
import 'package:stock_management/models/product_model.dart';
import 'package:stock_management/models/purchase_order_model.dart';
import 'package:stock_management/services/notification_engine.dart';

final DateTime _now = DateTime(2026, 3, 15, 9);

ProductModel _product({
  required String id,
  int quantity = 100,
  int held = 0,
  int threshold = 10,
}) {
  return ProductModel(
    id: id,
    name: 'Product $id',
    categoryId: 'c1',
    quantity: quantity,
    heldQuantity: held,
    lowStockThreshold: threshold,
    createdAt: _now,
    updatedAt: _now,
  );
}

BatchModel _batch({
  required String id,
  required DateTime expiry,
  int quantity = 5,
  BatchStatus status = BatchStatus.active,
}) {
  return BatchModel(
    id: id,
    productId: 'p-$id',
    productName: 'Product $id',
    batchNumber: 'B$id',
    expiryDate: expiry,
    quantity: quantity,
    status: status,
    createdAt: _now,
    updatedAt: _now,
  );
}

InvoiceModel _invoice({
  required String id,
  required DateTime due,
  double amountDue = 500,
  InvoiceStatus status = InvoiceStatus.sent,
}) {
  return InvoiceModel(
    id: id,
    invoiceNumber: 'INV-$id',
    customerId: 'cust',
    customerName: 'Acme',
    status: status,
    amountDue: amountDue,
    grandTotal: 500,
    invoiceDate: due.subtract(const Duration(days: 30)),
    dueDate: due,
    createdAt: _now,
    updatedAt: _now,
  );
}

PurchaseOrderModel _po({
  required String id,
  required DateTime expected,
  POStatus status = POStatus.sent,
}) {
  return PurchaseOrderModel(
    id: id,
    vendorId: 'v1',
    vendorName: 'Vendor One',
    status: status,
    expectedDate: expected,
    createdAt: _now,
    updatedAt: _now,
  );
}

const _engine = NotificationEngine();

void main() {
  group('stock alerts', () {
    test('flags out-of-stock and low-stock separately, never both', () {
      final results = _engine.scan(
        now: _now,
        products: [
          _product(id: 'empty', quantity: 0),
          _product(id: 'low', quantity: 4, threshold: 10),
          _product(id: 'fine', quantity: 500, threshold: 10),
        ],
      );

      final byType = <String, List<NotificationCandidate>>{};
      for (final c in results) {
        byType.putIfAbsent(c.type, () => []).add(c);
      }

      expect(byType[AlertType.outOfStock], hasLength(1));
      expect(byType[AlertType.outOfStock]!.single.entityId, 'empty');
      expect(byType[AlertType.lowStock], hasLength(1));
      expect(byType[AlertType.lowStock]!.single.entityId, 'low');
      // 'fine' contributes nothing, and no product appears under two types.
      expect(results, hasLength(2));
    });

    test('held stock counts against availability', () {
      // 12 on hand but 10 held leaves 2 available, under the threshold of 5.
      final results = _engine.scan(
        now: _now,
        products: [_product(id: 'p', quantity: 12, held: 10, threshold: 5)],
      );

      expect(results.single.type, AlertType.lowStock);
      expect(results.single.message, contains('2'));
    });

    test('collapses to one summary row past the threshold', () {
      final many = List.generate(
        9,
        (i) => _product(id: 'low$i', quantity: 1, threshold: 10),
      );

      final results = _engine.scan(now: _now, products: many);
      final low = results.where((c) => c.type == AlertType.lowStock).toList();

      expect(low, hasLength(1));
      expect(low.single.title, '9 products are running low');
      // A summary points at the list screen, not a single product.
      expect(low.single.entityId, isEmpty);
      expect(low.single.entityType, 'low_stock_list');
    });

    test('emits individual rows at or below the threshold', () {
      final few = List.generate(
        5,
        (i) => _product(id: 'low$i', quantity: 1, threshold: 10),
      );

      final results = _engine.scan(now: _now, products: few);

      expect(results, hasLength(5));
      expect(results.every((c) => c.entityType == 'product'), isTrue);
    });
  });

  group('batch alerts', () {
    test('separates expired from expiring and ignores empty or recalled', () {
      final results = _engine.scan(
        now: _now,
        batches: [
          _batch(id: 'gone', expiry: _now.subtract(const Duration(days: 2))),
          _batch(id: 'soon', expiry: _now.add(const Duration(days: 10))),
          _batch(id: 'far', expiry: _now.add(const Duration(days: 300))),
          // Zero units left is not worth waking anyone for.
          _batch(
            id: 'drained',
            expiry: _now.subtract(const Duration(days: 5)),
            quantity: 0,
          ),
          // A recalled batch is already being dealt with.
          _batch(
            id: 'recalled',
            expiry: _now.subtract(const Duration(days: 5)),
            status: BatchStatus.recalled,
          ),
        ],
      );

      expect(
        results.where((c) => c.type == AlertType.batchExpired).map(
          (c) => c.entityId,
        ),
        ['gone'],
      );
      expect(
        results.where((c) => c.type == AlertType.batchExpiring).map(
          (c) => c.entityId,
        ),
        ['soon'],
      );
    });

    test('honours a narrower expiry window', () {
      final batches = [_batch(id: 'b', expiry: _now.add(const Duration(days: 20)))];

      final wide = _engine.scan(now: _now, batches: batches);
      final narrow = _engine.scan(
        now: _now,
        batches: batches,
        config: const AlertScanConfig(expiryWarningDays: 7),
      );

      expect(wide.single.type, AlertType.batchExpiring);
      expect(narrow, isEmpty);
    });
  });

  group('invoice alerts', () {
    test('only unpaid, issued invoices past their due date count', () {
      final past = _now.subtract(const Duration(days: 12));
      final results = _engine.scan(
        now: _now,
        invoices: [
          _invoice(id: 'overdue', due: past),
          _invoice(id: 'draft', due: past, status: InvoiceStatus.draft),
          _invoice(id: 'cancelled', due: past, status: InvoiceStatus.cancelled),
          _invoice(id: 'settled', due: past, status: InvoiceStatus.paid),
          // Status says sent, but nothing is actually owed.
          _invoice(id: 'zero', due: past, amountDue: 0),
          _invoice(id: 'future', due: _now.add(const Duration(days: 5))),
        ],
      );

      expect(results.map((c) => c.entityId), ['overdue']);
      expect(results.single.message, contains('12 days overdue'));
    });
  });

  group('purchase order alerts', () {
    test('only sent or partial orders can be late', () {
      final past = _now.subtract(const Duration(days: 3));
      final results = _engine.scan(
        now: _now,
        purchaseOrders: [
          _po(id: 'sent', expected: past),
          _po(id: 'partial', expected: past, status: POStatus.partial),
          _po(id: 'draft', expected: past, status: POStatus.draft),
          _po(id: 'received', expected: past, status: POStatus.received),
          _po(id: 'cancelled', expected: past, status: POStatus.cancelled),
          _po(id: 'upcoming', expected: _now.add(const Duration(days: 4))),
        ],
      );

      expect(
        results.map((c) => c.entityId).toSet(),
        {'sent', 'partial'},
      );
    });
  });

  group('dedupe ids', () {
    test('same condition on the same day produces identical ids', () {
      final products = [_product(id: 'p', quantity: 0)];

      final morning = _engine.scan(now: DateTime(2026, 3, 15, 8), products: products);
      final evening = _engine.scan(now: DateTime(2026, 3, 15, 22), products: products);

      expect(morning.single.id, evening.single.id);
    });

    test('ids repeat within the cooldown window and change after it', () {
      final products = [_product(id: 'p', quantity: 0)];

      // Out-of-stock has a 3-day cooldown, so day 0 and day 1 land in the same
      // bucket while a fortnight later does not.
      final day0 = _engine.scan(now: DateTime(2026, 3, 15), products: products);
      final day1 = _engine.scan(now: DateTime(2026, 3, 16), products: products);
      final later = _engine.scan(now: DateTime(2026, 3, 29), products: products);

      expect(day0.single.id, day1.single.id);
      expect(day0.single.id, isNot(later.single.id));
    });

    test('ids stay safe as Firestore document ids', () {
      final results = _engine.scan(
        now: _now,
        products: [_product(id: 'a/b/c .. weird#id', quantity: 0)],
      );

      final id = results.single.id;
      expect(id, isNot(contains('/')));
      expect(id, isNot('.'));
      expect(id, isNot('..'));
      expect(id, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    });
  });

  group('config', () {
    test('disabled types are skipped entirely', () {
      final results = _engine.scan(
        now: _now,
        products: [_product(id: 'p', quantity: 0)],
        batches: [_batch(id: 'b', expiry: _now.subtract(const Duration(days: 1)))],
        config: const AlertScanConfig(enabledTypes: {AlertType.batchExpired}),
      );

      expect(results.map((c) => c.type), [AlertType.batchExpired]);
    });

    test('an empty enabled set produces nothing', () {
      final results = _engine.scan(
        now: _now,
        products: [_product(id: 'p', quantity: 0)],
        config: const AlertScanConfig(enabledTypes: {}),
      );

      expect(results, isEmpty);
    });

    test('every declared type has a label and description', () {
      for (final type in AlertType.all) {
        expect(AlertType.label(type), isNotEmpty);
        expect(AlertType.description(type), isNotEmpty);
      }
    });
  });
}
