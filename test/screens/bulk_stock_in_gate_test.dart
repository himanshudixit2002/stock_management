import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/screens/bulk/bulk_stock_in_gate.dart';

void main() {
  BulkStockInGate gate({
    bool loaded = true,
    bool loadingAnalytics = false,
    bool loadingProducts = false,
    int products = 3,
    int locations = 2,
  }) => bulkStockInGate(
    isFullCatalogLoaded: loaded,
    isLoadingAnalytics: loadingAnalytics,
    isLoadingProducts: loadingProducts,
    productCount: products,
    locationCount: locations,
  );

  group('the regression this gate exists for', () {
    test('products but no locations blocks with the locations message', () {
      // Previously this fell through to the form, which then refused to submit
      // with "Please select a location for each row" and no way to add one.
      expect(gate(products: 3, locations: 0), BulkStockInGate.noLocations);
    });

    test('products and locations reaches the form', () {
      expect(gate(products: 3, locations: 2), BulkStockInGate.ready);
    });
  });

  group('loading is distinct from empty', () {
    test('nothing loaded yet and a fetch in flight is loading, not empty', () {
      expect(
        gate(loaded: false, products: 0, loadingAnalytics: true),
        BulkStockInGate.loading,
      );
      expect(
        gate(loaded: false, products: 0, loadingProducts: true),
        BulkStockInGate.loading,
      );
    });

    test('no fetch in flight and nothing to show is empty, not loading', () {
      expect(gate(loaded: false, products: 0), BulkStockInGate.noProducts);
    });

    test('a finished load wins over a stale in-flight flag', () {
      // isFullCatalogLoaded is authoritative: once it flips, an empty catalog
      // is a fact rather than a pending answer, so the screen must stop
      // spinning even if a loading flag is still set.
      expect(
        gate(loaded: true, products: 0, loadingAnalytics: true),
        BulkStockInGate.noProducts,
      );
    });

    test('products already in hand never show a spinner', () {
      expect(
        gate(loaded: false, products: 5, loadingAnalytics: true),
        BulkStockInGate.ready,
      );
    });
  });

  test('with neither, "add a product" is the more useful thing to say', () {
    expect(gate(products: 0, locations: 0), BulkStockInGate.noProducts);
  });
}
