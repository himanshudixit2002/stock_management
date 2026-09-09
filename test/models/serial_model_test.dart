import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/serial_model.dart';

void main() {
  final now = DateTime(2026, 1, 1);

  SerialModel serial({
    String number = 'SN-001',
    SerialStatus status = SerialStatus.inStock,
    List<SerialEvent> history = const [],
    DateTime? warrantyUntil,
  }) => SerialModel(
    id: 's1',
    serialNumber: number,
    productId: 'p1',
    status: status,
    history: history,
    warrantyUntil: warrantyUntil,
    createdAt: now,
    updatedAt: now,
  );

  group('normalizeSerial', () {
    test('upper-cases, trims and collapses inner whitespace', () {
      // A serial number that identifies two units identifies neither, so
      // lookup has to be insensitive to how it was typed.
      expect(SerialModel.normalizeSerial('  sn 001 '), 'SN 001');
      expect(SerialModel.normalizeSerial('sn\t\t001'), 'SN 001');
      expect(SerialModel.normalizeSerial('SN-001'), 'SN-001');
    });

    test('an empty or whitespace-only number normalizes to empty', () {
      expect(SerialModel.normalizeSerial('   '), '');
    });
  });

  test('the key is derived from the number on construction', () {
    expect(serial(number: ' sn 7 ').serialKey, 'SN 7');
  });

  test('changing the number re-derives the key', () {
    final renamed = serial(number: 'A-1').copyWith(serialNumber: 'b 2');
    expect(renamed.serialKey, 'B 2');
  });

  test('a copyWith that does not touch the number keeps the key', () {
    final moved = serial(number: 'a 1').copyWith(location: 'Depot');
    expect(moved.serialKey, 'A 1');
  });

  group('status', () {
    test('units we still hold count as on hand', () {
      expect(serial(status: SerialStatus.inStock).isOnHand, isTrue);
      expect(serial(status: SerialStatus.allocated).isOnHand, isTrue);
      expect(serial(status: SerialStatus.returned).isOnHand, isTrue);
      expect(serial(status: SerialStatus.sold).isOnHand, isFalse);
      expect(serial(status: SerialStatus.scrapped).isOnHand, isFalse);
    });

    test('an unknown stored status reads as in stock rather than throwing', () {
      expect(SerialModel.statusFromString('nonsense'), SerialStatus.inStock);
    });
  });

  group('warranty', () {
    test('is live only until the end date', () {
      expect(
        serial(warrantyUntil: DateTime(2099, 1, 1)).isUnderWarranty,
        isTrue,
      );
      expect(
        serial(warrantyUntil: DateTime(2020, 1, 1)).isUnderWarranty,
        isFalse,
      );
      expect(serial().isUnderWarranty, isFalse);
    });
  });

  group('withEvent', () {
    test('appends the event and moves the status', () {
      final moved = serial().withEvent(
        SerialEvent(action: 'Sold', at: now),
        status: SerialStatus.sold,
      );
      expect(moved.status, SerialStatus.sold);
      expect(moved.history.single.action, 'Sold');
      expect(moved.updatedAt, now);
    });

    test('caps the history so one unit cannot grow without bound', () {
      var unit = serial();
      for (var i = 0; i < SerialModel.historyLimit + 10; i++) {
        unit = unit.withEvent(SerialEvent(action: 'Move $i', at: now));
      }
      expect(unit.history, hasLength(SerialModel.historyLimit));
      // The oldest entries fall off the front, so the most recent survive.
      expect(unit.history.last.action, 'Move ${SerialModel.historyLimit + 9}');
    });
  });

  group('serialization', () {
    test('round-trips through a map', () {
      final original = serial(
        number: 'sn 9',
        status: SerialStatus.allocated,
        history: [SerialEvent(action: 'Registered', at: now)],
      );
      final restored = SerialModel.fromMap(original.toMap(), 's1');
      expect(restored.serialKey, 'SN 9');
      expect(restored.status, SerialStatus.allocated);
      expect(restored.history.single.action, 'Registered');
    });

    test('a document written before serialKey existed still resolves', () {
      final restored = SerialModel.fromMap(const {
        'serialNumber': 'sn 4',
        'productId': 'p1',
      }, 's1');
      expect(restored.serialKey, 'SN 4');
    });
  });
}
