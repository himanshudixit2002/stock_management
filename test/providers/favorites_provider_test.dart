import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/providers/favorites_provider.dart';

void main() {
  group('FavoritesProvider', () {
    late FavoritesProvider provider;

    setUp(() {
      provider = FavoritesProvider();
    });

    test('starts with empty favorites', () {
      expect(provider.ids, isEmpty);
    });

    test('toggle adds and removes product', () {
      provider.toggle('product-1');
      expect(provider.isFavorite('product-1'), isTrue);
      expect(provider.ids.length, 1);

      provider.toggle('product-1');
      expect(provider.isFavorite('product-1'), isFalse);
      expect(provider.ids, isEmpty);
    });

    test('reset clears all favorites', () {
      provider.toggle('product-1');
      provider.toggle('product-2');
      expect(provider.ids.length, 2);

      provider.reset();
      expect(provider.ids, isEmpty);
    });

    test('notifies listeners on toggle', () {
      int callCount = 0;
      provider.addListener(() => callCount++);

      provider.toggle('product-1');
      expect(callCount, 1);

      provider.toggle('product-1');
      expect(callCount, 2);
    });
  });
}
