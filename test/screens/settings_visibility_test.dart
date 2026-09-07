import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/config/feature_access.dart';
import 'package:stock_management/config/permissions.dart';
import 'package:stock_management/config/settings_catalog.dart';
import 'package:stock_management/models/company_plan_model.dart';

SettingsVisibilityContext _ctx({
  Map<String, bool> permissions = const {},
  FeatureGateState gates = const FeatureGateState(
    billing: true,
    barcode: true,
    vendors: true,
    pricing: true,
  ),
  bool isWeb = false,
  CompanyPlan? plan,
}) => SettingsVisibilityContext(
  permissions: permissions,
  gates: gates,
  isWeb: isWeb,
  plan: plan,
);

Set<String> _visibleIds(SettingsVisibilityContext ctx) => {
  for (final leaf in SettingsCatalog.leaves)
    if (isSettingVisible(leaf, ctx)) leaf.id,
};

void main() {
  tearDown(PlanCatalog.resetToSeed);

  group('defect (a) — permitted staff can reach team settings', () {
    // These three sat inside `if (user.isAdmin)` on the old screen, so a role
    // granting them through the RBAC editor produced a permission that led
    // nowhere. Nothing in the catalog knows what an admin is any more.
    test('viewUsers alone reveals User management', () {
      final ids = _visibleIds(_ctx(permissions: {AppPermissions.viewUsers: true}));
      expect(ids, contains('team.users'));
    });

    test('manageRoles alone reveals Roles & permissions', () {
      final ids = _visibleIds(
        _ctx(permissions: {AppPermissions.manageRoles: true}),
      );
      expect(ids, contains('team.roles'));
    });

    test('manageUsers alone reveals Permission overrides', () {
      final ids = _visibleIds(
        _ctx(permissions: {AppPermissions.manageUsers: true}),
      );
      expect(ids, contains('team.overrides'));
    });

    test('a user with none of them sees no team rows', () {
      final ids = _visibleIds(_ctx());
      expect(ids, isNot(contains('team.users')));
      expect(ids, isNot(contains('team.roles')));
      expect(ids, isNot(contains('team.overrides')));
    });
  });

  group('defect (b) — import/export/zones honour their permission keys', () {
    test('importData shows Import and leaves Export hidden', () {
      final ids = _visibleIds(
        _ctx(
          permissions: {
            AppPermissions.importData: true,
            AppPermissions.exportData: false,
          },
        ),
      );
      expect(ids, contains('data.import'));
      expect(ids, isNot(contains('data.export')));
    });

    test('exportData shows Export and leaves Import hidden', () {
      final ids = _visibleIds(
        _ctx(permissions: {AppPermissions.exportData: true}),
      );
      expect(ids, contains('data.export'));
      expect(ids, isNot(contains('data.import')));
    });

    test('warehouse zones need manageWarehouseZones', () {
      expect(_visibleIds(_ctx()), isNot(contains('catalog.zones')));
      expect(
        _visibleIds(
          _ctx(permissions: {AppPermissions.manageWarehouseZones: true}),
        ),
        contains('catalog.zones'),
      );
    });

    test('bulk actions need their own permissions', () {
      final ids = _visibleIds(
        _ctx(permissions: {AppPermissions.bulkEdit: true}),
      );
      expect(ids, contains('data.bulkEdit'));
      expect(ids, isNot(contains('data.bulkStockIn')));
    });
  });

  group('defect (c) — the unreachable destinations are catalogued', () {
    test('Data health and Update from Excel are reachable', () {
      final ids = _visibleIds(_ctx(permissions: AppPermissions.allTrue()));
      expect(ids, contains('data.health'));
      expect(ids, contains('data.update'));
    });
  });

  group('admins', () {
    test('see every leaf that no company switch or platform hides', () {
      // effectivePermissions already returns allTrue() for an admin, so this
      // is exactly what an admin's Settings resolves to.
      final ids = _visibleIds(_ctx(permissions: AppPermissions.allTrue()));
      for (final leaf in SettingsCatalog.leaves) {
        if (leaf.visibility.platform != SettingsPlatform.any) continue;
        expect(ids, contains(leaf.id), reason: leaf.id);
      }
    });
  });

  group('company feature switches', () {
    test('billing off hides every billing leaf and the whole category row', () {
      final ctx = _ctx(
        permissions: AppPermissions.allTrue(),
        gates: const FeatureGateState(billing: false),
      );
      expect(SettingsCatalog.visibleLeavesIn(SettingsCategoryId.billing, ctx),
          isEmpty);
      expect(
        SettingsCatalog.visibleCategories(ctx).map((c) => c.id),
        isNot(contains(SettingsCategoryId.billing)),
      );
    });

    test('vendors off hides only the Vendors leaf, not the Team row', () {
      final ctx = _ctx(
        permissions: AppPermissions.allTrue(),
        gates: const FeatureGateState(billing: true, vendors: false),
      );
      final teamIds =
          SettingsCatalog.visibleLeavesIn(SettingsCategoryId.team, ctx)
              .map((l) => l.id);
      expect(teamIds, isNot(contains('team.vendors')));
      expect(teamIds, contains('team.users'));
      expect(
        SettingsCatalog.visibleCategories(ctx).map((c) => c.id),
        contains(SettingsCategoryId.team),
      );
    });
  });

  group('plan tier', () {
    test('a locked feature stays hidden even with the permission', () {
      PlanCatalog.hydrate(const [
        PlanDefinition(
          id: 'capped',
          label: 'Capped',
          description: 'Tier used by this test.',
          lockedFeatures: {'excelExport'},
        ),
      ]);
      final ids = _visibleIds(
        _ctx(
          permissions: AppPermissions.allTrue(),
          plan: const CompanyPlan(planId: 'capped'),
        ),
      );
      expect(ids, isNot(contains('data.export')));
      expect(ids, contains('data.import'));
    });
  });

  group('platform', () {
    test('the notification tray row is native-only', () {
      // LocalNotificationService is Android-only, so promising a tray on web
      // would be a setting that does nothing.
      final leaf = SettingsCatalog.leafById('notifications.tray')!;
      expect(isSettingVisible(leaf, _ctx(isWeb: false)), isTrue);
      expect(isSettingVisible(leaf, _ctx(isWeb: true)), isFalse);
    });

    test('legal rows are indexed on both platforms', () {
      for (final id in const [
        'help.privacy',
        'help.terms',
        'help.support',
        'help.dataDeletion',
      ]) {
        final leaf = SettingsCatalog.leafById(id)!;
        expect(isSettingVisible(leaf, _ctx(isWeb: true)), isTrue, reason: id);
        expect(isSettingVisible(leaf, _ctx(isWeb: false)), isTrue, reason: id);
      }
    });
  });

  group('categories', () {
    test('a category with no visible leaf is dropped from the hub', () {
      final ctx = _ctx();
      final visible = SettingsCatalog.visibleCategories(ctx).map((c) => c.id);
      // Nothing gates account, appearance or help, so they always survive.
      expect(visible, contains(SettingsCategoryId.account));
      expect(visible, contains(SettingsCategoryId.appearance));
      expect(visible, contains(SettingsCategoryId.help));
      // A user with no permissions has nothing to configure here.
      expect(visible, isNot(contains(SettingsCategoryId.features)));
      expect(visible, isNot(contains(SettingsCategoryId.team)));
    });

    test('visible categories come back in sortOrder', () {
      final ctx = _ctx(permissions: AppPermissions.allTrue());
      final orders =
          SettingsCatalog.visibleCategories(ctx).map((c) => c.sortOrder);
      expect(orders, orderedEquals(orders.toList()..sort()));
    });
  });

  group('the hub row list', () {
    // The profile card at the top of the hub *is* the Account category. Listing
    // the category again put two controls one above the other, both opening
    // ProfileScreen.
    test('Account is a visible category, because search needs it', () {
      final ctx = _ctx(permissions: AppPermissions.allTrue());
      expect(
        SettingsCatalog.visibleCategories(ctx).map((c) => c.id),
        contains(SettingsCategoryId.account),
      );
      expect(
        SettingsCatalog.visibleLeavesIn(SettingsCategoryId.account, ctx)
            .map((l) => l.id),
        containsAll(<String>['account.password', 'account.delete']),
      );
    });

    test('the hub does not repeat Account as a row', () {
      final ctx = _ctx(permissions: AppPermissions.allTrue());
      final rows = SettingsCatalog.hubRowCategories(ctx).map((c) => c.id);
      expect(rows, isNot(contains(SettingsCategoryId.account)));
      // Every other visible category still gets one.
      expect(rows.length, SettingsCatalog.visibleCategories(ctx).length - 1);
    });

    test('no hub row leads to the same route as another', () {
      // The duplicate row was only visible because Account and the profile card
      // shared AppRoutes.profile. Any other pair sharing a route would read the
      // same way.
      final ctx = _ctx(permissions: AppPermissions.allTrue());
      final routes = SettingsCatalog.hubRowCategories(
        ctx,
      ).map((c) => c.route).toList();
      expect(routes.toSet().length, routes.length);
    });
  });
}
