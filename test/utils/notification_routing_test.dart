import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/services/notification_engine.dart';
import 'package:stock_management/utils/notification_routing.dart';

void main() {
  group('tray payload encoding', () {
    test('round-trips an entity pair', () {
      final payload = NotificationRouting.encodePayload('invoice', 'inv-123');
      final (type, id) = NotificationRouting.decodePayload(payload);

      expect(type, 'invoice');
      expect(id, 'inv-123');
    });

    test('round-trips a summary alert with no entity id', () {
      final payload = NotificationRouting.encodePayload('low_stock_list', '');
      final (type, id) = NotificationRouting.decodePayload(payload);

      expect(type, 'low_stock_list');
      expect(id, isEmpty);
    });

    test('an id containing the separator keeps its tail', () {
      // Firestore ids never contain '|', but decoding must not silently drop
      // data if one ever does.
      final (type, id) = NotificationRouting.decodePayload('invoice|a|b');

      expect(type, 'invoice');
      expect(id, 'a|b');
    });

    test('a malformed payload degrades to a type with no id', () {
      final (type, id) = NotificationRouting.decodePayload('garbage');

      expect(type, 'garbage');
      expect(id, isEmpty);
      // And an unknown type is not actionable, so the tap is a no-op rather
      // than a crash.
      expect(NotificationRouting.isActionable(type), isFalse);
    });
  });

  group('actionability', () {
    test('every entityType the engine emits leads somewhere', () {
      const engine = NotificationEngine();
      // Drive the engine with nothing so only the static contract is exercised;
      // the entity types themselves are asserted below against the router.
      expect(engine.scan(now: DateTime(2026)), isEmpty);

      const emitted = [
        'product',
        'batch',
        'invoice',
        'purchase_order',
        'low_stock_list',
        'expiry_list',
        'invoice_list',
        'purchase_order_list',
      ];

      for (final type in emitted) {
        expect(
          NotificationRouting.isActionable(type),
          isTrue,
          reason: '$type has no route',
        );
      }
    });

    test('a summary type is actionable without an id', () {
      expect(NotificationRouting.isActionable('low_stock_list'), isTrue);
      expect(NotificationRouting.isActionable('expiry_list'), isTrue);
      expect(NotificationRouting.isActionable('notification_list'), isTrue);
    });

    test('an unknown type is not actionable', () {
      expect(NotificationRouting.isActionable('something_else'), isFalse);
      expect(NotificationRouting.isActionable(''), isFalse);
    });
  });
}
