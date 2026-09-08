/// Every setting the app has, as data.
///
/// Settings used to be a single screen that built forty-odd rows inline, which
/// made two things impossible. Search could only ever match the rows that
/// happened to be built, so "currency", "gst" and "expiry" — all real settings,
/// all living one page deeper — returned nothing. And gating was hand-written
/// per row, which had already drifted from [FeatureMap]: Import and Export
/// ignored their permission keys entirely, and three team destinations sat
/// behind an `isAdmin` check that made the permissions granting them
/// unreachable.
///
/// Declaring the settings as a `const` catalog fixes both at the root. Search
/// indexes leaves, not widgets, so it finds a setting wherever it lives; and a
/// leaf pointing at a catalogued feature states no permissions of its own, so
/// it cannot disagree with the rest of the app.
///
/// This file is deliberately free of widgets and `BuildContext` (it holds
/// `IconData` and `Color` the same way [FeatureMap] does) so the whole thing is
/// unit-testable without a widget tree. It also must stay out of any deferred
/// library: the router, the hub and every sub-page all read it.
library;

import 'package:flutter/material.dart';

import '../models/company_plan_model.dart';
import 'feature_access.dart';
import 'feature_map.dart';
import 'home_actions.dart' show HomeActionFeatureGate;
import 'permissions.dart';
import 'routes.dart';
import 'theme.dart';

// -----------------------------------------------------------------------------
// Categories
// -----------------------------------------------------------------------------

/// The hub rows. One category is one row on the Settings tab and one page
/// behind it, except [account], [notifications], [billing] and [plan], which
/// point at screens that already existed.
enum SettingsCategoryId {
  account,
  appearance,
  notifications,
  features,
  billing,
  catalog,
  team,
  data,
  plan,
  help,
}

class SettingsCategory {
  const SettingsCategory({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.route,
    this.sortOrder = 0,
  });

  final SettingsCategoryId id;
  final String title;

  /// Shown while the providers backing the live summary are still loading.
  final String subtitle;
  final IconData icon;
  final Color accent;
  final String route;
  final int sortOrder;
}

// -----------------------------------------------------------------------------
// Destinations
// -----------------------------------------------------------------------------

/// Where tapping a setting goes.
///
/// [anchor] is handed to the destination as its route argument so the page can
/// scroll to and flash the group the search hit named. Anchors are per group,
/// not per field: a page has five or six, and adding a field never needs a new
/// one.
sealed class SettingsDestination {
  const SettingsDestination();
}

/// A plain named route.
class RouteTarget extends SettingsDestination {
  const RouteTarget(this.route, {this.anchor});

  final String route;
  final String? anchor;
}

/// A destination catalogued in [FeatureMap]. The route *and* the gating both
/// come from the [FeatureEntry], so nothing is restated here and nothing can
/// drift.
class FeatureTarget extends SettingsDestination {
  const FeatureTarget(this.featureId, {this.anchor});

  final String featureId;
  final String? anchor;
}

/// Opens a sheet on the destination page rather than pushing a route of its
/// own — the three "manage this list" editors.
class SheetTarget extends SettingsDestination {
  const SheetTarget(this.route, this.actionId);

  final String route;
  final String actionId;
}

/// A legal page: the marketing site on web, the in-app screen on native. The
/// branch used to be repeated at all four call sites.
class LinkTarget extends SettingsDestination {
  const LinkTarget({required this.url, required this.nativeRoute});

  final String url;
  final String nativeRoute;
}

/// A control that lives on the destination page itself — the theme switch, a
/// company toggle, the tax rate field. Search still navigates to page+anchor.
class InlineTarget extends SettingsDestination {
  const InlineTarget(this.route, this.anchor);

  final String route;
  final String anchor;
}

/// The route a destination leads to, native-side.
String routeOf(SettingsDestination destination) => switch (destination) {
  RouteTarget(:final route) => route,
  SheetTarget(:final route) => route,
  InlineTarget(:final route) => route,
  LinkTarget(:final nativeRoute) => nativeRoute,
  FeatureTarget(:final featureId) =>
    FeatureMap.getById(featureId)?.route ?? AppRoutes.settings,
};

/// The anchor a destination carries, if any.
String? anchorOf(SettingsDestination destination) => switch (destination) {
  RouteTarget(:final anchor) => anchor,
  FeatureTarget(:final anchor) => anchor,
  InlineTarget(:final anchor) => anchor,
  SheetTarget(:final actionId) => actionId,
  LinkTarget() => null,
};

// -----------------------------------------------------------------------------
// Visibility
// -----------------------------------------------------------------------------

/// Platforms a setting exists on. The notification tray is Android-only, and
/// the legal pages differ between web and native.
enum SettingsPlatform { any, webOnly, nativeOnly }

/// Why a setting is or is not shown — as data, not a closure, so the catalog
/// stays `const` and every rule is testable without building a widget.
class SettingsVisibility {
  const SettingsVisibility({
    this.featureId,
    this.permissionAny = const [],
    this.permissionAll = const [],
    this.gates = const <HomeActionFeatureGate>[],
    this.platform = SettingsPlatform.any,
  });

