import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/landed_cost_model.dart';
import 'package:stock_management/services/landed_cost_allocator.dart';

void main() {
  LandedCostLine line(String id, int quantity, double cost) => LandedCostLine(
    productId: id,
    productName: id,
    quantity: quantity,
    baseUnitCost: cost,
  );

  double totalAllocated(List<LandedCostLine> lines) =>
      lines.fold(0.0, (acc, l) => acc + l.allocatedAmount);

  group('allocate', () {
    test('spreads a value-based charge in proportion to line value', () {
      final result = LandedCostAllocator.allocate(
        // 300 and 100 -> 3:1
        lines: [line('a', 3, 100), line('b', 1, 100)],
        charges: const [LandedCostCharge(label: 'Freight', amount: 400)],
      );
      expect(result[0].allocatedAmount, 300);
      expect(result[1].allocatedAmount, 100);
    });

    test('spreads a quantity-based charge per unit, not per value', () {
      final result = LandedCostAllocator.allocate(
        // Values are 3:1 but quantities are 1:1, so handling splits evenly.
        lines: [line('a', 2, 150), line('b', 2, 50)],
        charges: const [
          LandedCostCharge(
            label: 'Handling',
            amount: 100,
            basis: AllocationBasis.quantity,
          ),
        ],
      );
      expect(result[0].allocatedAmount, 50);
      expect(result[1].allocatedAmount, 50);
    });

    test('splits an equal-basis charge per line', () {
      final result = LandedCostAllocator.allocate(
        lines: [line('a', 10, 100), line('b', 1, 1)],
        charges: const [
          LandedCostCharge(
            label: 'Paperwork',
            amount: 90,
            basis: AllocationBasis.equal,
          ),
        ],
      );
      expect(result[0].allocatedAmount, 45);
      expect(result[1].allocatedAmount, 45);
    });

    test('sums charges allocated on different bases onto the same lines', () {
      final result = LandedCostAllocator.allocate(
        lines: [line('a', 1, 300), line('b', 3, 100)],
        charges: const [
          // By value this is 1:1; by quantity it is 1:3.
          LandedCostCharge(label: 'Duty', amount: 100),
          LandedCostCharge(
            label: 'Handling',
            amount: 40,
            basis: AllocationBasis.quantity,
          ),
        ],
      );
      expect(result[0].allocatedAmount, 60);
      expect(result[1].allocatedAmount, 80);
      expect(totalAllocated(result), 140);
    });

    test('allocated amounts always add up to the charges, despite rounding', () {
      // 100 / 3 does not divide into cents; the residue has to land somewhere
      // rather than being dropped, or the landed value stops reconciling.
      final result = LandedCostAllocator.allocate(
        lines: [line('a', 1, 10), line('b', 1, 10), line('c', 1, 10)],
        charges: const [LandedCostCharge(label: 'Freight', amount: 100)],
      );
      expect(totalAllocated(result), closeTo(100, 0.0001));
    });

    test('splits equally when nothing can be weighed', () {
      // A zero-value receipt would otherwise divide by zero and silently
      // discard the charge.
      final result = LandedCostAllocator.allocate(
        lines: [line('a', 0, 0), line('b', 0, 0)],
        charges: const [LandedCostCharge(label: 'Freight', amount: 50)],
      );
      expect(totalAllocated(result), 50);
      expect(result[0].allocatedAmount, 25);
    });

    test('returns nothing for no lines rather than losing the charge silently', () {
      expect(
        LandedCostAllocator.allocate(
          lines: const [],
          charges: const [LandedCostCharge(label: 'Freight', amount: 50)],
        ),
        isEmpty,
      );
    });
  });

  group('LandedCostLine', () {
    test('landed unit cost adds the per-unit share of the allocation', () {
      const l = LandedCostLine(
        productId: 'a',
        quantity: 4,
        baseUnitCost: 100,
        allocatedAmount: 40,
      );
      expect(l.landedUnitCost, 110);
      expect(l.upliftPercent, 10);
    });

    test('a zero-quantity line reports its base cost rather than dividing by zero', () {
      const l = LandedCostLine(
        productId: 'a',
        quantity: 0,
        baseUnitCost: 100,
        allocatedAmount: 40,
      );
      expect(l.landedUnitCost, 100);
    });
  });

  group('aggregateByProduct', () {
    LandedCostLine applied(
      String id,
      int quantity,
      double baseCost,
      double allocated, {
      double previous = 0,
    }) => LandedCostLine(
      productId: id,
      productName: id,
      quantity: quantity,
      baseUnitCost: baseCost,
      allocatedAmount: allocated,
      previousUnitCost: previous,
    );

    test('one line per product passes its landed cost straight through', () {
      final changes = LandedCostAllocator.aggregateByProduct([
        applied('a', 4, 100, 40),
      ]);
      expect(changes, hasLength(1));
      expect(changes.single.landedUnitCost, 110);
      expect(changes.single.quantity, 4);
    });

    test('a product on two lines gets one units-weighted cost', () {
      // 1 unit landing at 200 and 3 units landing at 100 average to 125,
      // not to the 150 a plain mean would give, and not to whichever line
      // happened to be written last.
      final changes = LandedCostAllocator.aggregateByProduct([
        applied('a', 1, 200, 0),
        applied('a', 3, 100, 0),
      ]);
      expect(changes, hasLength(1));
      expect(changes.single.landedUnitCost, 125);
      expect(changes.single.quantity, 4);
    });

    test('keeps products separate and in the order they appear', () {
      final changes = LandedCostAllocator.aggregateByProduct([
        applied('b', 1, 10, 0),
        applied('a', 1, 20, 0),
        applied('b', 1, 30, 0),
      ]);
      expect(changes.map((c) => c.productId), ['b', 'a']);
      expect(changes.first.landedUnitCost, 20);
    });

    test('a reversal restores the cost from before the sheet', () {
      final changes = LandedCostAllocator.aggregateByProduct([
        applied('a', 2, 110, 20, previous: 95),
      ]);
      expect(changes.single.previousUnitCost, 95);
    });

    test('a zero-quantity receipt averages plainly instead of dividing by zero', () {
      final changes = LandedCostAllocator.aggregateByProduct([
        applied('a', 0, 100, 0),
        applied('a', 0, 200, 0),
      ]);
      expect(changes.single.landedUnitCost, 150);
      expect(changes.single.quantity, 0);
    });

    test('lines with no product are skipped', () {
      final changes = LandedCostAllocator.aggregateByProduct([
        applied('', 1, 10, 0),
        applied('a', 1, 10, 0),
      ]);
      expect(changes.map((c) => c.productId), ['a']);
    });
  });
}
