import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_management/config/feature_access.dart';
import 'package:stock_management/config/feature_visibility.dart';
import 'package:stock_management/config/home_actions.dart';
import 'package:stock_management/config/permissions.dart';
import 'package:stock_management/providers/home_customization_provider.dart';

FeatureVisibility _admin({Set<String> hidden = const {}, bool billing = true}) =>
    FeatureVisibility(
      permissions: AppPermissions.allTrue(),
      gates: FeatureGateState(billing: billing, hiddenFeatures: hidden),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('starts on the default actions, with the AI panel off', () async {
    final p = HomeCustomizationProvider();
    await p.setCompanyId('c1');
    expect(p.selectedIds, HomeActionsRegistry.defaultActionIds);
    expect(p.isSectionVisible(HomeSection.aiInsights), isFalse);
    expect(p.isSectionVisible(HomeSection.quickActions), isTrue);
  });

  test('a removed action stays removed after a restart', () async {
    final p = HomeCustomizationProvider();
    await p.setCompanyId('c1');
    await p.saveActions(['stockIn', 'stockOut']);

    // A fresh provider is what a cold start gets. Missing defaults used to be
    // appended back here.
    final again = HomeCustomizationProvider();
    await again.setCompanyId('c1');
    expect(again.selectedIds, ['stockIn', 'stockOut']);
  });

  test('section choices persist per workspace', () async {
    final p = HomeCustomizationProvider();
    await p.setCompanyId('c1');
    await p.setSectionVisible(HomeSection.recentActivity, false);

    final again = HomeCustomizationProvider();
    await again.setCompanyId('c1');
    expect(again.isSectionVisible(HomeSection.recentActivity), isFalse);

    final other = HomeCustomizationProvider();
    await other.setCompanyId('c2');
    expect(other.isSectionVisible(HomeSection.recentActivity), isTrue);
  });

  test('reset brings back the defaults for actions and sections', () async {
    final p = HomeCustomizationProvider();
    await p.setCompanyId('c1');
    await p.saveActions(['stockIn']);
    await p.setSectionVisible(HomeSection.stats, false);
    await p.resetToDefaults();
    expect(p.selectedIds, HomeActionsRegistry.defaultActionIds);
    expect(p.isSectionVisible(HomeSection.stats), isTrue);
  });

  group('visible actions', () {
    test('skip a switched-off module', () async {
      final p = HomeCustomizationProvider();
      await p.setCompanyId('c1');
      final ids = p.visibleActions(_admin(hidden: {'fastPos'})).map((a) => a.id);
      expect(ids, isNot(contains('fastPos')));
      expect(ids, contains('stockIn'));
    });

    test('skip what a workspace switch turns off', () async {
      final p = HomeCustomizationProvider();
      await p.setCompanyId('c1');
      final ids = p.visibleActions(_admin(billing: false)).map((a) => a.id);
      expect(ids, isNot(contains('invoices')));
      expect(ids, isNot(contains('fastPos')));
    });

    test('skip what the role does not grant', () async {
      final p = HomeCustomizationProvider();
      await p.setCompanyId('c1');
      final perms = AppPermissions.allTrue()
        ..[AppPermissions.stockOut] = false;
      final vis = FeatureVisibility(
        permissions: perms,
        gates: const FeatureGateState(billing: true),
      );
      expect(p.visibleActions(vis).map((a) => a.id), isNot(contains('stockOut')));
    });
  });
}
