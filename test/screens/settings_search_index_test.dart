import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/config/feature_access.dart';
import 'package:stock_management/config/permissions.dart';
import 'package:stock_management/config/settings_catalog.dart';
import 'package:stock_management/screens/settings/settings_search.dart';

SettingsVisibilityContext _admin({
  FeatureGateState gates = const FeatureGateState(
    billing: true,
    barcode: true,
    vendors: true,
    pricing: true,
  ),
  bool isWeb = false,
}) => SettingsVisibilityContext(
  permissions: AppPermissions.allTrue(),
  gates: gates,
  isWeb: isWeb,
);

String _topHit(String query, {SettingsVisibilityContext? ctx}) {
  final hits = searchSettings(query, ctx: ctx ?? _admin());
  expect(hits, isNotEmpty, reason: 'no result for "$query"');
  return hits.first.leaf.id;
}

void main() {
  group('settings a flat-list search could never find', () {
    // Each of these lives one page deeper than the old Settings screen ever
    // built, so every one of them used to return "Nothing matches".
    test('currency finds the currency symbol in Billing', () {
      expect(_topHit('currency'), 'billing.currency');
    });

    test('gst finds the tax rate on a keyword alone', () {
      // "gst" appears in no title and no subtitle — only in the keywords.
      expect(_topHit('gst'), 'billing.taxRate');
    });

    test('expiry finds the expiry warning window', () {
      expect(_topHit('expiry'), 'notifications.expiryWindow');
    });

    test('dark finds the theme setting', () {
      expect(_topHit('dark'), 'appearance.theme');
    });

    test('invoice prefix finds invoice numbering', () {
      expect(_topHit('invoice prefix'), 'billing.invoiceNumbering');
    });

    test('delete account finds the danger zone', () {
      expect(_topHit('delete account'), 'account.delete');
    });

    test('a few more words people actually type', () {
      expect(_topHit('password'), 'account.password');
      expect(_topHit('shelf'), 'catalog.locations');
      expect(_topHit('spreadsheet'), 'data.import');
      expect(_topHit('rbac'), 'team.roles');
    });
  });

  group('breadcrumbs', () {
    test('name the page and the group a hit lives in', () {
      final hits = searchSettings('gst', ctx: _admin());
      expect(hits.first.breadcrumb, 'Billing & invoicing · Tax');
    });

    test('fall back to the category when a leaf has no group', () {
      final leaf = SettingsLeaf(
        id: 'test.leaf',
        category: SettingsCategoryId.data,
        title: 'Standalone',
        icon: SettingsCatalog.leaves.first.icon,
        accent: SettingsCatalog.leaves.first.accent,
        destination: SettingsCatalog.leaves.first.destination,
      );
      expect(breadcrumbFor(leaf), 'Data & tools');
    });
  });

  group('ranking', () {
    test('an exact title beats a prefix beats a contains', () {
      expect(scoreSettingsLeaf(_leaf('appearance.theme'), 'theme'), 100);
      expect(scoreSettingsLeaf(_leaf('appearance.theme'), 'the'), 80);
      expect(
        scoreSettingsLeaf(_leaf('billing.invoiceNumbering'), 'prefix'),
        60,
      );
    });

    test('a keyword outranks a subtitle', () {
      final keyword = scoreSettingsLeaf(_leaf('billing.taxRate'), 'gst');
      final subtitle = scoreSettingsLeaf(_leaf('billing.taxRate'), 'whether');
      expect(keyword, greaterThan(subtitle));
    });

    test('an unrelated query scores zero', () {
      expect(scoreSettingsLeaf(_leaf('appearance.theme'), 'invoice'), 0);
    });

    test('results come back best first', () {
      final hits = searchSettings('excel', ctx: _admin());
      expect(hits.length, greaterThan(1));
      for (var i = 1; i < hits.length; i++) {
        expect(hits[i - 1].score, greaterThanOrEqualTo(hits[i].score));
      }
    });
  });

  group('search respects visibility', () {
    test('a hidden leaf never surfaces', () {
      // Billing off is the case that matters: the rows are gone from the hub,
      // and search must not be a back door to a page the workspace disabled.
      final ctx = SettingsVisibilityContext(
        permissions: AppPermissions.allTrue(),
        gates: const FeatureGateState(billing: false),
        isWeb: false,
      );
      final ids = searchSettings('currency', ctx: ctx).map((h) => h.leaf.id);
      expect(ids, isNot(contains('billing.currency')));
    });

    test('a staff user without exportData cannot search up Export', () {
      final ctx = SettingsVisibilityContext(
        permissions: const {AppPermissions.importData: true},
        gates: const FeatureGateState(),
        isWeb: false,
      );
      final ids = searchSettings('excel', ctx: ctx).map((h) => h.leaf.id);
      expect(ids, contains('data.import'));
      expect(ids, isNot(contains('data.export')));
    });

    test('the tray row is not searchable on web', () {
      final ids = searchSettings(
        'tray',
        ctx: _admin(isWeb: true),
      ).map((h) => h.leaf.id);
      expect(ids, isNot(contains('notifications.tray')));
    });
  });

  group('query handling', () {
    test('an empty or whitespace query returns nothing, not everything', () {
      expect(searchSettings('', ctx: _admin()), isEmpty);
      expect(searchSettings('   ', ctx: _admin()), isEmpty);
    });

    test('matching is case-insensitive and trims the query', () {
      expect(_topHit('  CURRENCY '), 'billing.currency');
    });

    test('a query matching nothing returns an empty list', () {
      expect(searchSettings('zzzzqqq', ctx: _admin()), isEmpty);
    });

    test('limit is honoured', () {
      final hits = searchSettings('a', ctx: _admin(), limit: 3);
      expect(hits.length, lessThanOrEqualTo(3));
    });

    test('results are stable across repeated calls', () {
      final first = searchSettings('e', ctx: _admin()).map((h) => h.leaf.id);
      final second = searchSettings('e', ctx: _admin()).map((h) => h.leaf.id);
      expect(first, orderedEquals(second.toList()));
    });
  });
}

SettingsLeaf _leaf(String id) => SettingsCatalog.leafById(id)!;
