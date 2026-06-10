import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/utils/unit_conversion.dart';

void main() {
  group('unit conversion helpers', () {
    test('converts pack + pieces to base quantity', () {
      final base = toBaseQuantity(packs: 2, pieces: 3, unitsPerPack: 10);
      expect(base, 23);
    });

    test('splits base quantity into packs and pieces', () {
      final split = splitBaseQuantity(baseQuantity: 23, unitsPerPack: 10);
      expect(split.packs, 2);
      expect(split.pieces, 3);
    });

    test('formats mixed quantity text', () {
      final formatted = formatQuantityWithUnits(
        baseQuantity: 23,
        baseUnit: 'pcs',
        packUnit: 'box',
        unitsPerPack: 10,
      );
      expect(formatted, '2 box 3 pcs');
    });
  });
}
