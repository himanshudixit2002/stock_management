import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/product_model.dart';

void main() {
  group('ProductModel hold availability', () {
    test('computes available quantity and per-location availability', () {
      final product = ProductModel(
        id: 'p1',
        name: 'Widget',
        categoryId: 'c1',
        quantity: 100,
        heldQuantity: 25,
        locationQuantities: const {'Main': 70, 'Outlet': 30},
        heldLocationQuantities: const {'Main': 20, 'Outlet': 5},
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      expect(product.availableQuantity, 75);
      expect(product.availableAtLocation('Main'), 50);
      expect(product.availableAtLocation('Outlet'), 25);
    });

    test('unassigned (location-less) holds count against product availability',
        () {
      final product = ProductModel(
        id: 'p1',
        name: 'Widget',
        categoryId: 'c1',
        quantity: 100,
        heldQuantity: 30,
        locationQuantities: const {'Main': 70, 'Outlet': 30},
        heldLocationQuantities: const {
          'Main': 20,
          kUnassignedHoldLocation: 10,
        },
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      // Sentinel is excluded from real hold locations.
      expect(product.holdLocations, ['Main']);
      expect(product.unassignedHeldQuantity, 10);
      // Global available subtracts all holds (located + unassigned).
      expect(product.availableQuantity, 70);
    });

    test('availableForDispatchAtLocation caps by global availability', () {
      final product = ProductModel(
        id: 'p1',
        name: 'Widget',
        categoryId: 'c1',
        quantity: 100,
        // Everything is reserved by a location-less hold.
        heldQuantity: 100,
        locationQuantities: const {'Main': 70, 'Outlet': 30},
        heldLocationQuantities: const {kUnassignedHoldLocation: 100},
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      // No non-held units may be despatched even though stock is on hand.
      expect(product.availableQuantity, 0);
      expect(product.availableForDispatchAtLocation('Main'), 0);

      final partial = ProductModel(
        id: 'p2',
        name: 'Widget',
        categoryId: 'c1',
        quantity: 100,
        heldQuantity: 60,
        locationQuantities: const {'Main': 70, 'Outlet': 30},
        heldLocationQuantities: const {kUnassignedHoldLocation: 60},
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      // Global available is 40, so a 70-unit location is capped to 40.
      expect(partial.availableForDispatchAtLocation('Main'), 40);
      // A small location is capped by its own on-hand.
      expect(partial.availableForDispatchAtLocation('Outlet'), 30);
    });

    test('uses backward compatible unit defaults from map', () {
      final model = ProductModel.fromMap({
        'name': 'Legacy',
        'categoryId': 'c1',
        'quantity': 12,
        'unit': 'pcs',
        'createdAt': DateTime(2026, 1, 1),
        'updatedAt': DateTime(2026, 1, 1),
      }, 'p2');

      expect(model.baseUnit, 'pcs');
      expect(model.packUnit, 'box');
      expect(model.unitsPerPack, 1);
    });
  });
}
