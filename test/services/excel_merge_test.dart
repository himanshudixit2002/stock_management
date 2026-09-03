import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/product_model.dart';
import 'package:stock_management/services/excel_service.dart';

/// An import whose sheet listed the same product twice silently lost stock.
///
/// Every row was matched and merged on its own, so both rows computed
/// `existing + row` from the *same* base. `bulkUpdateProducts` then wrote the
/// same document twice inside one Firestore batch, where writes apply in order
/// and the last one wins — so 100 in stock plus rows of 10 and 5 finished at
/// 105 rather than 115, and the import reported success.
void main() {
  final service = ExcelService();

  ProductModel existing({
    String id = 'p1',
    String name = 'Widget',
    int quantity = 100,
    Map<String, int> locations = const {'Main': 100},
    String barcode = '',
  }) => ProductModel(
    id: id,
    name: name,
    categoryId: 'c1',
    categoryName: 'Parts',
    quantity: quantity,
    locationQuantities: locations,
    barcode: barcode,
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );

  ProductModel row({
    String name = 'Widget',
    int quantity = 0,
    Map<String, int> locations = const {},
    String barcode = '',
    double costPrice = 0,
    int lowStockThreshold = 0,
  }) => ProductModel(
    id: '',
    name: name,
    categoryId: '',
    categoryName: 'Parts',
    quantity: quantity,
    locationQuantities: locations,
    barcode: barcode,
    costPrice: costPrice,
    lowStockThreshold: lowStockThreshold,
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );

  test('duplicate rows for one product sum instead of overwriting', () {
    final result = service.matchExistingProducts(
      importedProducts: [
        row(quantity: 10, locations: {'Main': 10}),
        row(quantity: 5, locations: {'Main': 5}),
      ],
      existingProducts: [existing()],
    );

    expect(result.updates, hasLength(1), reason: 'one write, not two');
    expect(result.updates.single.merged.quantity, 115);
    expect(result.updates.single.merged.locationQuantities['Main'], 115);
    expect(result.newProducts, isEmpty);
  });

  test('duplicate rows landing in different locations both count', () {
    final result = service.matchExistingProducts(
      importedProducts: [
        row(quantity: 10, locations: {'Main': 10}),
        row(quantity: 5, locations: {'Bay 3': 5}),
      ],
      existingProducts: [existing()],
    );

    final merged = result.updates.single.merged;
    expect(merged.quantity, 115);
    expect(merged.locationQuantities['Main'], 110);
    expect(merged.locationQuantities['Bay 3'], 5);
  });

  test('rows matched by barcode are grouped too', () {
    final result = service.matchExistingProducts(
      importedProducts: [
        row(name: 'Widget A', quantity: 10, barcode: 'ABC'),
        row(name: 'Widget B', quantity: 5, barcode: 'abc'),
      ],
      existingProducts: [existing(barcode: 'ABC')],
    );

    expect(result.updates, hasLength(1));
    expect(result.updates.single.merged.quantity, 115);
  });

  test('a later row fills a blank without a blank overwriting a value', () {
    final result = service.matchExistingProducts(
      importedProducts: [
        row(quantity: 10, costPrice: 7.5, lowStockThreshold: 0),
        row(quantity: 5, costPrice: 0, lowStockThreshold: 20),
      ],
      existingProducts: [existing()],
    );

    final merged = result.updates.single.merged;
    expect(merged.costPrice, 7.5, reason: 'not wiped by the blank second row');
    expect(merged.lowStockThreshold, 20);
  });

  test('duplicate new products are created once, not twice', () {
    final result = service.matchExistingProducts(
      importedProducts: [
        row(name: 'Brand New', quantity: 4),
        row(name: 'Brand New', quantity: 6),
      ],
      existingProducts: const [],
    );

    expect(result.updates, isEmpty);
    expect(result.newProducts, hasLength(1));
    expect(result.newProducts.single.quantity, 10);
  });

  test('distinct products are still handled separately', () {
    final result = service.matchExistingProducts(
      importedProducts: [
        row(name: 'Widget', quantity: 10),
        row(name: 'Gadget', quantity: 5),
      ],
      existingProducts: [
        existing(),
        existing(id: 'p2', name: 'Gadget', quantity: 20, locations: {'Main': 20}),
      ],
    );

    expect(result.updates, hasLength(2));
    final byId = {
      for (final u in result.updates) u.existing.id: u.merged.quantity,
    };
    expect(byId['p1'], 110);
    expect(byId['p2'], 25);
  });

  test('a single row behaves exactly as before', () {
    final result = service.matchExistingProducts(
      importedProducts: [row(quantity: 10, locations: {'Main': 10})],
      existingProducts: [existing()],
    );
    expect(result.updates.single.merged.quantity, 110);
  });
}