  /// Delegate the whole decision to [FeatureMap.isVisible]. Set implicitly for
  /// a [FeatureTarget], so those leaves declare no permissions at all.
  final String? featureId;

  /// Any one of these permissions is enough.
  final List<String> permissionAny;

  /// All of these permissions are required.
  final List<String> permissionAll;

  /// Company feature switches that must all be on.
  final List<HomeActionFeatureGate> gates;

  final SettingsPlatform platform;

  static const SettingsVisibility visible = SettingsVisibility();
}

/// Everything [isSettingVisible] needs, gathered once per build.
class SettingsVisibilityContext {
  const SettingsVisibilityContext({
    required this.permissions,
    required this.gates,
    required this.isWeb,
    this.plan,
  });

  /// `UserModel.effectivePermissions` — already `allTrue()` for admins, which
  /// is why nothing in this file needs an `isAdmin` concept.
  final Map<String, bool> permissions;

  final FeatureGateState gates;
  final bool isWeb;
  final CompanyPlan? plan;

  bool has(String key) => permissions[key] == true;
}

/// True when [leaf] should be shown to the user described by [ctx].
bool isSettingVisible(SettingsLeaf leaf, SettingsVisibilityContext ctx) {
  final v = leaf.visibility;

  switch (v.platform) {
    case SettingsPlatform.webOnly:
      if (!ctx.isWeb) return false;
    case SettingsPlatform.nativeOnly:
      if (ctx.isWeb) return false;
    case SettingsPlatform.any:
      break;
  }

  final destination = leaf.destination;
  final featureId =
      v.featureId ??
      (destination is FeatureTarget ? destination.featureId : null);
  if (featureId != null) {
    final entry = FeatureMap.getById(featureId);
    // Fail closed. A catalogue test asserts no id ever reaches this.
    if (entry == null) return false;
    final visible = FeatureMap.isVisible(
      entry,
      ctx.permissions,
      // All four passed explicitly: isVisible defaults billing to false and
      // the other three to true, so omitting any of them silently shows rows
      // for a switch that is off.
      billingEnabled: ctx.gates.billing,
      barcodeEnabled: ctx.gates.barcode,
      vendorsEnabled: ctx.gates.vendors,
      pricingEnabled: ctx.gates.pricing,
      plan: ctx.plan,
    );
    if (!visible) return false;
  }

  for (final key in v.permissionAll) {
    if (!ctx.has(key)) return false;
  }
  if (v.permissionAny.isNotEmpty && !v.permissionAny.any(ctx.has)) {
    return false;
  }
  for (final gate in v.gates) {
    if (!ctx.gates.isOn(gate)) return false;
  }
  return true;
}

// -----------------------------------------------------------------------------
// Leaves
// -----------------------------------------------------------------------------

/// One setting: a row a user can tap, or a control they can change.
class SettingsLeaf {
  const SettingsLeaf({
    required this.id,
    required this.category,
    required this.title,
    required this.icon,
    required this.accent,
    required this.destination,
    this.group,
    this.subtitle,
    this.keywords = const [],
    this.visibility = SettingsVisibility.visible,
    this.sortOrder = 0,
  });

  /// Stable dotted id, e.g. `billing.taxRate`. Tests pin behaviour to these,
  /// so renaming one is a breaking change.
  final String id;

  final SettingsCategoryId category;
  final String title;

  /// Second breadcrumb crumb, e.g. `Tax` in "Billing & invoicing · Tax". Also
  /// the anchor's human name.
  final String? group;

  final String? subtitle;

  /// Words a user might search that appear in neither title nor subtitle —
  /// "gst" for the tax rate, "symbol" for the currency, "sso" for roles.
  final List<String> keywords;

  final IconData icon;
  final Color accent;
  final SettingsDestination destination;
  final SettingsVisibility visibility;
  final int sortOrder;
}

// -----------------------------------------------------------------------------
// The catalog
// -----------------------------------------------------------------------------

class SettingsCatalog {
  SettingsCatalog._();

