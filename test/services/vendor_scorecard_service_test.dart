import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/purchase_order_model.dart';
import 'package:stock_management/models/vendor_model.dart';
import 'package:stock_management/services/vendor_scorecard_service.dart';

void main() {
  final today = DateTime(2026, 3, 10);

  VendorModel vendor({String id = 'v1', int leadTime = 0}) => VendorModel(
    id: id,
    name: 'Supplier $id',
    leadTimeDays: leadTime,
    createdAt: today,
    updatedAt: today,
  );

  PurchaseOrderModel order({
    String vendorId = 'v1',
    required DateTime created,
    required DateTime expected,
    DateTime? received,
    List<POItem> items = const [],
    double total = 1000,
    POStatus status = POStatus.received,
  }) => PurchaseOrderModel(
    id: 'po${created.microsecondsSinceEpoch}$vendorId$total',
    vendorId: vendorId,
    vendorName: 'Supplier $vendorId',
    status: status,
    items: items,
    totalAmount: total,
    expectedDate: expected,
    receivedDate: received,
    createdAt: created,
    updatedAt: created,
  );

  POItem item({
    String productId = 'p1',
    int quantity = 10,
    int received = 10,
    double price = 100,
  }) => POItem(
    productId: productId,
    productName: 'Widget',
    quantity: quantity,
    receivedQuantity: received,
    unitPrice: price,
  );

  group('rating threshold', () {
    test('a vendor with fewer than three receipts is not graded', () {
      final card = VendorScorecardService.analyse(
        vendors: [vendor()],
        orders: [
          order(
            created: today.subtract(const Duration(days: 20)),
            expected: today.subtract(const Duration(days: 10)),
            received: today.subtract(const Duration(days: 12)),
            items: [item()],
          ),
        ],
        asOf: today,
      );
      expect(card.scores.single.isRated, isFalse);
      expect(card.scores.single.grade, '—');
      // Still measured, just not graded — one delivery is data, not a verdict.
      expect(card.scores.single.onTimeCount, 1);
    });
  });

  group('metrics', () {
    List<PurchaseOrderModel> threeOrders({
      required bool onTime,
      int receivedQty = 10,
      double price = 100,
    }) => [
      for (var i = 1; i <= 3; i++)
        order(
          created: today.subtract(Duration(days: 30 + i)),
          expected: today.subtract(Duration(days: 20 + i)),
          received: today.subtract(
            Duration(days: onTime ? 22 + i : 10 + i),
          ),
          items: [item(received: receivedQty, price: price)],
        ),
    ];

    test('early deliveries count as on time', () {
      final card = VendorScorecardService.analyse(
        vendors: [vendor()],
        orders: threeOrders(onTime: true),
        asOf: today,
      );
      final score = card.scores.single;
      expect(score.onTimeRate, 1);
      expect(score.lateCount, 0);
      expect(score.grade, 'A');
    });

    test('late deliveries drag the grade down', () {
      final card = VendorScorecardService.analyse(
        vendors: [vendor()],
        orders: threeOrders(onTime: false),
        asOf: today,
      );
      final score = card.scores.single;
      expect(score.onTimeRate, 0);
      expect(score.score, lessThan(60));
    });

    test('fill rate is received over ordered', () {
      final card = VendorScorecardService.analyse(
        vendors: [vendor()],
        orders: threeOrders(onTime: true, receivedQty: 5),
        asOf: today,
      );
      expect(card.scores.single.fillRate, closeTo(0.5, 0.0001));
    });

    test('lead time is measured against the promise', () {
      final card = VendorScorecardService.analyse(
        vendors: [vendor(leadTime: 5)],
        orders: threeOrders(onTime: true),
        asOf: today,
      );
      final score = card.scores.single;
      // Raised 31-33 days ago, arrived 23-25 days ago: about 8 days each.
      expect(score.averageLeadTimeDays, closeTo(8, 1));
      expect(score.leadTimeVariance, closeTo(3, 1));
    });

    test('rising prices are reported as a trend', () {
      final card = VendorScorecardService.analyse(
        vendors: [vendor()],
        orders: [
          order(
            created: today.subtract(const Duration(days: 60)),
            expected: today.subtract(const Duration(days: 50)),
            received: today.subtract(const Duration(days: 52)),
            items: [item(price: 100)],
          ),
          order(
            created: today.subtract(const Duration(days: 40)),
            expected: today.subtract(const Duration(days: 30)),
            received: today.subtract(const Duration(days: 32)),
            items: [item(price: 110)],
          ),
          order(
            created: today.subtract(const Duration(days: 20)),
            expected: today.subtract(const Duration(days: 10)),
            received: today.subtract(const Duration(days: 12)),
            items: [item(price: 120)],
          ),
        ],
        asOf: today,
      );
      expect(card.scores.single.priceTrendPercent, closeTo(20, 0.001));
      // Price stability is worth less than delivery: perfect on-time and fill
      // still grade well despite a 20% rise.
      expect(card.scores.single.grade, anyOf('A', 'B'));
    });
  });

  group('scoping', () {
    test('cancelled orders and orders outside the window are ignored', () {
      final card = VendorScorecardService.analyse(
        vendors: [vendor()],
        orders: [
          order(
            created: today.subtract(const Duration(days: 400)),
            expected: today.subtract(const Duration(days: 390)),
            received: today.subtract(const Duration(days: 392)),
            items: [item()],
          ),
          order(
            created: today.subtract(const Duration(days: 5)),
            expected: today,
            status: POStatus.cancelled,
            items: [item()],
          ),
        ],
        windowDays: 365,
        asOf: today,
      );
      expect(card.ordersConsidered, 0);
      expect(card.scores, isEmpty);
    });

    test('open orders count towards spend but not delivery', () {
      final card = VendorScorecardService.analyse(
        vendors: [vendor()],
        orders: [
          order(
            created: today.subtract(const Duration(days: 5)),
            expected: today.add(const Duration(days: 5)),
            status: POStatus.sent,
            items: [item(received: 0)],
            total: 2500,
          ),
        ],
        asOf: today,
      );
      final score = card.scores.single;
      expect(score.openCount, 1);
      expect(score.completedCount, 0);
      expect(score.totalSpend, 2500);
      expect(card.totalSpend, 2500);
    });

    test('vendors are ranked with the graded ones first', () {
      final card = VendorScorecardService.analyse(
        vendors: [vendor(id: 'v1'), vendor(id: 'v2')],
        orders: [
          for (var i = 1; i <= 3; i++)
            order(
              vendorId: 'v1',
              created: today.subtract(Duration(days: 30 + i)),
              expected: today.subtract(Duration(days: 20 + i)),
              received: today.subtract(Duration(days: 22 + i)),
              items: [item()],
            ),
          order(
            vendorId: 'v2',
            created: today.subtract(const Duration(days: 5)),
            expected: today.add(const Duration(days: 5)),
            status: POStatus.sent,
            items: [item(received: 0)],
            total: 999999,
          ),
        ],
        asOf: today,
      );
      expect(card.scores.first.vendorId, 'v1');
      expect(card.best?.vendorId, 'v1');
    });
  });
}
