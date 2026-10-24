import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/config/feature_access.dart';
import 'package:stock_management/config/feature_map.dart';
import 'package:stock_management/config/feature_visibility.dart';
import 'package:stock_management/config/home_actions.dart';
import 'package:stock_management/config/permissions.dart';
import 'package:stock_management/models/company_plan_model.dart';
import 'package:stock_management/screens/home/home_sections.dart';
import 'package:stock_management/services/notification_engine.dart';

FeatureVisibility _vis({
  Map<String, bool>? permissions,
  Set<String> hidden = const {},
  bool billing = true,
  bool barcode = true,
  bool vendors = true,
  CompanyPlan? plan,
}) => FeatureVisibility(
  permissions: permissions ?? AppPermissions.allTrue(),
  gates: FeatureGateState(
    billing: billing,
    barcode: barcode,
    vendors: vendors,
    hiddenFeatures: hidden,
  ),
  plan: plan,
);

void main() {
  group('modules a new workspace starts without', () {
    test('are all real, switchable features', () {
      final switchable = {for (final e in FeatureMap.switchable) e.id};
      for (final id in FeatureMap.hiddenForNewWorkspaces) {
        expect(FeatureMap.getById(id), isNotNull, reason: id);
        // Otherwise Workspace features would have no switch to turn it on.
        expect(switchable, contains(id), reason: id);
      }
    });

    test('leave the everyday features alone', () {
      for (final id in HomeActionsRegistry.defaultActionIds) {
        final action = HomeActionsRegistry.getById(id)!;
        expect(
          FeatureMap.hiddenForNewWorkspaces,
          isNot(contains(action.featureId)),
          reason: id,
        );
      }
    });

    test('drop out of the visible catalog', () {
      final vis = _vis(hidden: FeatureMap.hiddenForNewWorkspaces);
      for (final id in FeatureMap.hiddenForNewWorkspaces) {
        expect(vis.allowsId(id), isFalse, reason: id);
      }
      expect(vis.allowsId('invoices'), isTrue);
    });
  });

  test('every Home action opens a catalogued feature', () {
    for (final action in HomeActionsRegistry.allActions) {
      expect(
        FeatureMap.getById(action.featureId),
        isNotNull,
        reason: action.id,
      );
    }
  });

  test('every tip names a catalogued feature', () {
    for (final id in TipOfTheDay.tipFeatureIds.whereType<String>()) {
      expect(FeatureMap.getById(id), isNotNull, reason: id);
    }
  });

  group('tips', () {
    test('skip features the user cannot use', () {
      // With nothing granted only the tips for everyone remain.
      final none = _vis(permissions: AppPermissions.allFalse(), barcode: false);
      final tip = TipOfTheDay.tipFor(none);
      expect(tip, isNotNull);
      expect(tip, isNot(contains('Dashboard')));
      expect(tip, isNot(contains('staff permissions')));
    });
  });

  group('feature search', () {
    test('finds search-only tools by name', () {
      final hits = _vis().searchFeatures('ageing');
      expect(hits.map((e) => e.id), contains('aging'));
    });

    test('puts names that start with the query first', () {
      final hits = _vis().searchFeatures('stock', limit: 30);
      expect(hits.first.label.toLowerCase(), startsWith('stock'));
    });

    test('leaves out what the user cannot open', () {
      final staff = _vis(permissions: AppPermissions.allFalse());
      expect(staff.searchFeatures('audit'), isEmpty);
      final hidden = _vis(hidden: {'quotations'});
      expect(hidden.searchFeatures('quotation'), isEmpty);
    });

    test('ignores an empty query', () {
      expect(_vis().searchFeatures('  '), isEmpty);
    });
  });

  test('category entries respect switched-off modules and switches', () {
    final vis = _vis(hidden: {'labelPrint'});
    final inventory = vis
        .entriesIn(
          FeatureCategory.inventory,
          placement: FeaturePlacement.tabShortcut,
        )
        .map((e) => e.id);
    expect(inventory, isNot(contains('labelPrint')));

    final noBarcode = _vis(barcode: false)
        .entriesIn(
          FeatureCategory.inventory,
          placement: FeaturePlacement.tabShortcut,
        )
        .map((e) => e.id);
    expect(noBarcode, isNot(contains('labelPrint')));
  });

  group('alert relevance', () {
    test('covers every alert type for someone who can see everything', () {
      expect(
        AlertType.relevantFor(
          products: true,
          batches: true,
          invoices: true,
          purchaseOrders: true,
        ),
        AlertType.all.toSet(),
      );
    });

    test('drops invoice and order alerts for someone without them', () {
      final types = AlertType.relevantFor(
        products: true,
        batches: false,
        invoices: false,
        purchaseOrders: false,
      );
      expect(types, {AlertType.outOfStock, AlertType.lowStock});
    });
  });
}
