import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/product_model.dart';

/// Editing a product used to wipe every reservation on it.
///
/// `add_edit_product_screen` rebuilds a whole [ProductModel] from its form and
/// never populated `heldQuantity` / `heldLocationQuantities`, so they fell back
/// to the constructor defaults `0` and `{}`. `toMap()` serialises both, and
/// `updateProduct` wrote the whole map — so changing a low-stock threshold set
/// `heldQuantity` to 0 while the hold documents stayed `active`, releasing
/// reserved stock for someone else to sell.
///
/// [ProductModel.toEditableMap] is what closes that off at the model, so no
/// future screen can reintroduce it by forgetting a field.
void main() {
  ProductModel product() => ProductModel(
    id: 'p1',
    name: 'Widget',
    categoryId: 'c1',
    categoryName: 'Parts',
    quantity: 100,
    heldQuantity: 60,
    locationQuantities: const {'Main': 100},
    heldLocationQuantities: const {'Main': 60},
    lowStockThreshold: 10,
    costPrice: 5,
    sellingPrice: 9,
    createdAt: DateTime(2024, 1, 1),
    updatedAt: DateTime(2024, 6, 1),
    createdBy: 'u1',
    createdByName: 'Ada',
  );

  test('toMap still carries stock, for creating a product', () {
    final map = product().toMap();
    for (final field in ProductModel.stockOwnedFields) {
      expect(map.containsKey(field), isTrue, reason: '$field missing');
    }
  });

  test('toEditableMap omits every stock-owned field', () {
    final map = product().toEditableMap();
    for (final field in ProductModel.stockOwnedFields) {
      expect(map.containsKey(field), isFalse, reason: '$field must not be written');
    }
  });

  test('toEditableMap keeps the fields an edit is actually for', () {
    final map = product().toEditableMap();
    expect(map['name'], 'Widget');
    expect(map['lowStockThreshold'], 10);
    expect(map['costPrice'], 5);
    expect(map['sellingPrice'], 9);
    expect(map['categoryName'], 'Parts');
  });

  test('a form model that forgot the held fields cannot zero them', () {
    // Exactly what the edit screen produced: quantity and locations carried
    // across from the original, held fields left at their defaults.
    final fromForm = ProductModel(
      id: 'p1',
      name: 'Widget renamed',
      categoryId: 'c1',
      categoryName: 'Parts',
      quantity: 100,
      locationQuantities: const {'Main': 100},
      lowStockThreshold: 25,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 6, 2),
    );

    expect(fromForm.heldQuantity, 0, reason: 'the defaulting that caused it');

    final map = fromForm.toEditableMap();
    expect(map.containsKey('heldQuantity'), isFalse);
    expect(map.containsKey('heldLocationQuantities'), isFalse);
    expect(map['lowStockThreshold'], 25, reason: 'the intended edit still lands');
  });

  test('createdAt and createdBy are not rewritten by an edit', () {
    final map = product().toEditableMap();
    expect(map.containsKey('createdAt'), isFalse);
    expect(map.containsKey('createdBy'), isFalse);
    expect(map.containsKey('updatedAt'), isTrue);
  });
}
