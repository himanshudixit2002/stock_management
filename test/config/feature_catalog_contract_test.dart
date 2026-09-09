import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/config/feature_map.dart';
import 'package:stock_management/config/permissions.dart';
import 'package:stock_management/models/company_plan_model.dart';

void main() {
  /// The catalog is the hub every navigation surface reads: Home, the tab
  /// headers, global search, Plan & Features and the console's tier editor. A
  /// feature that names a permission or a plan lock that does not exist is not
  /// a compile error — it silently becomes ungoverned or permanently hidden,
  /// which is exactly the failure these tests exist to catch.
  group('FeatureMap contract', () {
    test('every entry id is unique', () {
      final ids = FeatureMap.all.map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'duplicate feature id');
    });

    test('every permission key a feature names actually exists', () {
      final known = AppPermissions.allKeys.toSet();
      for (final entry in FeatureMap.all) {
        final key = entry.permissionKey;
        if (key == null) continue;
        expect(
          known,
          contains(key),
          reason: '"${entry.label}" is gated on the unknown permission "$key", '
              'so nobody can ever reach it',
        );
      }
    });

    test('every entry points at a real-looking route', () {
      for (final entry in FeatureMap.all) {
        expect(
          entry.route,
          startsWith('/'),
          reason: '"${entry.label}" has a malformed route',
        );
      }
    });

    test('every entry carries a label and a subtitle', () {
      // Both are rendered: an entry with neither shows as an unexplained
      // blank tile on the Home grid.
      for (final entry in FeatureMap.all) {
        expect(entry.label.trim(), isNotEmpty);
        expect(entry.subtitle.trim(), isNotEmpty, reason: entry.label);
      }
    });
  });

  group('plan tier contract', () {
    test('every locked feature id exists in the catalog', () {
      final ids = FeatureMap.all.map((e) => e.id).toSet();
      for (final plan in PlanCatalog.seedDefaults) {
        for (final locked in plan.lockedFeatures) {
          expect(
            ids,
            contains(locked),
            reason: '${plan.label} locks "$locked", which is not a catalogued '
                'feature — the lock does nothing',
          );
        }
      }
    });

    test('the top tier locks nothing', () {
      expect(PlanCatalog.maxTier.lockedFeatures, isEmpty);
      expect(PlanCatalog.pro.lockedFeatures, isEmpty);
    });

    test('entry tiers lock strictly more than the tiers above them', () {
      // A cheaper tier that unlocks something a dearer one does not is a
      // pricing bug, and this is the only place it would show up.
      expect(
        PlanCatalog.growth.lockedFeatures,
        everyElement(isIn(PlanCatalog.starter.lockedFeatures)),
      );
    });

    test('a locked feature is refused by the plan it is locked on', () {
      const starter = CompanyPlan(planId: PlanCatalog.starterId);
      for (final locked in PlanCatalog.starter.lockedFeatures) {
        expect(starter.allowsFeature(locked), isFalse, reason: locked);
      }
      const max = CompanyPlan(planId: PlanCatalog.maxId);
      for (final entry in FeatureMap.all) {
        expect(max.allowsFeature(entry.id), isTrue, reason: entry.id);
      }
    });
  });

  group('permission contract', () {
    test('every declared permission has a definition with a real group', () {
      final groups = AppPermissions.groups.map((g) => g.id).toSet();
      for (final def in AppPermissions.all) {
        expect(
          groups,
          contains(def.group),
          reason: '"${def.label}" sits in the unknown group "${def.group}", '
              'so the role editor will not render it',
        );
      }
    });

    test('permission keys are unique', () {
      final keys = AppPermissions.allKeys;
      expect(keys.toSet().length, keys.length);
    });

    test('every permission key follows the can* convention', () {
      // viewOnly() hands out exactly the keys starting "canView", so a key
      // that breaks the convention silently changes what a read-only console
      // session can do.
      for (final key in AppPermissions.allKeys) {
        expect(key, startsWith('can'), reason: key);
      }
    });
  });
}