  static const List<SettingsCategory> categories = [
    SettingsCategory(
      id: SettingsCategoryId.account,
      title: 'Account & security',
      subtitle: 'Profile, password and account removal',
      icon: Icons.person_rounded,
      accent: AppTheme.primaryColor,
      route: AppRoutes.profile,
      sortOrder: 0,
    ),
    SettingsCategory(
      id: SettingsCategoryId.appearance,
      title: 'Appearance & home',
      subtitle: 'Theme and home quick actions',
      icon: Icons.palette_rounded,
      accent: AppTheme.accentColor,
      route: AppRoutes.settingsAppearance,
      sortOrder: 1,
    ),
    SettingsCategory(
      id: SettingsCategoryId.notifications,
      title: 'Notifications',
      subtitle: 'Which stock alerts reach you',
      icon: Icons.notifications_active_rounded,
      accent: AppTheme.warningColor,
      route: AppRoutes.notificationSettings,
      sortOrder: 2,
    ),
    SettingsCategory(
      id: SettingsCategoryId.features,
      title: 'Workspace features',
      subtitle: 'Turn pricing, vendors, barcode and billing on or off',
      icon: Icons.toggle_on_rounded,
      accent: AppTheme.infoColor,
      route: AppRoutes.settingsFeatures,
      sortOrder: 3,
    ),
    SettingsCategory(
      id: SettingsCategoryId.billing,
      title: 'Billing & invoicing',
      subtitle: 'Company profile, tax and numbering',
      icon: Icons.receipt_long_rounded,
      accent: AppTheme.successColor,
      route: AppRoutes.billingSettings,
      sortOrder: 4,
    ),
    SettingsCategory(
      id: SettingsCategoryId.catalog,
      title: 'Catalog & lists',
      subtitle: 'Categories, companies, sub-categories and locations',
      icon: Icons.sell_rounded,
      accent: AppTheme.indigoColor,
      route: AppRoutes.settingsCatalog,
      sortOrder: 5,
    ),
    SettingsCategory(
      id: SettingsCategoryId.team,
      title: 'Team & partners',
      subtitle: 'Users, roles, vendors and customers',
      icon: Icons.groups_rounded,
      accent: AppTheme.primaryColor,
      route: AppRoutes.settingsTeam,
      sortOrder: 6,
    ),
    SettingsCategory(
      id: SettingsCategoryId.data,
      title: 'Data & tools',
      subtitle: 'Import, export and bulk editing',
      icon: Icons.dataset_rounded,
      accent: AppTheme.violetColor,
      route: AppRoutes.settingsData,
      sortOrder: 7,
    ),
    SettingsCategory(
      id: SettingsCategoryId.plan,
      title: 'Plan & workspace',
      subtitle: 'What your tier includes',
      icon: Icons.workspace_premium_rounded,
      accent: AppTheme.infoColor,
      route: AppRoutes.planFeatures,
      sortOrder: 8,
    ),
    SettingsCategory(
      id: SettingsCategoryId.help,
      title: 'Help, legal & about',
      subtitle: 'Guides, policies and app version',
      icon: Icons.help_outline_rounded,
      accent: AppTheme.cyanColor,
      route: AppRoutes.settingsHelp,
      sortOrder: 9,
    ),
  ];

