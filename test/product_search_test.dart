import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/product_model.dart';
import 'package:stock_management/utils/product_search.dart';

DateTime get _t => DateTime(2024, 6, 1);

ProductModel _product({
  String id = 'p1',
  String name = 'Product',
  String categoryId = 'c1',
  String categoryName = '',
  String company = '',
  String size = '',
  int quantity = 10,
  int lowStockThreshold = 10,
  String description = '',
  String barcode = '',
  String preferredVendorName = '',
  String lastVendorName = '',
  Map<String, int> locationQuantities = const {},
}) {
  return ProductModel(
    id: id,
    name: name,
    categoryId: categoryId,
    categoryName: categoryName,
    company: company,
    size: size,
    quantity: quantity,
    lowStockThreshold: lowStockThreshold,
    description: description,
    barcode: barcode,
    preferredVendorName: preferredVendorName,
    lastVendorName: lastVendorName,
    locationQuantities: locationQuantities,
    createdAt: _t,
    updatedAt: _t,
  );
}

void main() {
  group('productMatchesBarcodeScan', () {
    test('exact match ignoring case', () {
      final p = _product(barcode: '5901234123457');
      expect(productMatchesBarcodeScan(p, '5901234123457'), isTrue);
      expect(productMatchesBarcodeScan(p, '5901234123457 '), isTrue);
      expect(productMatchesBarcodeScan(p, '5901234123458'), isFalse);
    });

    test('compact match across punctuation', () {
      final p = _product(barcode: '890-123-456');
      expect(productMatchesBarcodeScan(p, '890123456'), isTrue);
      expect(productMatchesBarcodeScan(p, '890 123 456'), isTrue);
    });

    test('empty stored barcode never matches', () {
      final p = _product(barcode: '');
      expect(productMatchesBarcodeScan(p, '123'), isFalse);
    });
  });

  group('productsMatchingBarcodeOrName', () {
    test('finds by barcode scan normalization', () {
      final list = [
        _product(id: 'a', name: 'Other', barcode: '111-222-333'),
        _product(id: 'b', name: 'X', barcode: '999'),
      ];
      final r = productsMatchingBarcodeOrName(list, '111222333');
      expect(r.map((e) => e.id).toList(), ['a']);
    });

    test('finds by name substring', () {
      final list = [_product(id: 'a', name: 'Milk Carton', barcode: '')];
      final r = productsMatchingBarcodeOrName(list, 'milk');
      expect(r, hasLength(1));
    });
  });

  group('parseProductSearchQuery', () {
    test('extracts stock and free-text tokens', () {
      final q = parseProductSearchQuery('stock:low organic milk');
      expect(q.filters.stock, 'low');
      expect(q.freeTextTokens, ['organic', 'milk']);
    });

    test('category filter and remaining tokens', () {
      final q = parseProductSearchQuery('cat:beverages cola');
      expect(q.filters.categorySubstr, 'beverages');
      expect(q.freeTextTokens, ['cola']);
    });
  });

  group('searchProductsRanked', () {
    test('multi-token requires each token to match (exact or fuzzy)', () {
      final catalog = [
        _product(id: 'a', name: 'Red Organic Apple'),
        _product(id: 'b', name: 'Red Tomato'),
      ];
      final r = searchProductsRanked(catalog, 'red apple');
      expect(r.map((e) => e.product.id).toList(), ['a']);
    });

    test('typo-tolerant multi-token search', () {
      final catalog = [
        _product(id: 'x', name: 'Samsung Galaxy Case'),
      ];
      final r = searchProductsRanked(catalog, 'samsng galxy');
      expect(r, isNotEmpty);
      expect(r.first.product.id, 'x');
    });

    test('typo in product name matches via fuzzy', () {
      final catalog = [
        _product(id: 'p', name: 'iPhone 15 Cover'),
      ];
      final r = searchProductsRanked(catalog, 'iphnoe');
      expect(r, isNotEmpty);
      expect(r.first.product.id, 'p');
    });

    test('compact barcode matches hyphenated barcode', () {
      final catalog = [
        _product(id: 'x', name: 'SKU Item', barcode: '890-123-456'),
      ];
      final r = searchProductsRanked(catalog, '890123456');
      expect(r, hasLength(1));
      expect(r.first.product.id, 'x');
      expect(r.first.matchHint, 'Barcode');
    });

    test('name match ranks above description-only match', () {
      final catalog = [
        _product(id: 'descOnly', name: 'ZZZ', description: 'widget spare part'),
        _product(id: 'nameHit', name: 'Widget Pro', description: 'other'),
      ];
      final r = searchProductsRanked(catalog, 'widget');
      expect(r.first.product.id, 'nameHit');
    });

    test('stock:low filter', () {
      final catalog = [
        _product(id: 'in', name: 'A', quantity: 100, lowStockThreshold: 10),
        _product(id: 'low', name: 'B', quantity: 3, lowStockThreshold: 10),
        _product(id: 'out', name: 'C', quantity: 0, lowStockThreshold: 10),
      ];
      final r = searchProductsRanked(catalog, 'stock:low');
      expect(r.map((e) => e.product.id).toList(), ['low']);
    });

    test('cat: substring filter', () {
      final catalog = [
        _product(id: '1', name: 'X', categoryName: 'Office Supplies'),
        _product(id: '2', name: 'Y', categoryName: 'Snacks'),
      ];
      final r = searchProductsRanked(catalog, 'cat:snacks');
      expect(r.map((e) => e.product.id).toList(), ['2']);
    });

    test('loc: matches location key', () {
      final catalog = [
        _product(id: '1', name: 'P', locationQuantities: {'Warehouse A': 5}),
        _product(id: '2', name: 'Q', locationQuantities: {'Shelf 1': 2}),
      ];
      final r = searchProductsRanked(catalog, 'loc:warehouse');
      expect(r.map((e) => e.product.id).toList(), ['1']);
    });
  });
}
