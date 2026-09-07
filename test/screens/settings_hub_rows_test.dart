import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/config/feature_access.dart';
import 'package:stock_management/config/permissions.dart';
import 'package:stock_management/config/settings_catalog.dart';
import 'package:stock_management/config/theme.dart';
import 'package:stock_management/widgets/app_list_row.dart';

import '../helpers/test_helpers.dart';

/// Renders exactly what the hub renders — the catalog's own hub rows, at the
/// tightest phone width — without needing Firebase for the providers.
void main() {
  const narrow = Size(360, 1400);

  final ctx = SettingsVisibilityContext(
    permissions: AppPermissions.allTrue(),
    gates: const FeatureGateState(
      billing: true,
      barcode: true,
      vendors: true,
      pricing: true,
    ),
    isWeb: false,
  );

  testWidgets('an admin sees nine rows and no repeated Account row', (
    tester,
  ) async {
    tester.view.physicalSize = narrow;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final categories = SettingsCatalog.hubRowCategories(ctx);

    await pumpAndSettle(
      tester,
      createTestApp(
        child: Theme(
          data: AppTheme.lightTheme,
          child: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (var i = 0; i < categories.length; i++)
                  AppListRow(
                    index: i,
                    icon: categories[i].icon,
                    accent: categories[i].accent,
                    title: categories[i].title,
                    subtitle: categories[i].subtitle,
                    onTap: () {},
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(AppListRow), findsNWidgets(9));
    // The profile card is the Account row; a second one led to the same screen.
    expect(find.text('Account & security'), findsNothing);
    for (final title in const [
      'Appearance & home',
      'Notifications',
      'Workspace features',
      'Billing & invoicing',
      'Catalog & lists',
      'Team & partners',
      'Data & tools',
      'Plan & workspace',
      'Help, legal & about',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
  });
}
