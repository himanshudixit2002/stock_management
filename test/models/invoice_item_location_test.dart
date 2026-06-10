import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/invoice_model.dart';

void main() {
  group('InvoiceItem location', () {
    test('round-trips location through toMap/fromMap', () {
      final item = InvoiceItem(
        productId: 'p1',
        productName: 'Tea',
        quantity: 3,
        unitPrice: 50,
        location: 'Warehouse A',
      );

      final restored = InvoiceItem.fromMap(item.toMap());

      expect(restored.location, 'Warehouse A');
      expect(restored.productId, 'p1');
      expect(restored.quantity, 3);
    });

    test('defaults to empty location when absent (backward compatible)', () {
      final restored = InvoiceItem.fromMap({
        'productId': 'p1',
        'productName': 'Tea',
        'quantity': 1,
        'unitPrice': 50,
      });

      expect(restored.location, isEmpty);
    });

    test('copyWith updates location', () {
      final item = InvoiceItem(productId: 'p1', quantity: 1);
      final moved = item.copyWith(location: 'Shop Front');

      expect(item.location, isEmpty);
      expect(moved.location, 'Shop Front');
    });
  });
}
