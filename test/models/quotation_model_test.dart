import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/quotation_model.dart';

void main() {
  final now = DateTime(2026, 3, 10);

  QuotationModel quote({
    QuotationStatus status = QuotationStatus.draft,
    List<QuotationLine> lines = const [],
    DateTime? validUntil,
    String convertedId = '',
  }) => QuotationModel(
    id: 'q1',
    quoteNumber: 'Q-1',
    customerId: 'c1',
    customerName: 'Acme',
    status: status,
    lines: lines,
    validUntil: validUntil,
    convertedSalesOrderId: convertedId,
    createdAt: now,
    updatedAt: now,
  );

  group('totals', () {
    test('a line nets its discount before tax', () {
      const line = QuotationLine(
        productId: 'p1',
        quantity: 10,
        unitPrice: 100,
        discountPercent: 10,
        taxRate: 18,
      );
      expect(line.gross, 1000);
      expect(line.discountAmount, 100);
      expect(line.taxable, 900);
      expect(line.taxAmount, 162);
      expect(line.total, 1062);
    });

    test('quote totals are the sum of the lines', () {
      final q = quote(
        lines: const [
          QuotationLine(productId: 'p1', quantity: 2, unitPrice: 500),
          QuotationLine(
            productId: 'p2',
            quantity: 1,
            unitPrice: 1000,
            taxRate: 10,
          ),
        ],
      );
      expect(q.subtotal, 2000);
      expect(q.totalTax, 100);
      expect(q.grandTotal, 2100);
      expect(q.totalUnits, 3);
    });
  });

  group('lapsing', () {
    test('a sent quote past its date reads as expired without being stamped', () {
      // Nothing sweeps the collection, so lapse is computed. The stored status
      // stays "sent" until somebody acts on it — which keeps "nobody answered"
      // distinguishable from "they said no".
      final q = quote(
        status: QuotationStatus.sent,
        validUntil: now.subtract(const Duration(days: 1)),
      );
      expect(q.hasLapsed, isTrue);
      expect(q.status, QuotationStatus.sent);
      expect(q.effectiveStatus, QuotationStatus.expired);
      expect(q.statusLabel, 'Expired');
    });

    test('a draft never lapses', () {
      final q = quote(validUntil: now.subtract(const Duration(days: 30)));
      expect(q.hasLapsed, isFalse);
    });

    test('a quote with no validity date is open-ended', () {
      final q = quote(status: QuotationStatus.sent);
      expect(q.hasLapsed, isFalse);
      expect(q.daysToExpiry, isNull);
    });
  });

  group('transitions', () {
    test('only a draft with lines can be sent', () {
      expect(quote().canSend, isFalse);
      expect(
        quote(
          lines: const [QuotationLine(productId: 'p1')],
        ).canSend,
        isTrue,
      );
      expect(
        quote(
          status: QuotationStatus.sent,
          lines: const [QuotationLine(productId: 'p1')],
        ).canSend,
        isFalse,
      );
    });

    test('a lapsed quote can still be answered', () {
      // A customer who calls back a week late is still a customer.
      expect(quote(status: QuotationStatus.expired).canDecide, isTrue);
      expect(quote(status: QuotationStatus.sent).canDecide, isTrue);
      expect(quote(status: QuotationStatus.draft).canDecide, isFalse);
    });

    test('only an accepted quote converts, and only once', () {
      expect(quote(status: QuotationStatus.accepted).canConvert, isTrue);
      expect(quote(status: QuotationStatus.sent).canConvert, isFalse);
      expect(
        quote(status: QuotationStatus.accepted, convertedId: 'so1').canConvert,
        isFalse,
      );
    });

    test('only a draft can be deleted', () {
      expect(quote().canDelete, isTrue);
      expect(quote(status: QuotationStatus.sent).canDelete, isFalse);
    });
  });

  group('serialisation', () {
    test('round-trips through a map', () {
      final original = quote(
        status: QuotationStatus.sent,
        validUntil: DateTime(2026, 4, 1),
        lines: const [
          QuotationLine(
            productId: 'p1',
            productName: 'Widget',
            unit: 'pcs',
            quantity: 4,
            unitPrice: 250,
            discountPercent: 5,
            taxRate: 18,
          ),
        ],
      );
      final restored = QuotationModel.fromMap(original.toMap(), 'q1');
      expect(restored.status, QuotationStatus.sent);
      expect(restored.quoteNumber, 'Q-1');
      expect(restored.validUntil, DateTime(2026, 4, 1));
      expect(restored.lines.single.productName, 'Widget');
      expect(restored.grandTotal, closeTo(original.grandTotal, 0.0001));
    });

    test('a document with no lines or dates reads back safely', () {
      final restored = QuotationModel.fromMap(const {}, 'q9');
      expect(restored.status, QuotationStatus.draft);
      expect(restored.lines, isEmpty);
      expect(restored.validUntil, isNull);
      expect(restored.grandTotal, 0);
    });

    test('the map carries denormalised totals for the list header', () {
      final map = quote(
        lines: const [
          QuotationLine(productId: 'p1', quantity: 2, unitPrice: 100),
        ],
      ).toMap();
      expect(map['grandTotal'], 200);
      expect(map['totalUnits'], 2);
    });
  });
}
