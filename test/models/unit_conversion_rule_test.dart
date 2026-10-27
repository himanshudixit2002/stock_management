import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/unit_conversion_rule.dart';

UnitConversionRule _rule({
  String id = 'r1',
  String categoryId = '',
  String company = '',
  String size = '',
  String packUnit = 'box',
  int unitsPerPack = 10,
  String baseUnit = 'pcs',
}) => UnitConversionRule(
  id: id,
  categoryId: categoryId,
  company: company,
  size: size,
  packUnit: packUnit,
  unitsPerPack: unitsPerPack,
  baseUnit: baseUnit,
);

void main() {
  group('matching', () {
    test('an empty scope covers every product', () {
      final rule = _rule();
      expect(rule.coversEverything, isTrue);
      expect(
        rule.matches(categoryId: 'c1', company: 'Acme', size: 'L'),
        isTrue,
      );
      expect(rule.matches(categoryId: '', company: '', size: ''), isTrue);
    });

    test('category is compared exactly, by id', () {
      final rule = _rule(categoryId: 'tiles');
      expect(rule.matches(categoryId: 'tiles', company: '', size: ''), isTrue);
      expect(rule.matches(categoryId: 'Tiles', company: '', size: ''), isFalse);
      expect(rule.matches(categoryId: '', company: '', size: ''), isFalse);
    });

    test('brand and sub-category ignore case and stray spaces', () {
      // They are typed by hand, and SettingsProvider already treats "Kajaria"
      // and "kajaria " as one brand.
      final rule = _rule(company: 'Kajaria', size: '600x600');
      expect(
        rule.matches(categoryId: 'x', company: 'kajaria ', size: '600X600'),
        isTrue,
      );
      expect(
        rule.matches(categoryId: 'x', company: 'Somany', size: '600x600'),
        isFalse,
      );
    });
  });

  group('specificity and precedence', () {
    test('count the pinned scope fields', () {
      expect(_rule().specificity, 0);
      expect(_rule(categoryId: 'c').specificity, 1);
      expect(_rule(company: 'A', size: 'L').specificity, 2);
      expect(_rule(categoryId: 'c', company: 'A', size: 'L').specificity, 3);
    });

    test('rank a sub-category over a brand over a category', () {
      expect(
        _rule(size: 'L').precedence,
        greaterThan(_rule(company: 'A').precedence),
      );
      expect(
        _rule(company: 'A').precedence,
        greaterThan(_rule(categoryId: 'c').precedence),
      );
    });

    test('two rules naming the same scope are the same scope', () {
      expect(
        _rule(company: 'Acme').sameScopeAs(_rule(id: 'r2', company: 'acme ')),
        isTrue,
      );
      expect(
        _rule(company: 'Acme').sameScopeAs(_rule(id: 'r2', size: 'Acme')),
        isFalse,
      );
    });
  });

  group('validation', () {
    test('a sound rule has no error', () {
      expect(_rule().validationError, isNull);
    });

    test('a pack of one is not a pack', () {
      expect(_rule(unitsPerPack: 1).validationError, isNotNull);
      expect(_rule(unitsPerPack: 0).validationError, isNotNull);
    });

    test('the pack and the unit inside it must differ', () {
      expect(
        _rule(packUnit: 'Box', baseUnit: 'box').validationError,
        isNotNull,
      );
    });

    test('both units are required', () {
      expect(_rule(packUnit: ' ').validationError, isNotNull);
      expect(_rule(baseUnit: '').validationError, isNotNull);
    });
  });

  group('storage', () {
    test('round-trips through a map', () {
      final rule = _rule(
        categoryId: 'c1',
        company: 'Acme',
        size: 'L',
      ).copyWith(updatedAt: DateTime(2026, 1, 2), updatedByName: 'Ada');
      final back = UnitConversionRule.fromMap(rule.toMap());
      expect(back.id, rule.id);
      expect(back.categoryId, 'c1');
      expect(back.company, 'Acme');
      expect(back.size, 'L');
      expect(back.label, '1 box = 10 pcs');
      expect(back.updatedAt, DateTime(2026, 1, 2));
      expect(back.updatedByName, 'Ada');
    });

    test('a bad entry in settings is dropped, not fatal', () {
      final rules = UnitConversionRule.listFromSettings([
        _rule().toMap(),
        'not a map',
        {'id': 'r2', 'packUnit': 'box', 'unitsPerPack': 1, 'baseUnit': 'pcs'},
        {'packUnit': 'box', 'unitsPerPack': 10, 'baseUnit': 'pcs'},
      ]);
      expect(rules.map((r) => r.id), ['r1']);
    });

    test('a missing list reads as no rules', () {
      expect(UnitConversionRule.listFromSettings(null), isEmpty);
    });
  });
}
