import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/purchase_order_model.dart';
import 'package:stock_management/models/return_model.dart';
import 'package:stock_management/models/sales_order_model.dart';
import 'package:stock_management/utils/order_return_sync.dart';

DateTime get _t => DateTime(2024, 6, 1);

ReturnItem _r(String pid, int q) =>
    ReturnItem(productId: pid, productName: pid, quantity: q);

void main() {
  group('applyCustomerReturnToSalesOrder', () {
    test('increments returnedQuantity capped by dispatched', () {
      final so = SalesOrderModel(
        id: 's1',
        customerId: 'c',
        status: SOStatus.dispatched,
        items: [
          SOItem(
            productId: 'a',
            quantity: 10,
            dispatchedQuantity: 10,
            returnedQuantity: 0,
          ),
        ],
        totalAmount: 100,
        createdAt: _t,
        updatedAt: _t,
      );
      final out = applyCustomerReturnToSalesOrder(so, [_r('a', 3)], _t);
      expect(out.items.first.returnedQuantity, 3);
    });

    test('uses quantity cap when nothing dispatched', () {
      final so = SalesOrderModel(
        id: 's1',
        customerId: 'c',
        status: SOStatus.confirmed,
        items: [
          SOItem(
            productId: 'a',
            quantity: 5,
            dispatchedQuantity: 0,
            returnedQuantity: 0,
          ),
        ],
        totalAmount: 50,
        createdAt: _t,
        updatedAt: _t,
      );
      final out = applyCustomerReturnToSalesOrder(so, [_r('a', 10)], _t);
      expect(out.items.first.returnedQuantity, 5);
    });
  });

  group('applyVendorReturnToPurchaseOrder', () {
    test('reduces receivedQuantity and status', () {
      final po = PurchaseOrderModel(
        id: 'p1',
        vendorId: 'v',
        status: POStatus.received,
        items: [POItem(productId: 'a', quantity: 10, receivedQuantity: 10)],
        totalAmount: 100,
        expectedDate: _t,
        receivedDate: _t,
        createdAt: _t,
        updatedAt: _t,
      );
      final out = applyVendorReturnToPurchaseOrder(po, [_r('a', 4)], _t);
      expect(out.items.first.receivedQuantity, 6);
      expect(out.status, POStatus.partial);
    });
  });
}
