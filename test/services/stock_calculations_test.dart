import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/product_model.dart';
import 'package:stock_management/models/stock_transaction_model.dart';
import 'package:stock_management/services/stock_calculations.dart';

StockTransactionModel _txn({
  required String id,
  required String productId,
  TransactionType type = TransactionType.stockIn,
  int quantity = 1,
  required DateTime date,
  String productName = '',
  String userId = 'user-1',
}) {
  return StockTransactionModel(
    id: id,
    productId: productId,
    productName: productName,
    type: type,
    quantity: quantity,
    userId: userId,
    date: date,
  );
}

void main() {
  group('StockCalculations.todayTransactionCount', () {
    test('counts only transactions whose calendar day matches today', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 14, 30);
      final yesterday = today.subtract(const Duration(days: 1));

      final list = [
        _txn(id: '1', productId: 'a', date: today),
        _txn(id: '2', productId: 'b', date: yesterday),
        _txn(
          id: '3',
          productId: 'c',
          date: today.add(const Duration(hours: 1)),
        ),
      ];

      expect(StockCalculations.todayTransactionCount(list), 2);
    });

    test('returns zero when no transactions fall on today', () {
      final now = DateTime.now();
      final past = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 2));

      expect(
        StockCalculations.todayTransactionCount([
          _txn(id: '1', productId: 'p', date: past),
        ]),
        0,
      );
    });
  });

  group('StockCalculations.recentTransactions', () {
    test('returns up to [limit] items preserving input order', () {
      final t1 = _txn(id: '1', productId: 'p', date: DateTime(2024, 3, 1));
      final t2 = _txn(id: '2', productId: 'p', date: DateTime(2024, 3, 2));
      final t3 = _txn(id: '3', productId: 'p', date: DateTime(2024, 3, 3));
      final list = [t1, t2, t3];

      expect(StockCalculations.recentTransactions(list, limit: 2), [t1, t2]);
      expect(StockCalculations.recentTransactions(list, limit: 10), list);
    });

    test('default limit is 5', () {
      final list = List.generate(
        7,
        (i) => _txn(id: '$i', productId: 'p', date: DateTime(2024, 1, i + 1)),
      );
      expect(StockCalculations.recentTransactions(list), hasLength(5));
    });
  });

  group('StockCalculations.filterByType', () {
    test('returns only matching transaction types', () {
      final in1 = _txn(
        id: '1',
        productId: 'p',
        type: TransactionType.stockIn,
        date: DateTime(2024, 1, 1),
      );
      final out1 = _txn(
        id: '2',
        productId: 'p',
        type: TransactionType.stockOut,
        date: DateTime(2024, 1, 2),
      );
      final in2 = _txn(
        id: '3',
        productId: 'p',
        type: TransactionType.stockIn,
        date: DateTime(2024, 1, 3),
      );

      final filtered = StockCalculations.filterByType([
        in1,
        out1,
        in2,
      ], TransactionType.stockIn);

      expect(filtered, [in1, in2]);
    });
  });

  group('StockCalculations.filterByProduct', () {
    test('returns only transactions for the given product id', () {
      final a1 = _txn(id: '1', productId: 'prod-a', date: DateTime(2024, 2, 1));
      final b1 = _txn(id: '2', productId: 'prod-b', date: DateTime(2024, 2, 2));
      final a2 = _txn(id: '3', productId: 'prod-a', date: DateTime(2024, 2, 3));

      expect(StockCalculations.filterByProduct([a1, b1, a2], 'prod-a'), [
        a1,
        a2,
      ]);
    });
  });

  group('StockCalculations.netStockChange', () {
    test(
      'adds stock in, subtracts stock out and damage, ignores non-physical hold flows',
      () {
        final base = DateTime(2024, 5, 1);
        final list = [
          _txn(
            id: '1',
            productId: 'p',
            type: TransactionType.stockIn,
            quantity: 100,
            date: base,
          ),
          _txn(
            id: '2',
            productId: 'p',
            type: TransactionType.stockOut,
            quantity: 30,
            date: base,
          ),
          _txn(
            id: '3',
            productId: 'p',
            type: TransactionType.damage,
            quantity: 5,
            date: base,
          ),
          _txn(
            id: '4',
            productId: 'p',
            type: TransactionType.transfer,
            quantity: 40,
            date: base,
          ),
          _txn(
            id: '5',
            productId: 'p',
            type: TransactionType.adjustment,
            quantity: 99,
            date: base,
          ),
          _txn(
            id: '6',
            productId: 'p',
            type: TransactionType.hold,
            quantity: 15,
            date: base,
          ),
          _txn(
            id: '7',
            productId: 'p',
            type: TransactionType.holdRelease,
            quantity: 15,
            date: base,
          ),
        ];

        expect(StockCalculations.netStockChange(list), 65);
      },
    );

    test('returns zero for empty list', () {
      expect(StockCalculations.netStockChange([]), 0);
    });
  });

  // --- Demand ---------------------------------------------------------------
  //
  // These moved here because four screens each had their own version and they
  // disagreed: the reorder list and the forecast divided by a fixed 30 and
  // measured the runway against on-hand; the reports service divided by its
  // selected period; the AI dashboard counted damage as demand too.

  ProductModel product({
    int quantity = 100,
    int heldQuantity = 0,
    int lowStockThreshold = 10,
  }) => ProductModel(
    id: 'p1',
    name: 'Widget',
    categoryId: 'c1',
    quantity: quantity,
    heldQuantity: heldQuantity,
    lowStockThreshold: lowStockThreshold,
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );

  group('StockCalculations.dailyBurnRate', () {
    final now = DateTime(2024, 6, 30);

    test('averages stock-out over the window', () {
      final txns = [
        _txn(id: '1', productId: 'p1', type: TransactionType.stockOut,
            quantity: 60, date: now.subtract(const Duration(days: 5))),
      ];
      expect(
        StockCalculations.dailyBurnRate(txns, 'p1', now: now),
        closeTo(2.0, 1e-9),
        reason: '60 units over a 30 day window',
      );
    });

    test('ignores damage — a loss is not demand', () {
      final txns = [
        _txn(id: '1', productId: 'p1', type: TransactionType.stockOut,
            quantity: 30, date: now.subtract(const Duration(days: 2))),
        _txn(id: '2', productId: 'p1', type: TransactionType.damage,
            quantity: 300, date: now.subtract(const Duration(days: 2))),
      ];
      expect(StockCalculations.dailyBurnRate(txns, 'p1', now: now), closeTo(1.0, 1e-9));
    });

    test('ignores stock-in and other products', () {
      final txns = [
        _txn(id: '1', productId: 'p1', type: TransactionType.stockIn,
            quantity: 900, date: now.subtract(const Duration(days: 1))),
        _txn(id: '2', productId: 'p2', type: TransactionType.stockOut,
            quantity: 900, date: now.subtract(const Duration(days: 1))),
      ];
      expect(StockCalculations.dailyBurnRate(txns, 'p1', now: now), 0);
    });

    test('excludes movement older than the window', () {
      final txns = [
        _txn(id: '1', productId: 'p1', type: TransactionType.stockOut,
            quantity: 60, date: now.subtract(const Duration(days: 40))),
      ];
      expect(StockCalculations.dailyBurnRate(txns, 'p1', now: now), 0);
    });

    test('divides by the days observed, not the window asked for', () {
      // A workspace three days old. Dividing 30 units by a flat 30 said 1/day
      // when the real rate is 10/day — a tenfold understatement, on the figure
      // that decides how much to reorder.
      final firstAt = now.subtract(const Duration(days: 3));
      final txns = [
        _txn(id: '1', productId: 'p1', type: TransactionType.stockOut,
            quantity: 30, date: now.subtract(const Duration(days: 1))),
      ];
      expect(
        StockCalculations.dailyBurnRate(txns, 'p1', now: now,
            firstTransactionAt: firstAt),
        closeTo(10.0, 1e-9),
      );
      expect(
        StockCalculations.dailyBurnRate(txns, 'p1', now: now),
        closeTo(1.0, 1e-9),
        reason: 'without the correction, the old behaviour',
      );
    });

    test('never divides by less than a day', () {
      final txns = [
        _txn(id: '1', productId: 'p1', type: TransactionType.stockOut,
            quantity: 5, date: now),
      ];
      final rate = StockCalculations.dailyBurnRate(txns, 'p1', now: now,
          firstTransactionAt: now);
      expect(rate, closeTo(5.0, 1e-9));
      expect(rate.isFinite, isTrue);
    });
  });

  group('StockCalculations.daysOfSupply', () {
    test('measures against available stock, not on-hand', () {
      // 40 on hand, 25 reserved for an order, 5/day of demand. On-hand says 8
      // days; the truth is 3, and the reorder list already flags this product
      // off the same available figure.
      final p = product(quantity: 40, heldQuantity: 25);
      expect(StockCalculations.daysOfSupply(p, 5), closeTo(3.0, 1e-9));
      expect(p.quantity / 5, 8.0, reason: 'what the old code reported');
    });

    test('is infinite when nothing is moving', () {
      expect(StockCalculations.daysOfSupply(product(), 0), double.infinity);
    });
  });

  group('StockCalculations.suggestedReorderQuantity', () {
    test('covers the lead time plus a safety buffer', () {
      // The headline case: 50/day, 21-day lead time. The old formula
      // (threshold*2 - quantity) suggested 20 units — a stockout about 19 days
      // before the delivery landed.
      final p = product(quantity: 0, lowStockThreshold: 10);
      final qty = StockCalculations.suggestedReorderQuantity(p, 50,
          leadTimeDays: 21, safetyDays: 7);
      expect(qty, 50 * 28);
      expect(p.lowStockThreshold * 2 - p.quantity, 20,
          reason: 'what the old formula suggested');
    });

    test('subtracts what is already available', () {
      final p = product(quantity: 100, heldQuantity: 0);
      expect(
        StockCalculations.suggestedReorderQuantity(p, 10,
            leadTimeDays: 3, safetyDays: 7),
        1,
        reason: '10/day over 10 days is 100, already covered; floor of 1',
      );
    });

    test('reserved units do not count as cover', () {
      final p = product(quantity: 100, heldQuantity: 100);
      expect(
        StockCalculations.suggestedReorderQuantity(p, 10,
            leadTimeDays: 3, safetyDays: 7),
        100,
      );
    });

    test('falls back to the threshold rule with no demand history', () {
      final p = product(quantity: 4, lowStockThreshold: 10);
      expect(StockCalculations.suggestedReorderQuantity(p, 0, leadTimeDays: 7), 16);
    });

    test('never suggests less than one unit', () {
      final p = product(quantity: 10000);
      expect(
        StockCalculations.suggestedReorderQuantity(p, 1, leadTimeDays: 1),
        1,
      );
    });
  });
}