  /// Every setting in the app, flat. Order within a category is [sortOrder].
  static const List<SettingsLeaf> leaves = [
    // ------------------------------------------------------------------ account
    SettingsLeaf(
      id: 'account.profile',
      category: SettingsCategoryId.account,
      group: 'Profile',
      title: 'Name and phone',
      subtitle: 'Your display name and contact number',
      keywords: ['profile', 'edit profile', 'display name', 'contact'],
      icon: Icons.badge_rounded,
      accent: AppTheme.primaryColor,
      destination: RouteTarget(AppRoutes.profile, anchor: 'account.profile'),
    ),
    SettingsLeaf(
      id: 'account.email',
      category: SettingsCategoryId.account,
      group: 'Profile',
      title: 'Email address',
      subtitle: 'The address you sign in with — cannot be changed',
      keywords: ['email', 'sign in', 'login', 'username'],
      icon: Icons.alternate_email_rounded,
      accent: AppTheme.infoColor,
      destination: RouteTarget(AppRoutes.profile, anchor: 'account.info'),
      sortOrder: 1,
    ),
    SettingsLeaf(
      id: 'account.password',
      category: SettingsCategoryId.account,
      group: 'Security',
      title: 'Change password',
      subtitle: 'Update the password for this account',
      keywords: ['password', 'security', 'credentials', 'reset'],
      icon: Icons.lock_rounded,
      accent: AppTheme.warningColor,
      destination: RouteTarget(AppRoutes.profile, anchor: 'account.security'),
      sortOrder: 2,
    ),
    SettingsLeaf(
      id: 'account.delete',
      category: SettingsCategoryId.account,
      group: 'Danger zone',
      title: 'Delete account',
      subtitle: 'Permanently remove your account and its data',
      keywords: ['delete', 'remove', 'close account', 'danger', 'erase'],
      icon: Icons.delete_forever_rounded,
      accent: AppTheme.dangerColor,
      destination: RouteTarget(AppRoutes.profile, anchor: 'account.danger'),
      sortOrder: 3,
    ),

    // --------------------------------------------------------------- appearance
    SettingsLeaf(
      id: 'appearance.theme',
      category: SettingsCategoryId.appearance,
      group: 'Theme',
      title: 'Theme',
      subtitle: 'Follow the system, or force light or dark',
      keywords: ['dark', 'light', 'night mode', 'colour', 'color', 'appearance'],
      icon: Icons.dark_mode_rounded,
      accent: AppTheme.accentColor,
      destination: InlineTarget(
        AppRoutes.settingsAppearance,
        'appearance.theme',
      ),
    ),
    SettingsLeaf(
      id: 'appearance.quickActions',
      category: SettingsCategoryId.appearance,
      group: 'Home screen',
      title: 'Home quick actions',
      subtitle: 'Choose the shortcuts on your home screen',
      keywords: ['home', 'shortcut', 'quick action', 'customize', 'dashboard'],
      icon: Icons.dashboard_customize_rounded,
      accent: AppTheme.primaryColor,
      destination: RouteTarget(AppRoutes.homeCustomization),
      sortOrder: 1,
    ),

    // ------------------------------------------------------------ notifications
    SettingsLeaf(
      id: 'notifications.tray',
      category: SettingsCategoryId.notifications,
      group: 'Delivery',
      title: 'Show alerts in the notification tray',
      subtitle: 'System notifications on this device',
      keywords: ['push', 'tray', 'system', 'android', 'banner', 'sound'],
      icon: Icons.notifications_rounded,
      accent: AppTheme.warningColor,
      destination: InlineTarget(
        AppRoutes.notificationSettings,
        'notifications.delivery',
      ),
      visibility: SettingsVisibility(platform: SettingsPlatform.nativeOnly),
    ),
    SettingsLeaf(
      id: 'notifications.types',
      category: SettingsCategoryId.notifications,
      group: 'Alert me about',
      title: 'Alert types',
      subtitle: 'Out of stock, low stock, expiry, overdue invoices and orders',
      keywords: [
        'low stock',
        'out of stock',
        'overdue',
        'invoice',
        'purchase order',
        'alerts',
      ],
      icon: Icons.tune_rounded,
      accent: AppTheme.infoColor,
      destination: InlineTarget(
        AppRoutes.notificationSettings,
        'notifications.types',
      ),
      sortOrder: 1,
    ),
    SettingsLeaf(
      id: 'notifications.expiryWindow',
      category: SettingsCategoryId.notifications,
      group: 'Expiry warning window',
      title: 'Expiry warning window',
      subtitle: 'How many days ahead a batch counts as nearing expiry',
      keywords: ['expiry', 'expiring', 'batch', 'shelf life', 'days', 'window'],
      icon: Icons.event_busy_rounded,
      accent: AppTheme.dangerColor,
      destination: InlineTarget(
        AppRoutes.notificationSettings,
        'notifications.expiry',
      ),
      sortOrder: 2,
    ),

    // ------------------------------------------------------------------ features
    SettingsLeaf(
      id: 'features.pricing',
      category: SettingsCategoryId.features,
      group: 'Workspace switches',
      title: 'Pricing',
      subtitle: 'Show cost and selling prices across the app',
      keywords: ['price', 'cost', 'selling', 'margin', 'money'],
      icon: Icons.attach_money_rounded,
      accent: AppTheme.successColor,
      destination: InlineTarget(AppRoutes.settingsFeatures, 'features.pricing'),
      visibility: SettingsVisibility(
        permissionAll: [AppPermissions.manageCompanySettings],
      ),
    ),
    SettingsLeaf(
      id: 'features.vendors',
      category: SettingsCategoryId.features,
      group: 'Workspace switches',
      title: 'Vendors',
      subtitle: 'Track suppliers and purchase sources',
      keywords: ['vendor', 'supplier', 'purchase', 'source'],
      icon: Icons.local_shipping_rounded,
      accent: AppTheme.indigoColor,
      destination: InlineTarget(AppRoutes.settingsFeatures, 'features.vendors'),
      visibility: SettingsVisibility(
        permissionAll: [AppPermissions.manageCompanySettings],
      ),
      sortOrder: 1,
    ),
    SettingsLeaf(
      id: 'features.barcode',
      category: SettingsCategoryId.features,
      group: 'Workspace switches',
      title: 'Barcode scanner',
      subtitle: 'Scan barcodes to find and move stock',
      keywords: ['barcode', 'scan', 'qr', 'camera', 'sku'],
      icon: Icons.qr_code_scanner_rounded,
      accent: AppTheme.infoColor,
      destination: InlineTarget(AppRoutes.settingsFeatures, 'features.barcode'),
      visibility: SettingsVisibility(
        permissionAll: [AppPermissions.manageCompanySettings],
      ),
      sortOrder: 2,
    ),
    SettingsLeaf(
      id: 'features.billing',
      category: SettingsCategoryId.features,
      group: 'Workspace switches',
      title: 'Billing',
      subtitle: 'Invoices, payments and point of sale',
      keywords: ['invoice', 'billing', 'payment', 'pos', 'sales'],
      icon: Icons.point_of_sale_rounded,
      accent: AppTheme.successColor,
      destination: InlineTarget(AppRoutes.settingsFeatures, 'features.billing'),
      visibility: SettingsVisibility(
        permissionAll: [AppPermissions.manageCompanySettings],
      ),
      sortOrder: 3,
    ),

    // ------------------------------------------------------------------- billing
    SettingsLeaf(
      id: 'billing.businessProfile',
      category: SettingsCategoryId.billing,
      group: 'Business profile',
      title: 'Business name and address',
      subtitle: 'What prints at the top of an invoice',
      keywords: ['business', 'company', 'address', 'phone', 'letterhead'],
      icon: Icons.storefront_rounded,
      accent: AppTheme.successColor,
      destination: RouteTarget(
        AppRoutes.billingSettings,
        anchor: 'billing.business',
      ),
      visibility: SettingsVisibility(
        permissionAny: [AppPermissions.viewInvoices],
        gates: [HomeActionFeatureGate.billing],
      ),
    ),
    SettingsLeaf(
      id: 'billing.taxId',
      category: SettingsCategoryId.billing,
      group: 'Tax',
      title: 'Tax ID',
      subtitle: 'GSTIN, VAT or tax registration number',
      // Deliberately not 'gst': that word belongs to the rate below, which is
      // what someone typing it is nearly always after. The registration number
      // is 'gstin'.
      keywords: ['gstin', 'vat number', 'tin', 'tax id', 'registration'],
      icon: Icons.badge_rounded,
      accent: AppTheme.infoColor,
      destination: RouteTarget(AppRoutes.billingSettings, anchor: 'billing.tax'),
      visibility: SettingsVisibility(
        permissionAny: [AppPermissions.viewInvoices],
        gates: [HomeActionFeatureGate.billing],
      ),
      sortOrder: 1,
    ),
    SettingsLeaf(
      id: 'billing.taxRate',
      category: SettingsCategoryId.billing,
      group: 'Tax',
      title: 'Default tax rate',
      subtitle: 'Tax label, percentage and whether prices include it',
      keywords: ['gst', 'vat', 'tax', 'rate', 'percent', 'inclusive', 'sales tax'],
      icon: Icons.percent_rounded,
      accent: AppTheme.warningColor,
      destination: RouteTarget(AppRoutes.billingSettings, anchor: 'billing.tax'),
      visibility: SettingsVisibility(
        permissionAny: [AppPermissions.viewInvoices],
        gates: [HomeActionFeatureGate.billing],
      ),
      sortOrder: 2,
    ),
    SettingsLeaf(
      id: 'billing.currency',
      category: SettingsCategoryId.billing,
      group: 'Invoice numbering',
      title: 'Currency symbol',
      subtitle: 'The symbol shown against every amount in the app',
      keywords: ['currency', 'symbol', 'rupee', 'dollar', 'money', 'inr', 'usd'],
      icon: Icons.currency_exchange_rounded,
      accent: AppTheme.successColor,
      destination: RouteTarget(
        AppRoutes.billingSettings,
        anchor: 'billing.numbering',
      ),
      visibility: SettingsVisibility(
        permissionAny: [AppPermissions.viewInvoices],
        gates: [HomeActionFeatureGate.billing],
      ),
      sortOrder: 3,
    ),
    SettingsLeaf(
      id: 'billing.invoiceNumbering',
      category: SettingsCategoryId.billing,
      group: 'Invoice numbering',
      title: 'Invoice prefix and next number',
      subtitle: 'How new invoice and bill numbers are generated',
      keywords: ['invoice prefix', 'numbering', 'sequence', 'next number', 'bill'],
      icon: Icons.tag_rounded,
      accent: AppTheme.infoColor,
      destination: RouteTarget(
        AppRoutes.billingSettings,
        anchor: 'billing.numbering',
      ),
      visibility: SettingsVisibility(
        permissionAny: [AppPermissions.viewInvoices],
        gates: [HomeActionFeatureGate.billing],
      ),
      sortOrder: 4,
    ),
    SettingsLeaf(
      id: 'billing.terms',
      category: SettingsCategoryId.billing,
      group: 'Terms & notes',
      title: 'Payment terms and footer',
      subtitle: 'Default due days, invoice footer and standing notes',
      keywords: ['terms', 'due date', 'footer', 'notes', 'payment days'],
      icon: Icons.notes_rounded,
      accent: AppTheme.violetColor,
      destination: RouteTarget(
        AppRoutes.billingSettings,
        anchor: 'billing.terms',
      ),
      visibility: SettingsVisibility(
        permissionAny: [AppPermissions.viewInvoices],
        gates: [HomeActionFeatureGate.billing],
      ),
      sortOrder: 5,
    ),

    // ------------------------------------------------------------------- catalog
    SettingsLeaf(
      id: 'catalog.categories',
      category: SettingsCategoryId.catalog,
      group: 'Product attributes',
      title: 'Categories',
      subtitle: 'Group products so reports and filters stay useful',
      keywords: ['category', 'group', 'classification', 'tag'],
      icon: Icons.category_rounded,
      accent: AppTheme.primaryColor,
      destination: FeatureTarget('categories'),
    ),
    SettingsLeaf(
      id: 'catalog.companies',
      category: SettingsCategoryId.catalog,
      group: 'Product attributes',
      title: 'Companies',
      subtitle: 'Brands or manufacturers a product can belong to',
      keywords: ['company', 'brand', 'manufacturer', 'make'],
      icon: Icons.business_rounded,
      accent: AppTheme.infoColor,
      destination: SheetTarget(AppRoutes.settingsCatalog, 'companies'),
      visibility: SettingsVisibility(
        permissionAny: [AppPermissions.manageCompanySettings],
      ),
      sortOrder: 1,
    ),
    SettingsLeaf(
      id: 'catalog.subCategories',
      category: SettingsCategoryId.catalog,
      group: 'Product attributes',
      title: 'Sub-categories',
      subtitle: 'Sizes, variants or any second axis on a product',
      keywords: ['size', 'variant', 'sub category', 'subcategory', 'option'],
      icon: Icons.straighten_rounded,
      accent: AppTheme.accentColor,
      destination: SheetTarget(AppRoutes.settingsCatalog, 'sizes'),
      visibility: SettingsVisibility(
        permissionAny: [AppPermissions.manageCompanySettings],
      ),
      sortOrder: 2,
    ),
    SettingsLeaf(
      id: 'catalog.locations',
      category: SettingsCategoryId.catalog,
      group: 'Product attributes',
      title: 'Locations',
      subtitle: 'Where stock physically sits — shelves, rooms, shops',
      keywords: ['location', 'shelf', 'store', 'branch', 'rack', 'place'],
      icon: Icons.location_on_rounded,
      accent: AppTheme.warningColor,
      destination: SheetTarget(AppRoutes.settingsCatalog, 'locations'),
      visibility: SettingsVisibility(
        permissionAny: [AppPermissions.manageCompanySettings],
      ),
      sortOrder: 3,
    ),
    SettingsLeaf(
      id: 'catalog.zones',
      category: SettingsCategoryId.catalog,
      group: 'Warehouse',
      title: 'Warehouse zones',
      subtitle: 'Define storage zones and their capacity',
      keywords: ['zone', 'warehouse', 'aisle', 'bin', 'capacity', 'storage'],
      icon: Icons.warehouse_rounded,
      accent: AppTheme.indigoColor,
      destination: FeatureTarget('warehouseZones'),
      sortOrder: 4,
    ),

    // ---------------------------------------------------------------------- team
    SettingsLeaf(
      id: 'team.users',
      category: SettingsCategoryId.team,
      group: 'People',
      title: 'User management',
      subtitle: 'Invite team members and set what each one can do',
      keywords: ['user', 'staff', 'team', 'invite', 'member', 'employee'],
      icon: Icons.manage_accounts_rounded,
      accent: AppTheme.infoColor,
      destination: FeatureTarget('userManagement'),
    ),
    SettingsLeaf(
      id: 'team.roles',
      category: SettingsCategoryId.team,
      group: 'People',
      title: 'Roles & permissions',
      subtitle: 'Build reusable roles from granular permissions',
      keywords: ['role', 'permission', 'access', 'rbac', 'rights', 'privilege'],
      icon: Icons.admin_panel_settings_rounded,
      accent: AppTheme.primaryColor,
      destination: FeatureTarget('roles'),
      sortOrder: 1,
    ),
    SettingsLeaf(
      id: 'team.overrides',
      category: SettingsCategoryId.team,
      group: 'People',
      title: 'Permission overrides',
      subtitle: 'Grant or revoke a single permission for one person',
      keywords: ['override', 'exception', 'permission', 'per user', 'grant'],
      icon: Icons.shield_rounded,
      accent: AppTheme.warningColor,
      destination: RouteTarget(AppRoutes.staffPermissions),
      visibility: SettingsVisibility(
        permissionAll: [AppPermissions.manageUsers],
      ),
      sortOrder: 2,
    ),
    SettingsLeaf(
      id: 'team.vendors',
      category: SettingsCategoryId.team,
      group: 'Partners',
      title: 'Vendors',
      subtitle: 'Add, edit and track supplier performance',
      keywords: ['vendor', 'supplier', 'partner', 'purchase'],
      icon: Icons.local_shipping_rounded,
      accent: AppTheme.indigoColor,
      destination: RouteTarget(AppRoutes.vendors),
      visibility: SettingsVisibility(
        permissionAll: [AppPermissions.viewVendors],
        gates: [HomeActionFeatureGate.vendors],
      ),
      sortOrder: 3,
    ),
    SettingsLeaf(
      id: 'team.customers',
      category: SettingsCategoryId.team,
      group: 'Partners',
      title: 'Customers',
      subtitle: 'View and manage the people you sell to',
      keywords: ['customer', 'client', 'buyer', 'contact', 'partner'],
      icon: Icons.people_alt_rounded,
      accent: AppTheme.primaryColor,
      destination: RouteTarget(AppRoutes.customers),
      visibility: SettingsVisibility(
        permissionAll: [AppPermissions.viewCustomers],
      ),
      sortOrder: 4,
    ),

    // ---------------------------------------------------------------------- data
    SettingsLeaf(
      id: 'data.import',
      category: SettingsCategoryId.data,
      group: 'Spreadsheets',
      title: 'Import from Excel',
      subtitle: 'Bulk-create products from a spreadsheet',
      keywords: ['import', 'excel', 'csv', 'spreadsheet', 'upload', 'xlsx'],
      icon: Icons.upload_file_rounded,
      accent: AppTheme.infoColor,
      destination: FeatureTarget('excelImport'),
    ),
    SettingsLeaf(
      id: 'data.update',
      category: SettingsCategoryId.data,
      group: 'Spreadsheets',
      title: 'Update from Excel',
      subtitle: 'Update existing products in bulk from a spreadsheet',
      keywords: ['update', 'excel', 'csv', 'spreadsheet', 'bulk', 'xlsx'],
      icon: Icons.sync_rounded,
      accent: AppTheme.accentColor,
      destination: FeatureTarget('excelUpdate'),
      sortOrder: 1,
    ),
    SettingsLeaf(
      id: 'data.export',
      category: SettingsCategoryId.data,
      group: 'Spreadsheets',
      title: 'Export to Excel',
      subtitle: 'Download your products, stock and reports',
      keywords: ['export', 'excel', 'csv', 'download', 'backup', 'xlsx'],
      icon: Icons.download_rounded,
      accent: AppTheme.successColor,
      destination: FeatureTarget('excelExport'),
      sortOrder: 2,
    ),
    SettingsLeaf(
      id: 'data.health',
      category: SettingsCategoryId.data,
      group: 'Maintenance',
      title: 'Data health',
      subtitle: 'Find stock and invoice records that do not reconcile',
      keywords: ['health', 'diagnostic', 'reconcile', 'integrity', 'repair'],
      icon: Icons.health_and_safety_rounded,
      accent: AppTheme.dangerColor,
      destination: FeatureTarget('dataHealth'),
      sortOrder: 3,
    ),
    SettingsLeaf(
      id: 'data.bulkStockIn',
      category: SettingsCategoryId.data,
      group: 'Bulk actions',
      title: 'Bulk stock in',
      subtitle: 'Receive stock for many products at once',
      keywords: ['bulk', 'stock in', 'receive', 'many', 'batch entry'],
      icon: Icons.inventory_2_rounded,
      accent: AppTheme.successColor,
      destination: RouteTarget(AppRoutes.bulkStockIn),
      visibility: SettingsVisibility(
        permissionAll: [AppPermissions.bulkStockIn],
      ),
      sortOrder: 4,
    ),
    SettingsLeaf(
      id: 'data.bulkEdit',
      category: SettingsCategoryId.data,
      group: 'Bulk actions',
      title: 'Bulk edit',
      subtitle: 'Change a field across many products at once',
      keywords: ['bulk', 'edit', 'mass update', 'many products'],
      icon: Icons.edit_note_rounded,
      accent: AppTheme.infoColor,
      destination: RouteTarget(AppRoutes.bulkEdit),
      visibility: SettingsVisibility(permissionAll: [AppPermissions.bulkEdit]),
      sortOrder: 5,
    ),
    SettingsLeaf(
      id: 'data.companySwitcher',
      category: SettingsCategoryId.data,
      group: 'Workspace',
      title: 'Switch workspace',
      subtitle: 'Move between the companies you belong to',
      keywords: ['switch', 'workspace', 'company', 'tenant', 'organisation'],
      icon: Icons.swap_horiz_rounded,
      accent: AppTheme.primaryColor,
      destination: RouteTarget(AppRoutes.companySwitcher),
      sortOrder: 6,
    ),
    SettingsLeaf(
      id: 'data.onboarding',
      category: SettingsCategoryId.data,
      group: 'Workspace',
      title: 'Re-run setup wizard',
      subtitle: 'Walk through first-time setup again',
      keywords: ['onboarding', 'wizard', 'setup', 'getting started', 'tutorial'],
      icon: Icons.rocket_launch_rounded,
      accent: AppTheme.accentColor,
      destination: RouteTarget(AppRoutes.onboarding),
      sortOrder: 7,
    ),

    // ---------------------------------------------------------------------- plan
    SettingsLeaf(
      id: 'plan.features',
      category: SettingsCategoryId.plan,
      group: 'Plan',
      title: 'Plan & features',
      subtitle: 'Everything your tier includes and what is locked',
      keywords: ['plan', 'tier', 'upgrade', 'subscription', 'limits', 'quota'],
      icon: Icons.workspace_premium_rounded,
      accent: AppTheme.infoColor,
      destination: RouteTarget(AppRoutes.planFeatures),
    ),

    // ---------------------------------------------------------------------- help
    SettingsLeaf(
      id: 'help.guides',
      category: SettingsCategoryId.help,
      group: 'Help',
      title: 'Help & support',
      subtitle: 'Guides and answers to common questions',
      keywords: ['help', 'support', 'faq', 'guide', 'how to', 'contact'],
      icon: Icons.help_outline_rounded,
      accent: AppTheme.infoColor,
      destination: RouteTarget(AppRoutes.help),
    ),
    SettingsLeaf(
      id: 'help.activity',
      category: SettingsCategoryId.help,
      group: 'Help',
      title: 'Activity timeline',
      subtitle: 'Everything that happened in this workspace',
      keywords: ['activity', 'timeline', 'history', 'log', 'audit'],
      icon: Icons.timeline_rounded,
      accent: AppTheme.violetColor,
      destination: FeatureTarget('activityTimeline'),
      sortOrder: 1,
    ),
    SettingsLeaf(
      id: 'help.about',
      category: SettingsCategoryId.help,
      group: 'About',
      title: 'About this app',
      subtitle: 'Version, licences and credits',
      keywords: ['about', 'version', 'build', 'licence', 'license', 'credits'],
      icon: Icons.info_outline_rounded,
      accent: AppTheme.primaryColor,
      destination: RouteTarget(AppRoutes.about),
      sortOrder: 2,
    ),
    SettingsLeaf(
      id: 'help.privacy',
      category: SettingsCategoryId.help,
      group: 'Legal',
      title: 'Privacy policy',
      subtitle: 'What we collect and how it is used',
      keywords: ['privacy', 'policy', 'gdpr', 'data', 'legal'],
      icon: Icons.privacy_tip_rounded,
      accent: AppTheme.infoColor,
      destination: LinkTarget(
        url: 'https://smartshelfkart.com/privacy-policy',
        nativeRoute: AppRoutes.privacyPolicy,
      ),
      sortOrder: 3,
    ),
    SettingsLeaf(
      id: 'help.terms',
      category: SettingsCategoryId.help,
      group: 'Legal',
      title: 'Terms of service',
      subtitle: 'The agreement covering your use of the app',
      keywords: ['terms', 'conditions', 'agreement', 'legal', 'tos'],
      icon: Icons.gavel_rounded,
      accent: AppTheme.textSecondary,
      destination: LinkTarget(
        url: 'https://smartshelfkart.com/terms',
        nativeRoute: AppRoutes.terms,
      ),
      sortOrder: 4,
    ),
    SettingsLeaf(
      id: 'help.support',
      category: SettingsCategoryId.help,
      group: 'Legal',
      title: 'Contact support',
      subtitle: 'Reach the team behind the app',
      keywords: ['support', 'contact', 'email', 'help desk', 'ticket'],
      icon: Icons.support_agent_rounded,
      accent: AppTheme.successColor,
      destination: LinkTarget(
        url: 'https://smartshelfkart.com/support',
        nativeRoute: AppRoutes.support,
      ),
      sortOrder: 5,
    ),
    SettingsLeaf(
      id: 'help.dataDeletion',
      category: SettingsCategoryId.help,
      group: 'Legal',
      title: 'Data deletion',
      subtitle: 'How to have your data removed',
      keywords: ['data deletion', 'erase', 'remove data', 'gdpr', 'right to be forgotten'],
      icon: Icons.delete_sweep_rounded,
      accent: AppTheme.dangerColor,
      destination: LinkTarget(
        url: 'https://smartshelfkart.com/data-deletion',
        nativeRoute: AppRoutes.dataDeletion,
      ),
      sortOrder: 6,
    ),
  ];

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  static SettingsCategory categoryById(SettingsCategoryId id) =>
      categories.firstWhere((c) => c.id == id);

