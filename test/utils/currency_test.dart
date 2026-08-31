import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/utils/currency.dart';

void main() {
  group('Money.symbolOrFallback', () {
    test('returns the configured symbol when set', () {
      expect(Money.symbolOrFallback(r'$'), r'$');
      expect(Money.symbolOrFallback('AED'), 'AED');
    });

    test('falls back when the symbol is null, empty or whitespace', () {
      expect(Money.symbolOrFallback(null), Money.fallbackSymbol);
      expect(Money.symbolOrFallback(''), Money.fallbackSymbol);
      expect(Money.symbolOrFallback('   '), Money.fallbackSymbol);
    });

    test('trims surrounding whitespace', () {
      expect(Money.symbolOrFallback(r'  $ '), r'$');
    });
  });

  group('Money.withSymbol', () {
    test('prefixes the symbol and groups with two decimals by default', () {
      expect(Money.withSymbol(r'$', 1234.5), r'$1,234.50');
    });

    test('honours a decimals override', () {
      expect(Money.withSymbol(r'$', 1234.5, decimals: 0), r'$1,235');
      expect(Money.withSymbol(r'$', 1234.567, decimals: 3), r'$1,234.567');
    });

    test('uses the fallback symbol when none is configured', () {
      expect(Money.withSymbol('', 10), '${Money.fallbackSymbol}10.00');
    });

    test('keeps the sign inside the amount for negatives', () {
      expect(Money.withSymbol(r'$', -5), r'$-5.00');
    });
  });

  group('Money.number', () {
    test('formats without a symbol', () {
      expect(Money.number(1234.5), '1,234.50');
      expect(Money.number(0), '0.00');
    });
  });

  group('Money.compactWithSymbol', () {
    test('abbreviates at crore, lakh and thousand thresholds', () {
      expect(Money.compactWithSymbol(r'$', 12000000), r'$1.2Cr');
      expect(Money.compactWithSymbol(r'$', 340000), r'$3.4L');
      expect(Money.compactWithSymbol(r'$', 5600), r'$5.6K');
    });

    test('uses the full format below one thousand', () {
      expect(Money.compactWithSymbol(r'$', 999.5), r'$999.50');
    });

    test('abbreviates negatives by magnitude, keeping the sign', () {
      expect(Money.compactWithSymbol(r'$', -340000), r'$-3.4L');
    });

    test('boundaries land on the larger unit', () {
      expect(Money.compactWithSymbol(r'$', 100000), r'$1.0L');
      expect(Money.compactWithSymbol(r'$', 10000000), r'$1.0Cr');
    });
  });

  group('Money.compactNumber', () {
    test('abbreviates without a symbol', () {
      expect(Money.compactNumber(5600), '5.6K');
      expect(Money.compactNumber(12000000), '1.2Cr');
      expect(Money.compactNumber(12), '12.00');
    });
  });
}
