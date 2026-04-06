import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/invoice_model.dart';
import 'package:stock_management/models/sales_order_model.dart';
import 'package:stock_management/utils/sales_order_invoice_sync.dart';

DateTime get _t => DateTime(2024, 6, 1);

SalesOrderModel _so({
  List<SOItem>? items,
  SOStatus status = SOStatus.confirmed,
}) {
  return SalesOrderModel(
    id: 'so1',
    customerId: 'c1',
    customerName: 'Cust',
    status: status,
    items: items ?? [],
    totalAmount: 100,
    createdAt: _t,
    updatedAt: _t,
  );
}

InvoiceItem _inv(String pid, int q) => InvoiceItem(
      productId: pid,
      productName: pid,
      quantity: q,
      unitPrice: 10,
    );

void main() {
  group('applyInvoiceFulfillment', () {
    test('partial fulfillment keeps confirmed', () {
      final so = _so(
        items: [
          SOItem(productId: 'a', quantity: 10, dispatchedQuantity: 0),
          SOItem(productId: 'b', quantity: 5, dispatchedQuantity: 0),
        ],
      );
      final out = applyInvoiceFulfillment(so, [_inv('a', 3)], _t);
      expect(out.status, SOStatus.confirmed);
      expect(out.items[0].dispatchedQuantity, 3);
      expect(out.items[1].dispatchedQuantity, 0);
    });

    test('full fulfillment sets dispatched', () {
      final so = _so(
        items: [
          SOItem(productId: 'a', quantity: 10, dispatchedQuantity: 0),
        ],
      );
      final out = applyInvoiceFulfillment(so, [_inv('a', 10)], _t);
      expect(out.status, SOStatus.dispatched);
      expect(out.items[0].dispatchedQuantity, 10);
    });

    test('aggregates duplicate productIds on invoice', () {
      final so = _so(
        items: [SOItem(productId: 'a', quantity: 10, dispatchedQuantity: 0)],
      );
      final out = applyInvoiceFulfillment(
        so,
        [_inv('a', 4), _inv('a', 6)],
        _t,
      );
      expect(out.items[0].dispatchedQuantity, 10);
      expect(out.status, SOStatus.dispatched);
    });

    test('caps by line quantity', () {
      final so = _so(
        items: [SOItem(productId: 'a', quantity: 5, dispatchedQuantity: 0)],
      );
      final out = applyInvoiceFulfillment(so, [_inv('a', 100)], _t);
      expect(out.items[0].dispatchedQuantity, 5);
      expect(out.status, SOStatus.dispatched);
    });

    test('no-op for delivered', () {
      final so = _so(
        status: SOStatus.delivered,
        items: [
          SOItem(productId: 'a', quantity: 5, dispatchedQuantity: 5),
        ],
      );
      final out = applyInvoiceFulfillment(so, [_inv('a', 1)], _t);
      expect(out.items[0].dispatchedQuantity, 5);
      expect(out.status, SOStatus.delivered);
    });
  });

  group('revertInvoiceFulfillment', () {
    test('subtracts and downgrades dispatched to confirmed', () {
      final so = _so(
        status: SOStatus.dispatched,
        items: [
          SOItem(productId: 'a', quantity: 10, dispatchedQuantity: 10),
        ],
      );
      final out = revertInvoiceFulfillment(so, [_inv('a', 10)], _t);
      expect(out.items[0].dispatchedQuantity, 0);
      expect(out.status, SOStatus.confirmed);
    });

    test('partial revert leaves confirmed', () {
      final so = _so(
        status: SOStatus.dispatched,
        items: [
          SOItem(productId: 'a', quantity: 10, dispatchedQuantity: 10),
        ],
      );
      final out = revertInvoiceFulfillment(so, [_inv('a', 3)], _t);
      expect(out.items[0].dispatchedQuantity, 7);
      expect(out.status, SOStatus.confirmed);
    });
  });
}
