import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/shipment_model.dart';

void main() {
  final now = DateTime(2026, 3, 10);

  ShipmentModel shipment({
    ShipmentStatus status = ShipmentStatus.draft,
    List<ShipmentLine> lines = const [],
  }) => ShipmentModel(
    id: 's1',
    shipmentNumber: 'SH-1',
    salesOrderId: 'so1',
    customerName: 'Acme',
    status: status,
    lines: lines,
    location: 'Main',
    createdAt: now,
    updatedAt: now,
  );

  group('quantities', () {
    test('a short pick is reported per line and in total', () {
      final s = shipment(
        lines: const [
          ShipmentLine(
            productId: 'p1',
            orderItemIndex: 0,
            orderedQuantity: 10,
            pickedQuantity: 7,
            packedQuantity: 7,
          ),
        ],
      );
      expect(s.lines.single.shortPicked, 3);
      expect(s.lines.single.isFullyPicked, isFalse);
      expect(s.isShort, isTrue);
      expect(s.pickProgress, closeTo(0.7, 0.0001));
    });

    test('an over-pick does not push progress past 100%', () {
      final s = shipment(
        lines: const [
          ShipmentLine(
            productId: 'p1',
            orderedQuantity: 10,
            pickedQuantity: 12,
          ),
        ],
      );
      expect(s.pickProgress, 1);
      expect(s.lines.single.shortPicked, 0);
    });
  });

  group('dispatch mapping', () {
    test('packed quantities are keyed by the order line, not the product', () {
      // The same product can legitimately appear twice on one order, so the
      // line index is what the dispatch path is addressed by.
      final s = shipment(
        lines: const [
          ShipmentLine(
            productId: 'p1',
            orderItemIndex: 0,
            orderedQuantity: 5,
            pickedQuantity: 5,
            packedQuantity: 5,
          ),
          ShipmentLine(
            productId: 'p1',
            orderItemIndex: 2,
            orderedQuantity: 3,
            pickedQuantity: 3,
            packedQuantity: 2,
          ),
        ],
      );
      expect(s.dispatchByOrderIndex, {0: 5, 2: 2});
    });

    test('what leaves is what was packed, not what was picked', () {
      final s = shipment(
        lines: const [
          ShipmentLine(
            productId: 'p1',
            orderItemIndex: 0,
            orderedQuantity: 10,
            pickedQuantity: 10,
            packedQuantity: 6,
          ),
        ],
      );
      expect(s.dispatchByOrderIndex, {0: 6});
      expect(s.totalPacked, 6);
    });

    test('lines with nothing packed are left out', () {
      final s = shipment(
        lines: const [
          ShipmentLine(productId: 'p1', orderItemIndex: 0, orderedQuantity: 5),
        ],
      );
      expect(s.dispatchByOrderIndex, isEmpty);
    });
  });

  group('transitions', () {
    ShipmentModel withPick(ShipmentStatus status) => shipment(
      status: status,
      lines: const [
        ShipmentLine(
          productId: 'p1',
          orderedQuantity: 5,
          pickedQuantity: 5,
          packedQuantity: 5,
        ),
      ],
    );

    test('packing needs something picked', () {
      expect(shipment().canPack, isFalse);
      expect(withPick(ShipmentStatus.picking).canPack, isTrue);
    });

    test('only a packed shipment dispatches', () {
      expect(withPick(ShipmentStatus.picking).canDispatch, isFalse);
      expect(withPick(ShipmentStatus.packed).canDispatch, isTrue);
    });

    test('a dispatched shipment can no longer be edited or cancelled', () {
      final dispatched = withPick(ShipmentStatus.dispatched);
      expect(dispatched.canEdit, isFalse);
      expect(dispatched.canCancel, isFalse);
      expect(dispatched.canDeliver, isTrue);
    });
  });

  group('serialisation', () {
    test('round-trips through a map', () {
      final original = shipment(
        status: ShipmentStatus.packed,
        lines: const [
          ShipmentLine(
            productId: 'p1',
            productName: 'Widget',
            orderItemIndex: 1,
            orderedQuantity: 4,
            pickedQuantity: 4,
            packedQuantity: 4,
            location: 'Main',
          ),
        ],
      ).copyWith(carrier: 'Blue Dart', packageCount: 3, weightKg: 12.5);

      final restored = ShipmentModel.fromMap(original.toMap(), 's1');
      expect(restored.status, ShipmentStatus.packed);
      expect(restored.carrier, 'Blue Dart');
      expect(restored.packageCount, 3);
      expect(restored.weightKg, 12.5);
      expect(restored.lines.single.orderItemIndex, 1);
    });

    test('a legacy line with no order index is not addressed for dispatch', () {
      final restored = ShipmentModel.fromMap(const {
        'lines': [
          {'productId': 'p1', 'orderedQuantity': 5, 'packedQuantity': 5},
        ],
      }, 's2');
      expect(restored.lines.single.orderItemIndex, -1);
      expect(restored.dispatchByOrderIndex, isEmpty);
    });
  });
}
