import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/config/feature_map.dart';
import 'package:stock_management/config/routes.dart';
import 'package:stock_management/config/settings_catalog.dart';

/// Every route the catalog is allowed to point at.
///
/// Written out rather than derived, because the point is to catch a typo in a
/// destination — and a typo would still be "some string on AppRoutes" if we
/// reflected over the class.
const _knownRoutes = <String>{
  AppRoutes.about,
  AppRoutes.activityTimeline,
  AppRoutes.billingSettings,
  AppRoutes.bulkEdit,
  AppRoutes.bulkStockIn,
  AppRoutes.categories,
  AppRoutes.companySwitcher,
  AppRoutes.customers,
  AppRoutes.dataDeletion,
  AppRoutes.dataHealth,
  AppRoutes.excelExport,
  AppRoutes.excelImport,
  AppRoutes.excelUpdate,
  AppRoutes.help,
  AppRoutes.homeCustomization,
  AppRoutes.notificationSettings,
  AppRoutes.onboarding,
  AppRoutes.planFeatures,
  AppRoutes.privacyPolicy,
  AppRoutes.profile,
  AppRoutes.roles,
  AppRoutes.settingsAppearance,
  AppRoutes.settingsCatalog,
  AppRoutes.settingsData,
  AppRoutes.settingsFeatures,
  AppRoutes.settingsHelp,
  AppRoutes.settingsTeam,
  AppRoutes.staffPermissions,
  AppRoutes.support,
  AppRoutes.terms,
  AppRoutes.userManagement,
  AppRoutes.vendors,
  AppRoutes.warehouseZones,
};

void main() {
  group('catalog integrity', () {
    test('leaf ids are unique', () {
      final ids = SettingsCatalog.leaves.map((l) => l.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every feature id resolves in FeatureMap', () {
      // isSettingVisible fails closed on an unknown id, so a typo here would
      // silently hide a setting rather than crash.
      for (final leaf in SettingsCatalog.leaves) {
        final destination = leaf.destination;
        final id =
            leaf.visibility.featureId ??
            (destination is FeatureTarget ? destination.featureId : null);
        if (id == null) continue;
        expect(
          FeatureMap.getById(id),
          isNotNull,
          reason: '${leaf.id} points at unknown feature "$id"',
        );
      }
    });

    test('every destination route is a real AppRoutes constant', () {
      for (final leaf in SettingsCatalog.leaves) {
        expect(
          _knownRoutes,
          contains(routeOf(leaf.destination)),
          reason: '${leaf.id} points at an unregistered route',
        );
      }
      for (final category in SettingsCatalog.categories) {
        expect(_knownRoutes, contains(category.route));
      }
    });

    test('every category has at least one leaf', () {
      for (final id in SettingsCategoryId.values) {
        expect(
          SettingsCatalog.leavesIn(id),
          isNotEmpty,
          reason: '$id would render a row leading to an empty page',
        );
      }
    });

    test('every category id has exactly one SettingsCategory', () {
      final ids = SettingsCatalog.categories.map((c) => c.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(ids.toSet(), SettingsCategoryId.values.toSet());
    });

    test('a leaf never restates the permission its feature already enforces', () {
      // Restating it is how Settings drifted from FeatureMap in the first
      // place: two copies of a rule, only one of them maintained.
      for (final leaf in SettingsCatalog.leaves) {
        if (leaf.destination is! FeatureTarget) continue;
        expect(
          leaf.visibility.permissionAll,
          isEmpty,
          reason: '${leaf.id} duplicates its FeatureMap gating',
        );
        expect(leaf.visibility.permissionAny, isEmpty, reason: leaf.id);
      }
    });

    test('every settingsOnly feature is reachable from the catalog', () {
      // The defect this pins: FeatureMap declared dataHealth and excelUpdate as
      // Settings destinations, and the Settings screen listed neither, so
      // Data Health had no entry point in the entire app.
      final catalogued = <String>{
        for (final leaf in SettingsCatalog.leaves)
          if (leaf.destination case FeatureTarget(:final featureId)) featureId,
      };
      for (final entry in FeatureMap.entriesFor(FeaturePlacement.settingsOnly)) {
        expect(
          catalogued,
          contains(entry.id),
          reason: '${entry.id} is a settings destination with no settings row',
        );
      }
    });

    test('every legal link carries both a url and a native route', () {
      final links = SettingsCatalog.leaves
          .map((l) => l.destination)
          .whereType<LinkTarget>();
      expect(links, isNotEmpty);
      for (final link in links) {
        expect(link.url, startsWith('https://'));
        expect(_knownRoutes, contains(link.nativeRoute));
      }
    });

    test('leafById finds a leaf and returns null for an unknown id', () {
      expect(SettingsCatalog.leafById('billing.currency'), isNotNull);
      expect(SettingsCatalog.leafById('nope.nothing'), isNull);
    });

    test('anchorOf carries a sheet action id through as the anchor', () {
      // The three manage-list sheets are opened by passing their action id as
      // the route argument, so anchor and action must be the same channel.
      const target = SheetTarget(AppRoutes.settingsCatalog, 'locations');
      expect(anchorOf(target), 'locations');
      expect(routeOf(target), AppRoutes.settingsCatalog);
    });
  });
}
