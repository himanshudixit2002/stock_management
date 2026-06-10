import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/stock_hold_model.dart';

void main() {
  group('StockHoldModel', () {
    test('serializes and deserializes with remaining quantity', () {
      final now = DateTime(2026, 1, 1, 10, 0);
      final hold = StockHoldModel(
        id: 'hold-1',
        productId: 'prod-1',
        productName: 'Test Product',
        location: 'Main',
        quantity: 20,
        consumedQuantity: 5,
        releasedQuantity: 3,
        status: StockHoldStatus.partiallyConsumed,
        sourceType: StockHoldSourceType.salesOrder,
        sourceId: 'so-1',
        challanNumber: 'SO-abc123',
        reason: 'SO confirmed',
        createdBy: 'u1',
        createdByName: 'Test User',
        createdAt: now,
        updatedAt: now,
      );

      final map = hold.toMap();
      final parsed = StockHoldModel.fromMap(map, 'hold-1');

      expect(parsed.productId, 'prod-1');
      expect(parsed.sourceType, StockHoldSourceType.salesOrder);
      expect(parsed.status, StockHoldStatus.partiallyConsumed);
      expect(parsed.remainingQuantity, 12);
      expect(parsed.challanNumber, 'SO-abc123');
    });

    test('defaults challanNumber to empty when absent (backward compatible)',
        () {
      final parsed = StockHoldModel.fromMap({
        'productId': 'p1',
        'productName': 'Tea',
        'location': 'Main',
        'quantity': 5,
      }, 'hold-2');

      expect(parsed.challanNumber, isEmpty);
      expect(parsed.remainingQuantity, 5);
    });

    test('copyWith updates challanNumber', () {
      final now = DateTime(2026, 1, 1);
      final hold = StockHoldModel(
        id: 'h',
        productId: 'p',
        location: 'Main',
        quantity: 3,
        createdAt: now,
        updatedAt: now,
      );

      expect(hold.challanNumber, isEmpty);
      expect(hold.copyWith(challanNumber: 'CH-1').challanNumber, 'CH-1');
    });

    test('location is optional and hasLocation reflects it', () {
      final now = DateTime(2026, 1, 1);
      final located = StockHoldModel(
        id: 'h1',
        productId: 'p',
        location: 'Main',
        quantity: 3,
        createdAt: now,
        updatedAt: now,
      );
      final unassigned = StockHoldModel(
        id: 'h2',
        productId: 'p',
        quantity: 3,
        createdAt: now,
        updatedAt: now,
      );

      expect(located.hasLocation, isTrue);
      expect(unassigned.location, isEmpty);
      expect(unassigned.hasLocation, isFalse);
    });

    test('location-less hold round-trips through map', () {
      final now = DateTime(2026, 1, 1);
      final hold = StockHoldModel(
        id: 'h3',
        productId: 'p',
        productName: 'Tea',
        quantity: 7,
        challanNumber: 'CH-9',
        createdAt: now,
        updatedAt: now,
      );

      final parsed = StockHoldModel.fromMap(hold.toMap(), 'h3');
      expect(parsed.hasLocation, isFalse);
      expect(parsed.remainingQuantity, 7);
      expect(parsed.challanNumber, 'CH-9');
    });
  });
}
