import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/product_model.dart';
import 'package:stock_management/models/stock_transaction_model.dart';
import 'package:stock_management/services/dead_stock_service.dart';

void main() {
  final asOf = DateTime(2026, 6, 1);

  ProductModel product(String id, {int quantity = 10, double cost = 100}) =>
      ProductModel(
        id: id,
        name: id,
        categoryId: 'c',
        quantity: quantity,
        costPrice: cost,
        createdAt: asOf,
        updatedAt: asOf,
      );

  StockTransactionModel movement(
    String productId,
    int daysAgo, {
    TransactionType type = TransactionType.stockOut,
    int quantity = 1,
  }) => StockTransactionModel(
    id: '$productId-$daysAgo',
    productId: productId,
    type: type,
    quantity: quantity,
    userId: 'u',
    date: asOf.subtract(Duration(days: daysAgo)),
  );

  DeadStockEntry entryFor(DeadStockReport report, String id) =>
      report.entries.firstWhere((e) => e.product.id == id);

  group('analyse', () {
    test('bands a product by how long since its last sale', () {
      final report = DeadStockService.analyse(
        products: [product('fresh'), product('slowing'), product('stale'), product('dead')],
        transactions: [
          movement('fresh', 2),
          movement('slowing', 40),
          movement('stale', 70),
          movement('dead', 200),
        ],
        staleAfterDays: 60,
        deadAfterDays: 120,
        asOf: asOf,
      );

      expect(entryFor(report, 'fresh').band, MovementBand.fresh);
      expect(entryFor(report, 'slowing').band, MovementBand.slowing);
      expect(entryFor(report, 'stale').band, MovementBand.stale);
      expect(entryFor(report, 'dead').band, MovementBand.dead);
    });

    test('a product with no outbound history reads as never sold, not as dead', () {
      // The distinction matters: a new product has no evidence either way.
      final report = DeadStockService.analyse(
        products: [product('new')],
        transactions: const [],
        asOf: asOf,
      );
      final entry = entryFor(report, 'new');
      expect(entry.band, MovementBand.neverSold);
      expect(entry.daysSinceLastSale, isNull);
      expect(entry.lastSaleDate, isNull);
    });

    test('write-offs and transfers are not evidence of demand', () {
      // Counting a damage write-off as a sale would hide exactly the products
      // this report exists to surface.
      final report = DeadStockService.analyse(
        products: [product('p')],
        transactions: [
          movement('p', 1, type: TransactionType.damage),
          movement('p', 1, type: TransactionType.transfer),
          movement('p', 1, type: TransactionType.adjustment),
        ],
        asOf: asOf,
      );
      expect(entryFor(report, 'p').band, MovementBand.neverSold);
      expect(report.transactionsCovered, 0);
    });

    test('the most recent sale is the one that counts', () {
      final report = DeadStockService.analyse(
        products: [product('p')],
        transactions: [movement('p', 300), movement('p', 5)],
        asOf: asOf,
      );
      expect(entryFor(report, 'p').daysSinceLastSale, 5);
    });

    test('units sold only count inside the window', () {
      final report = DeadStockService.analyse(
        products: [product('p')],
        transactions: [
          movement('p', 10, quantity: 3),
          movement('p', 200, quantity: 50),
        ],
        windowDays: 90,
        asOf: asOf,
      );
      expect(entryFor(report, 'p').unitsSoldInWindow, 3);
    });

    test('value at rest is cost, not retail', () {
      final report = DeadStockService.analyse(
        products: [product('p', quantity: 4, cost: 25)],
        transactions: const [],
        asOf: asOf,
      );
      expect(entryFor(report, 'p').valueAtRest, 100);
      expect(report.totalValueAtRest, 100);
    });

    test('products with nothing on hand are excluded by default', () {
      final report = DeadStockService.analyse(
        products: [product('empty', quantity: 0)],
        transactions: const [],
        asOf: asOf,
      );
      expect(report.entries, isEmpty);

      final withZero = DeadStockService.analyse(
        products: [product('empty', quantity: 0)],
        transactions: const [],
        includeZeroStock: true,
        asOf: asOf,
      );
      expect(withZero.entries, hasLength(1));
    });

    test('worst band first, then most capital tied up', () {
      final report = DeadStockService.analyse(
        products: [
          product('freshExpensive', quantity: 100, cost: 500),
          product('deadCheap', quantity: 1, cost: 1),
          product('deadExpensive', quantity: 10, cost: 100),
        ],
        transactions: [
          movement('freshExpensive', 1),
          movement('deadCheap', 200),
          movement('deadExpensive', 200),
        ],
        staleAfterDays: 60,
        deadAfterDays: 120,
        asOf: asOf,
      );
      expect(report.entries.first.product.id, 'deadExpensive');
      expect(report.entries.last.product.id, 'freshExpensive');
    });

    test('problem share is the capital at rest over the total', () {
      final report = DeadStockService.analyse(
        products: [
          product('dead', quantity: 1, cost: 300),
          product('fresh', quantity: 1, cost: 100),
        ],
        transactions: [movement('dead', 200), movement('fresh', 1)],
        staleAfterDays: 60,
        deadAfterDays: 120,
        asOf: asOf,
      );
      expect(report.totalValueAtRest, 400);
      expect(report.deadValue, 300);
      expect(report.problemShare, closeTo(0.75, 0.0001));
    });

    test('an empty catalog yields the empty report rather than throwing', () {
      final report = DeadStockService.analyse(
        products: const [],
        transactions: const [],
      );
      expect(report.entries, isEmpty);
      expect(report.problemShare, 0);
    });
  });
}
