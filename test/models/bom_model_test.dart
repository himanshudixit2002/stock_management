import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/bom_model.dart';

void main() {
  final now = DateTime(2026, 1, 1);

  BomModel bom({
    int outputQuantity = 1,
    List<BomComponent> components = const [],
    BomStatus status = BomStatus.active,
  }) => BomModel(
    id: 'b1',
    name: 'Hamper',
    outputProductId: 'out',
    outputProductName: 'Hamper',
    outputQuantity: outputQuantity,
    components: components,
    status: status,
    createdAt: now,
    updatedAt: now,
  );

  group('BomComponent.consumptionFor', () {
    test('multiplies by runs with no wastage', () {
      const c = BomComponent(productId: 'a', quantity: 3);
      expect(c.consumptionFor(4), 12);
    });

    test('rounds wastage up, so a build never under-consumes', () {
      // 10 * 1.02 = 10.2 units; rounding down would let a build succeed on
      // stock that is not on the shelf.
      const c = BomComponent(productId: 'a', quantity: 10, wastagePercent: 2);
      expect(c.consumptionFor(1), 11);
    });

    test('zero or negative runs consume nothing', () {
      const c = BomComponent(productId: 'a', quantity: 3);
      expect(c.consumptionFor(0), 0);
      expect(c.consumptionFor(-2), 0);
    });
  });

  group('consumptionFor', () {
    test('sums a component listed twice rather than dropping one', () {
      final b = bom(
        components: const [
          BomComponent(productId: 'a', quantity: 2),
          BomComponent(productId: 'a', quantity: 3),
        ],
      );
      expect(b.consumptionFor(1), {'a': 5});
    });

    test('skips components with no product', () {
      final b = bom(
        components: const [
          BomComponent(productId: '', quantity: 5),
          BomComponent(productId: 'a', quantity: 1),
        ],
      );
      expect(b.consumptionFor(1), {'a': 1});
    });
  });

  group('maxRunsFrom', () {
    test('is limited by the scarcest component', () {
      final b = bom(
        components: const [
          BomComponent(productId: 'a', quantity: 2),
          BomComponent(productId: 'b', quantity: 5),
        ],
      );
      expect(b.maxRunsFrom({'a': 100, 'b': 12}), 2);
    });

    test('accounts for wastage rather than ignoring it', () {
      // Without wastage 10 units would allow 1 run; with 50% wastage a run
      // consumes 15, so nothing can be built.
      final b = bom(
        components: const [
          BomComponent(productId: 'a', quantity: 10, wastagePercent: 50),
        ],
      );
      expect(b.maxRunsFrom({'a': 10}), 0);
      expect(b.maxRunsFrom({'a': 15}), 1);
    });

    test('a missing component means nothing can be built', () {
      final b = bom(
        components: const [BomComponent(productId: 'a', quantity: 1)],
      );
      expect(b.maxRunsFrom(const {}), 0);
    });

    test('a recipe with no components builds nothing, not everything', () {
      // Returning "unlimited" here would be a licence to print stock.
      expect(bom().maxRunsFrom({'a': 1000}), 0);
    });
  });

  group('output and status', () {
    test('output scales with runs', () {
      expect(bom(outputQuantity: 6).outputFor(3), 18);
      expect(bom(outputQuantity: 6).outputFor(0), 0);
    });

    test('only an active recipe with components is buildable', () {
      const component = BomComponent(productId: 'a', quantity: 1);
      expect(bom(components: const [component]).isBuildable, isTrue);
      expect(
        bom(components: const [component], status: BomStatus.draft).isBuildable,
        isFalse,
      );
      expect(bom().isBuildable, isFalse);
    });
  });

  group('serialization', () {
    test('round-trips through a map', () {
      final original = bom(
        outputQuantity: 4,
        components: const [
          BomComponent(
            productId: 'a',
            productName: 'Box',
            quantity: 2,
            unit: 'pcs',
            wastagePercent: 5,
          ),
        ],
      );
      final restored = BomModel.fromMap(original.toMap(), 'b1');
      expect(restored.outputQuantity, 4);
      expect(restored.components.single.productId, 'a');
      expect(restored.components.single.wastagePercent, 5);
      expect(restored.status, BomStatus.active);
    });

    test('a zero output quantity is clamped to one', () {
      // A zero would make every build consume components and produce nothing.
      final restored = BomModel.fromMap(const {
        'name': 'x',
        'outputProductId': 'out',
        'outputQuantity': 0,
      }, 'b1');
      expect(restored.outputQuantity, 1);
    });

    test('a malformed components field yields no components, not a crash', () {
      final restored = BomModel.fromMap(const {
        'name': 'x',
        'components': 'not a list',
      }, 'b1');
      expect(restored.components, isEmpty);
    });
  });
}
