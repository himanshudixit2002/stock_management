import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/transfer_order_model.dart';

void main() {
  final now = DateTime(2026, 1, 1);

  TransferOrderModel order({
    TransferOrderStatus status = TransferOrderStatus.draft,
    List<TransferOrderLine> lines = const [],
    DateTime? expectedAt,
    DateTime? dispatchedAt,
  }) => TransferOrderModel(
    id: 't1',
    fromLocation: 'Main',
    toLocation: 'Depot',
    status: status,
    lines: lines,
    expectedAt: expectedAt,
    dispatchedAt: dispatchedAt,
    createdAt: now,
    updatedAt: now,
  );

  const line = TransferOrderLine(productId: 'p', quantity: 10);

  group('quantities', () {
    test('in transit is what left minus what arrived', () {
      const partly = TransferOrderLine(
        productId: 'p',
        quantity: 10,
        dispatchedQuantity: 10,
        receivedQuantity: 4,
      );
      expect(partly.inTransitQuantity, 6);
    });

    test('in transit never goes negative on an over-receipt', () {
      const over = TransferOrderLine(
        productId: 'p',
        quantity: 10,
        dispatchedQuantity: 4,
        receivedQuantity: 10,
      );
      expect(over.inTransitQuantity, 0);
    });

    test('totals sum across lines and ignore negative quantities', () {
      final o = order(
        lines: const [
          TransferOrderLine(productId: 'a', quantity: 5, dispatchedQuantity: 5),
          TransferOrderLine(productId: 'b', quantity: -3),
        ],
      );
      expect(o.totalQuantity, 5);
      expect(o.totalDispatched, 5);
      expect(o.totalInTransit, 5);
    });
  });

  group('state transitions', () {
    test('only a draft with lines can be dispatched', () {
      expect(order(lines: const [line]).canDispatch, isTrue);
      expect(order().canDispatch, isFalse);
      expect(
        order(status: TransferOrderStatus.dispatched, lines: const [line])
            .canDispatch,
        isFalse,
      );
    });

    test('only a dispatched order with stock in transit can be received', () {
      const inTransit = TransferOrderLine(
        productId: 'p',
        quantity: 10,
        dispatchedQuantity: 10,
      );
      expect(
        order(status: TransferOrderStatus.dispatched, lines: const [inTransit])
            .canReceive,
        isTrue,
      );
      expect(
        order(status: TransferOrderStatus.draft, lines: const [inTransit])
            .canReceive,
        isFalse,
      );
    });

    test('a partly received order can no longer be cancelled', () {
      // Cancelling would have to un-receive stock that is already on the
      // destination's shelf.
      const partly = TransferOrderLine(
        productId: 'p',
        quantity: 10,
        dispatchedQuantity: 10,
        receivedQuantity: 4,
      );
      expect(
        order(status: TransferOrderStatus.dispatched, lines: const [partly])
            .canCancel,
        isFalse,
      );
      expect(
        order(status: TransferOrderStatus.dispatched, lines: const [
          TransferOrderLine(
            productId: 'p',
            quantity: 10,
            dispatchedQuantity: 10,
          ),
        ]).canCancel,
        isTrue,
      );
    });

    test('only a draft is editable', () {
      expect(order().canEdit, isTrue);
      expect(order(status: TransferOrderStatus.dispatched).canEdit, isFalse);
    });
  });

  group('shipment health', () {
    test('a shipment past its expected date is overdue', () {
      expect(
        order(
          status: TransferOrderStatus.dispatched,
          expectedAt: DateTime(2020, 1, 1),
        ).isOverdue,
        isTrue,
      );
      expect(
        order(
          status: TransferOrderStatus.dispatched,
          expectedAt: DateTime(2099, 1, 1),
        ).isOverdue,
        isFalse,
      );
      // A draft cannot be overdue: nothing has left yet.
      expect(order(expectedAt: DateTime(2020, 1, 1)).isOverdue, isFalse);
    });

    test('days in transit is null unless the order is on the road', () {
      expect(order().daysInTransit, isNull);
      expect(
        order(
          status: TransferOrderStatus.dispatched,
          dispatchedAt: DateTime.now().subtract(const Duration(days: 3)),
        ).daysInTransit,
        3,
      );
    });

    test('a closed order that received less than it sent has a shortage', () {
      final closed = order(
        status: TransferOrderStatus.received,
        lines: const [
          TransferOrderLine(
            productId: 'p',
            quantity: 10,
            dispatchedQuantity: 10,
            receivedQuantity: 8,
          ),
        ],
      );
      expect(closed.hasShortage, isTrue);
    });
  });

  test('round-trips through a map', () {
    final original = order(
      status: TransferOrderStatus.dispatched,
      lines: const [line],
      expectedAt: DateTime(2026, 2, 1),
    );
    final restored = TransferOrderModel.fromMap(original.toMap(), 't1');
    expect(restored.status, TransferOrderStatus.dispatched);
    expect(restored.lines.single.quantity, 10);
    expect(restored.expectedAt, DateTime(2026, 2, 1));
  });
}
