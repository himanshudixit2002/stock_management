import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/config/feature_access.dart';
import 'package:stock_management/config/feature_map.dart';
import 'package:stock_management/config/home_actions.dart'
    show HomeActionFeatureGate;
import 'package:stock_management/config/permissions.dart';

void main() {
  FeatureEntry entryWith({
    String? permissionKey,
    List<HomeActionFeatureGate> gates = const [],
  }) => FeatureEntry(
    id: 'test',
    label: 'Test feature',
    subtitle: 'Does a thing',
    icon: FeatureMap.all.first.icon,
    route: '/test',
    category: FeatureCategory.dailyOps,
    placement: FeaturePlacement.searchOnly,
    permissionKey: permissionKey,
    featureGates: gates,
  );

  group('resolveFeatureAccess', () {
    test('available when the permission is held and no gate blocks it', () {
      expect(
        resolveFeatureAccess(
          entryWith(permissionKey: AppPermissions.viewProducts),
          {AppPermissions.viewProducts: true},
          const FeatureGateState(),
        ),
        FeatureAccess.available,
      );
    });

    test('available when a feature has no permission requirement', () {
      expect(
        resolveFeatureAccess(entryWith(), const {}, const FeatureGateState()),
        FeatureAccess.available,
      );
    });

    test('needsPermission when the key is missing or false', () {
      for (final perms in [
        const <String, bool>{},
        {AppPermissions.viewProducts: false},
      ]) {
        expect(
          resolveFeatureAccess(
            entryWith(permissionKey: AppPermissions.viewProducts),
            perms,
            const FeatureGateState(),
          ),
          FeatureAccess.needsPermission,
        );
      }
    });

    test('featureOff when a required company switch is off', () {
      expect(
        resolveFeatureAccess(
          entryWith(gates: [HomeActionFeatureGate.billing]),
          const {},
          const FeatureGateState(billing: false),
        ),
        FeatureAccess.featureOff,
      );
    });

    test('a switched-off feature reports the gate, not the permission', () {
      // Both are wrong here. Saying "ask an admin for access" would send the
      // user chasing a permission for something nobody can currently use, so
      // the gate has to win.
      expect(
        resolveFeatureAccess(
          entryWith(
            permissionKey: AppPermissions.viewInvoices,
            gates: [HomeActionFeatureGate.billing],
          ),
          const {},
          const FeatureGateState(billing: false),
        ),
        FeatureAccess.featureOff,
      );
    });

    test('every gate must pass, not just one', () {
      final entry = entryWith(
        gates: [HomeActionFeatureGate.billing, HomeActionFeatureGate.pricing],
      );
      expect(
        resolveFeatureAccess(entry, const {},
            const FeatureGateState(billing: true, pricing: false)),
        FeatureAccess.featureOff,
      );
      expect(
        resolveFeatureAccess(entry, const {},
            const FeatureGateState(billing: true, pricing: true)),
        FeatureAccess.available,
      );
    });
  });

  group('FeatureGateState', () {
    test('names every gate that is blocking a feature', () {
      final blocked = const FeatureGateState(billing: false, pricing: false)
          .blockedGatesFor(entryWith(gates: [
            HomeActionFeatureGate.billing,
            HomeActionFeatureGate.pricing,
            HomeActionFeatureGate.barcode,
          ]))
          .map(FeatureGateState.labelOf)
          .toList();
      // barcode defaults on, so it must not be blamed.
      expect(blocked, ['Billing', 'Pricing']);
    });

    test('reports nothing blocked when every switch is on', () {
      expect(
        const FeatureGateState(billing: true).blockedGatesFor(
          entryWith(gates: [HomeActionFeatureGate.billing]),
        ),
        isEmpty,
      );
    });
  });

  group('agreement with FeatureMap.isVisible', () {
    test('available matches isVisible across the whole catalogue', () {
      // The screen must never claim a feature is reachable when the navigation
      // would hide it, or vice versa.
      const gates = FeatureGateState(
        billing: true,
        barcode: true,
        vendors: false,
        pricing: true,
      );
      final permissions = <String, bool>{
        for (final entry in FeatureMap.all)
          if (entry.permissionKey != null) entry.permissionKey!: true,
      };
      permissions[AppPermissions.viewInvoices] = false;

      for (final entry in FeatureMap.all) {
        final visible = FeatureMap.isVisible(
          entry,
          permissions,
          billingEnabled: gates.billing,
          barcodeEnabled: gates.barcode,
          vendorsEnabled: gates.vendors,
          pricingEnabled: gates.pricing,
        );
        expect(
          resolveFeatureAccess(entry, permissions, gates) ==
              FeatureAccess.available,
          visible,
          reason: 'disagreement on "${entry.label}"',
        );
      }
    });
  });
}
