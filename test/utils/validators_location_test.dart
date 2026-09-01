import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/utils/validators.dart';

void main() {
  group('validateLocationName', () {
    test('rejects a dot, which Firestore reads as a nested field path', () {
      // "Rack 1.2" used to be written as locationQuantities.Rack 1.2, creating
      // {Rack 1: {2: n}} — read back as 0, silently destroying the stock.
      expect(validateLocationName('Rack 1.2'), isNotNull);
    });

    test('rejects the other Firestore field-path metacharacters', () {
      for (final name in ['a/b', 'a~b', 'a*b', 'a[b', 'a]b']) {
        expect(validateLocationName(name), isNotNull, reason: name);
      }
    });

    test('rejects Firestore reserved __name__ style keys', () {
      expect(validateLocationName('__proto__'), isNotNull);
    });

    test('accepts ordinary warehouse names', () {
      for (final name in ['Main', 'Rack A', 'Aisle 3', 'Cold Store 2']) {
        expect(validateLocationName(name), isNull, reason: name);
      }
    });

    test('requires a value', () {
      expect(validateLocationName(''), isNotNull);
      expect(validateLocationName('   '), isNotNull);
      expect(validateLocationName(null), isNotNull);
    });
  });
}
