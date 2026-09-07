import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/settings_catalog.dart';
import '../../config/theme.dart';
import '../../providers/category_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/app_list_row.dart';
import '../../widgets/app_screen_scaffold.dart';
import 'manage_list_sheet.dart';
import 'settings_context.dart';
import 'settings_focus.dart';
import 'settings_page_shell.dart';
import 'settings_search_field.dart';

/// The lists a product is described by, plus warehouse zones.
///
/// The route argument doubles as a deep link: Stock In, Stock Transfer and
/// Stock Adjustment send someone straight to the Locations editor when a
/// product has nowhere to be, and a settings search hit on "shelf" lands the
/// same way.
class SettingsCatalogScreen extends StatefulWidget {
  const SettingsCatalogScreen({super.key, this.focusId});

  final String? focusId;

  @override
  State<SettingsCatalogScreen> createState() => _SettingsCatalogScreenState();
}

class _SettingsCatalogScreenState extends State<SettingsCatalogScreen>
    with SettingsFocusMixin {
  bool _resolved = false;

  /// Resolves the route argument, which is either a sheet to open outright or
  /// an anchor to scroll to.
  void _resolveArgument(String? argument) {
    if (argument == null) return;
    if (ManageListAction.all.contains(argument)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showManageListAction(context, argument);
      });
      return;
    }
    focusAfterLayout(argument);
  }

  @override
  Widget build(BuildContext context) {
    if (!_resolved) {
      _resolved = true;
      _resolveArgument(widget.focusId ?? settingsAnchorOf(context));
    }

    final settings = context.watch<SettingsProvider>();
    final categories = context.watch<CategoryProvider>().categories.length;
    final ctx = settingsVisibilityContext(context);
    final readOnly = isInspectingWorkspace(context);

    String count(int n, String singular, String plural) =>
        '$n ${n == 1 ? singular : plural}';

    // [writes] marks a row that opens an editor rather than navigating, so
    // only those are disabled during an inspection — reading a screen is
    // always allowed.
    Widget row(
      String id, {
      required String subtitle,
      required VoidCallback onTap,
      int index = 0,
      bool writes = false,
    }) {
      final leaf = SettingsCatalog.leafById(id)!;
      final blocked = writes && readOnly;
      return KeyedSubtree(
        key: keyFor(id),
        child: AppListRow(
          index: index,
          icon: leaf.icon,
          accent: leaf.accent,
          title: leaf.title,
          subtitle: subtitle,
          highlighted: isFlashing(id),
          enabled: !blocked,
          onTap: blocked ? null : onTap,
        ),
      );
    }

    final attributes = <Widget>[
      if (canSee('catalog.categories', ctx))
        row(
          'catalog.categories',
          subtitle: settings.isInitialized
              ? count(categories, 'category', 'categories')
              : 'Group products for reports and filters',
          onTap: () => openSetting(
            context,
            SettingsCatalog.leafById('catalog.categories')!,
          ),
        ),
      if (canSee('catalog.companies', ctx))
        row(
          'catalog.companies',
          writes: true,
          index: 1,
          subtitle: count(settings.companies.length, 'company', 'companies'),
          onTap: () => showManageCompaniesSheet(context),
        ),
      if (canSee('catalog.subCategories', ctx))
        row(
          'catalog.subCategories',
          writes: true,
          index: 2,
          subtitle: count(
            settings.sizes.length,
            'sub-category',
            'sub-categories',
          ),
          onTap: () => showManageSizesSheet(context),
        ),
      if (canSee('catalog.locations', ctx))
        row(
          'catalog.locations',
          writes: true,
          index: 3,
          subtitle: count(settings.locations.length, 'location', 'locations'),
          onTap: () => showManageLocationsSheet(context),
        ),
    ];

    return AppScreenScaffold(
      icon: Icons.sell_rounded,
      title: 'Catalog & lists',
      subtitle: 'How products are described',
      iconColor: AppTheme.indigoColor,
      body: SettingsPageBody(
        children: [
          if (readOnly)
            const SettingsNote(
              text: kInspectionReadOnlyNote,
              icon: Icons.visibility_rounded,
              color: AppTheme.warningColor,
            ),
          SettingsGroup(
            title: 'Product attributes',
            subtitle: 'Renaming one updates every product that uses it',
            children: attributes,
          ),
          if (canSee('catalog.zones', ctx))
            SettingsGroup(
              title: 'Warehouse',
              children: [
                row(
                  'catalog.zones',
                  subtitle: 'Define storage zones and their capacity',
                  onTap: () => openSetting(
                    context,
                    SettingsCatalog.leafById('catalog.zones')!,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
