import 'package:flutter_test/flutter_test.dart';
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
}
