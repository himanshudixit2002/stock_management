import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/product_model.dart';
import 'package:stock_management/models/unit_conversion_rule.dart';
import 'package:stock_management/services/unit_conversion_planner.dart';

UnitConversionRule _rule(
  String id, {
  String categoryId = '',
  String company = '',
  String size = '',
  String packUnit = 'box',
  int unitsPerPack = 10,
  String baseUnit = 'pcs',
}) => UnitConversionRule(
  id: id,
  categoryId: categoryId,
  company: company,
  size: size,
  packUnit: packUnit,
  unitsPerPack: unitsPerPack,
  baseUnit: baseUnit,
);

ProductModel _product({
  String id = 'p1',
  String categoryId = 'tiles',
  String company = 'Kajaria',
  String size = '600x600',
  String baseUnit = 'pcs',
  String packUnit = 'box',
  int unitsPerPack = 1,
  bool customConversion = false,
  int quantity = 0,
}) => ProductModel(
  id: id,
  name: 'Tile $id',
  categoryId: categoryId,
  company: company,
  size: size,
  quantity: quantity,
  unit: baseUnit,
  baseUnit: baseUnit,
  packUnit: packUnit,
  unitsPerPack: unitsPerPack,
  customConversion: customConversion,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  group('resolveUnitConversion', () {
    final everything = _rule('all', unitsPerPack: 2);
    final tiles = _rule('tiles', categoryId: 'tiles', unitsPerPack: 3);
    final kajaria = _rule('kajaria', company: 'Kajaria', unitsPerPack: 4);
    final big = _rule('big', size: '600x600', unitsPerPack: 5);
    final tilesKajaria = _rule(
      'tiles-kajaria',
      categoryId: 'tiles',
      company: 'Kajaria',
      unitsPerPack: 6,
    );

    UnitConversionRule? resolve(List<UnitConversionRule> rules) =>
        resolveUnitConversionFor(rules, _product());

    test('no rule covers a product outside every scope', () {
      expect(resolve([_rule('x', categoryId: 'paint')]), isNull);
    });

    test('an all-products rule is the fallback', () {
      expect(resolve([everything])?.id, 'all');
      expect(resolve([everything, tiles])?.id, 'tiles');
    });

    test('pinning more fields wins, whatever the order', () {
      expect(resolve([tilesKajaria, big, tiles])?.id, 'tiles-kajaria');
      expect(resolve([tiles, big, tilesKajaria])?.id, 'tiles-kajaria');
    });

    test('between single fields: sub-category, then brand, then category', () {
      expect(resolve([tiles, kajaria, big])?.id, 'big');
      expect(resolve([tiles, kajaria])?.id, 'kajaria');
    });
  });

  group('planUnitChange', () {
    final rule = _rule('r');

    test('no rule, nothing to do', () {
      expect(planUnitChange(_product(), null).kind, UnitChangeKind.none);
    });

    test('a product already following its rule is left alone', () {
      final p = _product(packUnit: 'Box', unitsPerPack: 10, baseUnit: 'PCS');
      expect(planUnitChange(p, rule).kind, UnitChangeKind.none);
    });

    test('counted in the base unit: only the pack changes', () {
      final change = planUnitChange(_product(unitsPerPack: 6), rule);
      expect(change.kind, UnitChangeKind.repack);
      expect(change.factor, 1);
      expect(change.writes, isTrue);
    });

    test('counted in the pack unit: stock is converted', () {
      final change = planUnitChange(_product(baseUnit: 'Box'), rule);
      expect(change.kind, UnitChangeKind.convertStock);
      expect(change.factor, 10);
    });

    test('counted in an unrelated unit: not touched', () {
      final change = planUnitChange(_product(baseUnit: 'kg'), rule);
      expect(change.kind, UnitChangeKind.unitMismatch);
      expect(change.writes, isFalse);
    });

    test('a custom product is kept unless asked to include it', () {
      final p = _product(unitsPerPack: 6, customConversion: true);
      expect(planUnitChange(p, rule).kind, UnitChangeKind.keptCustom);
      expect(
        planUnitChange(p, rule, includeCustom: true).kind,
        UnitChangeKind.repack,
      );
    });

    test('planUnitChanges lists only products that need something', () {
      final changes = planUnitChanges(
        [
          _product(id: 'follows', unitsPerPack: 10),
          _product(id: 'repack', unitsPerPack: 6),
          _product(id: 'boxed', baseUnit: 'box'),
          _product(id: 'uncovered', categoryId: 'paint'),
        ],
        [_rule('r', categoryId: 'tiles')],
      );
      expect(changes.map((c) => c.product.id), ['repack', 'boxed']);
    });
  });

  group('per-unit prices', () {
    test('divide exactly when they can', () {
      expect(perUnitPrice(100, 10), 10);
    });

    test('keep enough places that a whole pack re-totals', () {
      final each = perUnitPrice(100, 12);
      expect(each, 8.333333);
      // Invoice totals round to cents; at cents the pack is still ₹100.
      expect(((each * 12) * 100).roundToDouble() / 100, 100);
    });
  });

  group('convertedProductFields', () {
    test('scales every quantity and divides every price', () {
      final boxed = ProductModel(
        id: 'p1',
        name: 'Tile',
        categoryId: 'tiles',
        quantity: 50,
        heldQuantity: 5,
        unit: 'box',
        baseUnit: 'box',
        packUnit: 'carton',
        unitsPerPack: 4,
        locationQuantities: const {'Main': 40, 'In transit': 6, 'At vendor': 4},
        heldLocationQuantities: const {'Main': 3, '(unassigned)': 2},
        lowStockThreshold: 5,
        costPrice: 100,
        sellingPrice: 120,
        vendorPrices: const {'v1': 90},
        customConversion: true,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final at = DateTime(2026, 10, 27, 9);
      final fields = convertedProductFields(boxed, _rule('r'), at: at);

      expect(fields['quantity'], 500);
      expect(fields['locationQuantities'], {
        'Main': 400,
        'In transit': 60,
        'At vendor': 40,
      });
      expect(fields['heldQuantity'], 50);
      expect(fields['heldLocationQuantities'], {
        'Main': 30,
        '(unassigned)': 20,
      });
      expect(fields['lowStockThreshold'], 50);
      expect(fields['costPrice'], 10);
      expect(fields['sellingPrice'], 12);
      expect(fields['vendorPrices'], {'v1': 9});
      expect(fields['unit'], 'pcs');
      expect(fields['baseUnit'], 'pcs');
      expect(fields['packUnit'], 'box');
      expect(fields['unitsPerPack'], 10);
      expect(fields['customConversion'], isFalse);
      expect(fields['unitsConvertedAt'], Timestamp.fromDate(at));
    });

    test('a repack writes only pack fields', () {
      expect(repackFields(_rule('r')).keys, {
        'packUnit',
        'unitsPerPack',
        'customConversion',
      });
    });
  });

  group('related records', () {
    test('an open hold scales all three of its counts', () {
      expect(
        convertedHoldFields({
          'quantity': 5,
          'consumedQuantity': 2,
          'releasedQuantity': 1,
        }, 10),
        {'quantity': 50, 'consumedQuantity': 20, 'releasedQuantity': 10},
      );
    });

    test('a batch scales', () {
      expect(convertedBatchFields({'quantity': 7}, 10), {'quantity': 70});
    });

    test('a price list converts only its fixed price for the product', () {
      final fields = convertedPriceListFields(
        {
          'entries': [
            {
              'productId': 'p1',
              'mode': 'fixedPrice',
              'value': 100.0,
              'minQuantity': 2,
            },
            {
              'productId': 'p1',
              'mode': 'percentOff',
              'value': 10.0,
              'minQuantity': 5,
            },
            {
              'productId': 'p2',
              'mode': 'fixedPrice',
              'value': 100.0,
              'minQuantity': 2,
            },
          ],
        },
        'p1',
        10,
      );
      final entries = fields!['entries'] as List;
      expect(entries[0], containsPair('value', 10.0));
      expect(entries[0], containsPair('minQuantity', 20));
      expect(entries[1], containsPair('value', 10.0), reason: 'a percentage');
      expect(entries[1], containsPair('minQuantity', 50));
      expect(entries[2], containsPair('minQuantity', 2), reason: 'not p1');
    });

    test('a price list without the product is left alone', () {
      expect(
        convertedPriceListFields(
          {
            'entries': [
              {'productId': 'p2', 'mode': 'fixedPrice', 'value': 1.0},
            ],
          },
          'p1',
          10,
        ),
        isNull,
      );
    });

    test('a BOM scales the product as a component and as the output', () {
      final asComponent = convertedBomFields(
        {
          'outputProductId': 'kit',
          'outputQuantity': 1,
          'components': [
            {'productId': 'p1', 'quantity': 2, 'unit': 'box'},
            {'productId': 'p2', 'quantity': 3, 'unit': 'pcs'},
          ],
        },
        'p1',
        10,
        'pcs',
      );
      final components = asComponent!['components'] as List;
      expect(components[0], containsPair('quantity', 20));
      expect(components[0], containsPair('unit', 'pcs'));
      expect(components[1], containsPair('quantity', 3));
      expect(asComponent.containsKey('outputQuantity'), isFalse);

      final asOutput = convertedBomFields(
        {
          'outputProductId': 'p1',
          'outputQuantity': 1,
          'totalBuilt': 7,
          'components': const [],
        },
        'p1',
        10,
        'pcs',
      );
      expect(asOutput, {'outputQuantity': 10, 'totalBuilt': 70});
    });

    test('a recurring invoice keeps its line total', () {
      final fields = convertedRecurringInvoiceFields(
        {
          'items': [
            {
              'productId': 'p1',
              'quantity': 3,
              'unitPrice': 120.0,
              'unit': 'box',
            },
          ],
        },
        'p1',
        10,
        'pcs',
      );
      final line = (fields!['items'] as List).single as Map;
      expect(line['quantity'], 30);
      expect(line['unitPrice'], 12.0);
      expect(line['unit'], 'pcs');
      expect(
        (line['quantity'] as int) * (line['unitPrice'] as double),
        3 * 120.0,
      );
    });

    test('an applied landed cost reverses to a per-new-unit cost', () {
      final fields = convertedLandedCostFields(
        {
          'lines': [
            {
              'productId': 'p1',
              'quantity': 4,
              'baseUnitCost': 100.0,
              'allocatedAmount': 40.0,
              'previousUnitCost': 95.0,
            },
          ],
        },
        'p1',
        10,
      );
      final line = (fields!['lines'] as List).single as Map;
      expect(line['quantity'], 40);
      expect(line['baseUnitCost'], 10.0);
      expect(line['previousUnitCost'], 9.5);
      expect(line['allocatedAmount'], 40.0, reason: 'a line total');
    });
  });
}
