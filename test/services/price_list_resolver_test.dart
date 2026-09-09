import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/price_list_model.dart';
import 'package:stock_management/models/product_model.dart';
import 'package:stock_management/services/price_list_resolver.dart';

void main() {
  final now = DateTime(2026, 1, 1);

  ProductModel product({double selling = 100, double cost = 60}) => ProductModel(
    id: 'p1',
    name: 'Widget',
    categoryId: 'c1',
    quantity: 10,
    sellingPrice: selling,
    costPrice: cost,
    createdAt: now,
    updatedAt: now,
  );

  PriceListModel list({
    double defaultDiscount = 0,
    List<PriceListEntry> entries = const [],
    List<String> customers = const ['cust1'],
    bool active = true,
    DateTime? validUntil,
    String name = 'Wholesale',
  }) => PriceListModel(
    id: name,
    name: name,
    defaultDiscountPercent: defaultDiscount,
    entries: entries,
    customerIds: customers,
    isActive: active,
    validUntil: validUntil,
    createdAt: now,
    updatedAt: now,
  );

  group('resolve', () {
    test('falls back to the catalog price with no lists at all', () {
      const resolver = PriceListResolver([]);
      final price = resolver.resolve(product: product(), customerId: 'cust1');
      expect(price.unitPrice, 100);
      expect(price.source, PriceSource.catalog);
      expect(price.isDiscounted, isFalse);
    });

    test('falls back to the catalog price for a customer on no list', () {
      final resolver = PriceListResolver([list(defaultDiscount: 20)]);
      final price = resolver.resolve(product: product(), customerId: 'other');
      expect(price.unitPrice, 100);
      expect(price.source, PriceSource.catalog);
    });

    test('applies the blanket discount when the product has no entry', () {
      final resolver = PriceListResolver([list(defaultDiscount: 20)]);
      final price = resolver.resolve(product: product(), customerId: 'cust1');
      expect(price.unitPrice, 80);
      expect(price.source, PriceSource.listDefault);
      expect(price.discountPercent, 20);
    });

    test('a product entry beats the blanket discount', () {
      final resolver = PriceListResolver([
        list(
          defaultDiscount: 20,
          entries: const [
            PriceListEntry(
              productId: 'p1',
              mode: PriceListMode.fixedPrice,
              value: 55,
            ),
          ],
        ),
      ]);
      final price = resolver.resolve(product: product(), customerId: 'cust1');
      expect(price.unitPrice, 55);
      expect(price.source, PriceSource.listEntry);
    });

    test('prices margin-over-cost off the cost price, not the selling price', () {
      final resolver = PriceListResolver([
        list(
          entries: const [
            PriceListEntry(
              productId: 'p1',
              mode: PriceListMode.marginOverCost,
              value: 25,
            ),
          ],
        ),
      ]);
      final price = resolver.resolve(
        product: product(selling: 100, cost: 60),
        customerId: 'cust1',
      );
      expect(price.unitPrice, 75);
    });

    test('a quantity slab only applies once the quantity reaches it', () {
      final resolver = PriceListResolver([
        list(
          defaultDiscount: 5,
          entries: const [
            PriceListEntry(
              productId: 'p1',
              mode: PriceListMode.discountPercent,
              value: 30,
              minQuantity: 100,
            ),
          ],
        ),
      ]);
      expect(
        resolver.resolve(product: product(), customerId: 'cust1', quantity: 99)
            .unitPrice,
        95,
      );
      expect(
        resolver.resolve(product: product(), customerId: 'cust1', quantity: 100)
            .unitPrice,
        70,
      );
    });

    test('the highest slab the quantity reaches wins, whatever the order', () {
      final resolver = PriceListResolver([
        list(
          entries: const [
            PriceListEntry(
              productId: 'p1',
              mode: PriceListMode.discountPercent,
              value: 40,
              minQuantity: 500,
            ),
            PriceListEntry(
              productId: 'p1',
              mode: PriceListMode.discountPercent,
              value: 10,
              minQuantity: 10,
            ),
          ],
        ),
      ]);
      expect(
        resolver.resolve(product: product(), customerId: 'cust1', quantity: 500)
            .unitPrice,
        60,
      );
    });

    test('an inactive or expired list prices nothing', () {
      final inactive = PriceListResolver([
        list(defaultDiscount: 50, active: false),
      ]);
      expect(
        inactive.resolve(product: product(), customerId: 'cust1').unitPrice,
        100,
      );

      final expired = PriceListResolver([
        list(defaultDiscount: 50, validUntil: DateTime(2020, 1, 1)),
      ]);
      expect(
        expired.resolve(product: product(), customerId: 'cust1').unitPrice,
        100,
      );
    });

    test('a customer on two lists gets the better one, not an arbitrary one', () {
      // Document order must not decide the price.
      final resolver = PriceListResolver([
        list(defaultDiscount: 10, name: 'A'),
        list(defaultDiscount: 25, name: 'B'),
      ]);
      final price = resolver.resolve(product: product(), customerId: 'cust1');
      expect(price.unitPrice, 75);
      expect(price.listName, 'B');
    });

    test('a discount over 100% floors at zero rather than paying the customer', () {
      final resolver = PriceListResolver([
        list(
          entries: const [
            PriceListEntry(
              productId: 'p1',
              mode: PriceListMode.discountPercent,
              value: 150,
            ),
          ],
        ),
      ]);
      expect(
        resolver.resolve(product: product(), customerId: 'cust1').unitPrice,
        0,
      );
    });

    test('an empty customer id never matches a list', () {
      final resolver = PriceListResolver([
        list(defaultDiscount: 30, customers: const ['']),
      ]);
      expect(
        resolver.resolve(product: product(), customerId: '').unitPrice,
        100,
      );
    });
  });
}
