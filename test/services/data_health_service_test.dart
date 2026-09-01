import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/product_model.dart';
import 'package:stock_management/models/stock_hold_model.dart';
import 'package:stock_management/models/invoice_model.dart';
import 'package:stock_management/models/sales_order_model.dart';
import 'package:stock_management/services/data_health_service.dart';

ProductModel _product({
  String id = 'p1',
  String name = 'Widget',
  int quantity = 10,
  int heldQuantity = 0,
  Map<String, int> locations = const {'Main': 10},
  Map<String, int> held = const {},
}) {
  final now = DateTime(2026, 1, 1);
  return ProductModel(
    id: id,
    name: name,
    categoryId: 'c1',
    quantity: quantity,
    heldQuantity: heldQuantity,
    locationQuantities: locations,
    heldLocationQuantities: held,
    createdAt: now,
    updatedAt: now,
  );
}

List<DataHealthFinding> _findings(
  List<DataHealthCheck> checks,
  String checkId,
) => checks.firstWhere((c) => c.id == checkId).findings;

void main() {
  const service = DataHealthService();

  List<DataHealthCheck> scan({
    List<ProductModel> products = const [],
    List<StockHoldModel> holds = const [],
    List<InvoiceModel> invoices = const [],
    List<SalesOrderModel> orders = const [],
  }) => service.scan(
    products: products,
    holds: holds,
    invoices: invoices,
    salesOrders: orders,
  );

  group('DataHealthService', () {
    test('clean data produces no findings', () {
      final checks = scan(products: [_product()]);
      expect(checks.every((c) => c.passed), isTrue);
    });

    test('flags more reserved than on hand', () {
      // What damage/transfer/adjustment could produce before the held guard.
      final checks = scan(
        products: [_product(quantity: 5, heldQuantity: 8)],
      );
      expect(_findings(checks, 'held_exceeds_on_hand'), hasLength(1));
      expect(
        _findings(checks, 'held_exceeds_on_hand').first.severity,
        DataHealthSeverity.critical,
      );
    });

    test('flags a total that does not match its locations', () {
      final checks = scan(
        products: [
          _product(quantity: 10, locations: {'Main': 3, 'Back': 2}),
        ],
      );
      expect(_findings(checks, 'quantity_location_mismatch'), hasLength(1));
    });

    test('flags a reservation at a location holding no stock', () {
      final checks = scan(
        products: [
          _product(
            quantity: 10,
            heldQuantity: 4,
            locations: {'Main': 10},
            held: {'Back': 4},
          ),
        ],
      );
      expect(_findings(checks, 'held_without_stock'), hasLength(1));
    });

    test('accepts an unassigned reservation within the product total', () {
      final checks = scan(
        products: [
          _product(
            quantity: 10,
            heldQuantity: 4,
            locations: {'Main': 10},
            held: {kUnassignedHoldLocation: 4},
          ),
        ],
      );
      expect(_findings(checks, 'held_without_stock'), isEmpty);
    });

    test('flags a location name Firestore would read as a field path', () {
      // "Rack 1.2" is exactly what the old dotted-path write destroyed.
      final checks = scan(
        products: [_product(locations: {'Rack 1.2': 10})],
      );
      final found = _findings(checks, 'unsafe_location_name');
      expect(found, hasLength(1));
      expect(found.first.detail, contains('Rack 1.2'));
    });

    test('flags a hold left behind by a cancelled order', () {
      final now = DateTime(2026, 1, 1);
      final checks = scan(
        products: [_product()],
        holds: [
          StockHoldModel(
            id: 'h1',
            productId: 'p1',
            productName: 'Widget',
            location: 'Main',
            quantity: 3,
            status: StockHoldStatus.active,
            sourceType: StockHoldSourceType.salesOrder,
            sourceId: 'so1',
            createdAt: now,
            updatedAt: now,
          ),
        ],
        orders: [
          SalesOrderModel(
            id: 'so1',
            customerId: 'c1',
            status: SOStatus.cancelled,
            createdAt: now,
            updatedAt: now,
          ),
        ],
      );
      expect(_findings(checks, 'orphaned_hold'), hasLength(1));
    });

    test('flags a hold on a product that no longer exists', () {
      final now = DateTime(2026, 1, 1);
      final checks = scan(
        products: const [],
        holds: [
          StockHoldModel(
            id: 'h1',
            productId: 'gone',
            productName: 'Deleted Widget',
            location: 'Main',
            quantity: 2,
            status: StockHoldStatus.active,
            createdAt: now,
            updatedAt: now,
          ),
        ],
      );
      expect(_findings(checks, 'orphaned_hold'), hasLength(1));
    });

    test('flags a stock-moving invoice referencing a deleted product', () {
      final now = DateTime(2026, 1, 1);
      final checks = scan(
        products: [_product()],
        invoices: [
          InvoiceModel(
            id: 'i1',
            invoiceNumber: 'INV-0001',
            customerId: 'c1',
            status: InvoiceStatus.sent,
            stockDeducted: true,
            items: [
              InvoiceItem(productId: 'gone', productName: 'Ghost', quantity: 1),
            ],
            invoiceDate: now,
            dueDate: now,
            createdAt: now,
            updatedAt: now,
          ),
        ],
      );
      expect(_findings(checks, 'invoice_missing_product'), hasLength(1));
    });

    test('ignores a cancelled invoice referencing a deleted product', () {
      final now = DateTime(2026, 1, 1);
      final checks = scan(
        products: [_product()],
        invoices: [
          InvoiceModel(
            id: 'i1',
            invoiceNumber: 'INV-0002',
            customerId: 'c1',
            status: InvoiceStatus.cancelled,
            stockDeducted: true,
            items: [
              InvoiceItem(productId: 'gone', productName: 'Ghost', quantity: 1),
            ],
            invoiceDate: now,
            dueDate: now,
            createdAt: now,
            updatedAt: now,
          ),
        ],
      );
      expect(_findings(checks, 'invoice_missing_product'), isEmpty);
    });
  });
}