  static String categoryTitle(SettingsCategoryId id) => categoryById(id).title;

  /// Every leaf in [id], in `sortOrder` then declaration order.
  static List<SettingsLeaf> leavesIn(SettingsCategoryId id) {
    final list = leaves.where((l) => l.category == id).toList();
    list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  /// [leavesIn] filtered to what [ctx] may see.
  static List<SettingsLeaf> visibleLeavesIn(
    SettingsCategoryId id,
    SettingsVisibilityContext ctx,
  ) => leavesIn(id).where((l) => isSettingVisible(l, ctx)).toList();

  /// Categories with at least one visible leaf, in `sortOrder`.
  ///
  /// A category row that leads to an empty page is worse than no row: it reads
  /// as something broken rather than something the user has no access to.
  static List<SettingsCategory> visibleCategories(
    SettingsVisibilityContext ctx,
  ) {
    final list = categories
        .where((c) => leavesIn(c.id).any((l) => isSettingVisible(l, ctx)))
        .toList();
    list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  /// The categories that get their own row on the hub.
  ///
  /// [SettingsCategoryId.account] is excluded: the profile card at the top of
  /// the hub already *is* that row, and listing the category underneath it put
  /// two controls opening the same screen directly above one another. It stays
  /// in [visibleCategories] and in the leaf list so search still finds
  /// "password" and "delete account".
  static List<SettingsCategory> hubRowCategories(
    SettingsVisibilityContext ctx,
  ) => visibleCategories(
    ctx,
  ).where((c) => c.id != SettingsCategoryId.account).toList();

  static SettingsLeaf? leafById(String id) {
    for (final leaf in leaves) {
      if (leaf.id == id) return leaf;
    }
    return null;
  }
}
