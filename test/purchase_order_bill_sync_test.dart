import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/invoice_model.dart';
import 'package:stock_management/models/purchase_order_model.dart';
import 'package:stock_management/utils/purchase_order_bill_sync.dart';

DateTime get _t => DateTime(2024, 6, 1);

PurchaseOrderModel _po({
  List<POItem>? items,
  POStatus status = POStatus.sent,
  DateTime? receivedDate,
}) {
  return PurchaseOrderModel(
    id: 'po1',
    vendorId: 'v1',
    vendorName: 'Vendor',
    status: status,
    items: items ?? [],
    totalAmount: 100,
    expectedDate: _t,
    receivedDate: receivedDate,
    createdAt: _t,
    updatedAt: _t,
  );
}

InvoiceItem _line(String pid, int q) =>
    InvoiceItem(productId: pid, productName: pid, quantity: q, unitPrice: 10);

void main() {
  group('applyBillReceipt', () {
    test('partial receipt keeps sent with progress becomes partial', () {
      final po = _po(
        items: [
          POItem(productId: 'a', quantity: 10, receivedQuantity: 0),
          POItem(productId: 'b', quantity: 5, receivedQuantity: 0),
        ],
      );
      final out = applyBillReceipt(po, [_line('a', 3)], _t);
      expect(out.status, POStatus.partial);
      expect(out.items[0].receivedQuantity, 3);
      expect(out.items[1].receivedQuantity, 0);
    });

    test('full receipt sets received', () {
      final po = _po(
        items: [POItem(productId: 'a', quantity: 10, receivedQuantity: 0)],
      );
      final out = applyBillReceipt(po, [_line('a', 10)], _t);
      expect(out.status, POStatus.received);
      expect(out.items[0].receivedQuantity, 10);
      expect(out.receivedDate, isNotNull);
    });

    test('aggregates duplicate productIds on bill', () {
      final po = _po(
        items: [POItem(productId: 'a', quantity: 10, receivedQuantity: 0)],
      );
      final out = applyBillReceipt(po, [_line('a', 4), _line('a', 6)], _t);
      expect(out.items[0].receivedQuantity, 10);
      expect(out.status, POStatus.received);
    });

    test('caps by line quantity', () {
      final po = _po(
        items: [POItem(productId: 'a', quantity: 5, receivedQuantity: 0)],
      );
      final out = applyBillReceipt(po, [_line('a', 100)], _t);
      expect(out.items[0].receivedQuantity, 5);
      expect(out.status, POStatus.received);
    });

    test('no-op for fully received', () {
      final po = _po(
        status: POStatus.received,
        items: [POItem(productId: 'a', quantity: 5, receivedQuantity: 5)],
      );
      final out = applyBillReceipt(po, [_line('a', 1)], _t);
      expect(out.items[0].receivedQuantity, 5);
      expect(out.status, POStatus.received);
    });
  });

  group('revertBillReceipt', () {
    test('subtracts and downgrades received to sent', () {
      final po = _po(
        status: POStatus.received,
        receivedDate: _t,
        items: [POItem(productId: 'a', quantity: 10, receivedQuantity: 10)],
      );
      final out = revertBillReceipt(po, [_line('a', 10)], _t);
      expect(out.items[0].receivedQuantity, 0);
      expect(out.status, POStatus.sent);
      expect(out.receivedDate, isNull);
    });

    test('partial revert leaves partial', () {
      final po = _po(
        status: POStatus.received,
        items: [POItem(productId: 'a', quantity: 10, receivedQuantity: 10)],
      );
      final out = revertBillReceipt(po, [_line('a', 3)], _t);
      expect(out.items[0].receivedQuantity, 7);
      expect(out.status, POStatus.partial);
    });
  });
}
