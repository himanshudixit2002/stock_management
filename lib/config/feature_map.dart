import 'package:flutter/material.dart';

import 'home_actions.dart' show HomeActionFeatureGate;
import 'permissions.dart';
import 'routes.dart';
import 'theme.dart';

/// High-level grouping a feature belongs to. Drives the categorized Home grid
/// and the section headers / subtitles across the app.
enum FeatureCategory { dailyOps, orders, inventory, billing, reports, admin }

/// Where a feature's primary entry point lives. This is the single source of
/// truth so a feature is surfaced in exactly one canonical place (avoiding the
/// previous duplicate entry points), while remaining reachable everywhere via
/// the catalog queries below.
enum FeaturePlacement {
  /// Surfaced in the raised "Quick Actions" sheet (daily, high-frequency).
  homePrimary,

  /// Surfaced in the categorized Home grid, grouped by [FeatureCategory].
  homeSecondary,

  /// Surfaced as a chip in a tab's contextual sub-header.
  tabShortcut,

  /// Reached from the Settings tab.
  settingsOnly,

  /// Reached primarily through global search / deep links.
  searchOnly,
}

/// A single catalogued feature. Routes + permission keys are reused verbatim
/// from [AppRoutes] / [AppPermissions] so this stays a faithful catalog and
/// never invents destinations.
class FeatureEntry {
  final String id;
  final String label;

  /// One-line description so users know what the feature does.
  final String subtitle;
  final IconData icon;
  final String route;
  final FeatureCategory category;
  final FeaturePlacement placement;
  final String? permissionKey;

  /// Company-level feature toggles (all must pass) required for visibility.
  final List<HomeActionFeatureGate> featureGates;
  final int sortOrder;

  const FeatureEntry({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.route,
    required this.category,
    required this.placement,
    this.permissionKey,
    this.featureGates = const [],
    this.sortOrder = 0,
  });
}

/// Display metadata for a [FeatureCategory] (used by section headers).
class FeatureCategoryMeta {
  final String title;
  final String subtitle;
  final IconData icon;

  const FeatureCategoryMeta({
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

/// Single source of truth describing where every feature lives in the app's
/// information architecture. UI-only: it never mutates permissions or routes.
class FeatureMap {
  FeatureMap._();

  static const Map<FeatureCategory, FeatureCategoryMeta> categoryMeta = {
    FeatureCategory.dailyOps: FeatureCategoryMeta(
      title: 'Daily Operations',
      subtitle: 'Move, hold and adjust stock in a tap',
      icon: Icons.bolt_rounded,
    ),
    FeatureCategory.orders: FeatureCategoryMeta(
      title: 'Orders & Customers',
      subtitle: 'Purchases, sales, returns and contacts',
      icon: Icons.receipt_long_rounded,
    ),
    FeatureCategory.inventory: FeatureCategoryMeta(
      title: 'Smart Inventory',
      subtitle: 'Batches, forecasts, counts and reorders',
      icon: Icons.layers_rounded,
    ),
    FeatureCategory.billing: FeatureCategoryMeta(
      title: 'Billing',
      subtitle: 'Invoices, payments and point of sale',
      icon: Icons.point_of_sale_rounded,
    ),
    FeatureCategory.reports: FeatureCategoryMeta(
      title: 'Insights & Reports',
      subtitle: 'Dashboards, history and analysis',
      icon: Icons.analytics_rounded,
    ),
    FeatureCategory.admin: FeatureCategoryMeta(
      title: 'Admin & Tools',
      subtitle: 'Data, zones and team management',
      icon: Icons.admin_panel_settings_rounded,
    ),
  };

  /// The full catalog. Each feature appears once with a single canonical
  /// [placement]; queries below re-surface them where needed.
  static const List<FeatureEntry> all = [
    // ---------------- Daily operations (Quick Actions sheet) ----------------
    FeatureEntry(
      id: 'stockIn',
      label: 'Stock In',
      subtitle: 'Receive and add stock to products',
      icon: Icons.add_circle_rounded,
      route: AppRoutes.stockIn,
      category: FeatureCategory.dailyOps,
      placement: FeaturePlacement.homePrimary,
      permissionKey: AppPermissions.stockIn,
      sortOrder: 0,
    ),
    FeatureEntry(
      id: 'stockOut',
      label: 'Stock Out',
      subtitle: 'Remove or issue stock from products',
      icon: Icons.remove_circle_rounded,
      route: AppRoutes.stockOut,
      category: FeatureCategory.dailyOps,
      placement: FeaturePlacement.homePrimary,
      permissionKey: AppPermissions.stockOut,
      sortOrder: 1,
    ),
    FeatureEntry(
      id: 'transfer',
      label: 'Transfer',
      subtitle: 'Move stock between locations',
      icon: Icons.swap_horiz_rounded,
      route: AppRoutes.stockTransfer,
      category: FeatureCategory.dailyOps,
      placement: FeaturePlacement.homePrimary,
      permissionKey: AppPermissions.transfer,
      sortOrder: 2,
    ),
    FeatureEntry(
      id: 'damage',
      label: 'Damage',
      subtitle: 'Record damaged or written-off stock',
      icon: Icons.broken_image_rounded,
      route: AppRoutes.damageReport,
      category: FeatureCategory.dailyOps,
      placement: FeaturePlacement.homePrimary,
      permissionKey: AppPermissions.damage,
      sortOrder: 3,
    ),
    FeatureEntry(
      id: 'adjust',
      label: 'Adjust',
      subtitle: 'Correct stock counts manually',
      icon: Icons.tune_rounded,
      route: AppRoutes.stockAdjustment,
      category: FeatureCategory.dailyOps,
      placement: FeaturePlacement.homePrimary,
      permissionKey: AppPermissions.adjustStock,
      sortOrder: 4,
    ),
    FeatureEntry(
      id: 'hold',
      label: 'Hold Stock',
      subtitle: 'Reserve stock for later release',
      icon: Icons.pause_circle_rounded,
      route: AppRoutes.stockHold,
      category: FeatureCategory.dailyOps,
      placement: FeaturePlacement.homePrimary,
      permissionKey: AppPermissions.holdStock,
      sortOrder: 5,
    ),
    FeatureEntry(
      id: 'release',
      label: 'Release Hold',
      subtitle: 'Release previously held stock',
      icon: Icons.play_circle_rounded,
      route: AppRoutes.stockRelease,
      category: FeatureCategory.dailyOps,
      placement: FeaturePlacement.homePrimary,
      permissionKey: AppPermissions.releaseStock,
      sortOrder: 6,
    ),
    FeatureEntry(
      id: 'fastPos',
      label: 'Fast POS',
      subtitle: 'Quick checkout and point of sale',
      icon: Icons.point_of_sale_rounded,
      route: AppRoutes.fastPos,
      category: FeatureCategory.dailyOps,
      placement: FeaturePlacement.homePrimary,
      permissionKey: AppPermissions.useFastPos,
      featureGates: [HomeActionFeatureGate.billing],
      sortOrder: 7,
    ),

    // ---------------- Orders & Customers (Home grid) ----------------
    FeatureEntry(
      id: 'purchaseOrders',
      label: 'Purchase Orders',
      subtitle: 'Raise and track supplier orders',
      icon: Icons.receipt_long,
      route: AppRoutes.purchaseOrders,
      category: FeatureCategory.orders,
      placement: FeaturePlacement.homeSecondary,
      permissionKey: AppPermissions.viewPurchaseOrders,
      sortOrder: 0,
    ),
    FeatureEntry(
      id: 'salesOrders',
      label: 'Sales Orders',
      subtitle: 'Manage customer sales orders',
      icon: Icons.local_shipping,
      route: AppRoutes.salesOrders,
      category: FeatureCategory.orders,
      placement: FeaturePlacement.homeSecondary,
      permissionKey: AppPermissions.viewSalesOrders,
      sortOrder: 1,
    ),
    FeatureEntry(
      id: 'returns',
      label: 'Returns',
      subtitle: 'Process customer and supplier returns',
      icon: Icons.assignment_return,
      route: AppRoutes.returns,
      category: FeatureCategory.orders,
      placement: FeaturePlacement.homeSecondary,
      permissionKey: AppPermissions.viewReturns,
      sortOrder: 2,
    ),
    FeatureEntry(
      id: 'customers',
      label: 'Customers',
      subtitle: 'View and manage customer records',
      icon: Icons.people,
      route: AppRoutes.customers,
      category: FeatureCategory.orders,
      placement: FeaturePlacement.homeSecondary,
      permissionKey: AppPermissions.viewCustomers,
      sortOrder: 3,
    ),

    // ---------------- Billing (Home grid) ----------------
    FeatureEntry(
      id: 'invoices',
      label: 'Billing',
      subtitle: 'Create and manage invoices',
      icon: Icons.receipt_long_rounded,
      route: AppRoutes.invoices,
      category: FeatureCategory.billing,
      placement: FeaturePlacement.homeSecondary,
      permissionKey: AppPermissions.viewInvoices,
      featureGates: [HomeActionFeatureGate.billing],
      sortOrder: 0,
    ),
    FeatureEntry(
      id: 'billingReports',
      label: 'Billing Reports',
      subtitle: 'Revenue and payment summaries',
      icon: Icons.bar_chart_rounded,
      route: AppRoutes.billingReports,
      category: FeatureCategory.billing,
      placement: FeaturePlacement.homeSecondary,
      permissionKey: AppPermissions.viewInvoices,
      featureGates: [HomeActionFeatureGate.billing],
      sortOrder: 1,
    ),

    // ---------------- Smart Inventory (Home grid) ----------------
    FeatureEntry(
      id: 'barcodeScanner',
      label: 'Barcode Scanner',
      subtitle: 'Scan barcodes to find products',
      icon: Icons.qr_code_scanner,
      route: AppRoutes.barcodeScanner,
      category: FeatureCategory.inventory,
      placement: FeaturePlacement.homeSecondary,
      featureGates: [HomeActionFeatureGate.barcode],
      sortOrder: 0,
    ),
    FeatureEntry(
      id: 'batchTracking',
      label: 'Batch Tracking',
      subtitle: 'Track lots and expiry by batch',
      icon: Icons.layers,
      route: AppRoutes.batches,
      category: FeatureCategory.inventory,
      placement: FeaturePlacement.homeSecondary,
      permissionKey: AppPermissions.manageBatches,
      sortOrder: 1,
    ),
    FeatureEntry(
      id: 'reorder',
      label: 'Reorder',
      subtitle: 'See what needs restocking',
      icon: Icons.shopping_cart_checkout,
      route: AppRoutes.reorderSuggestions,
      category: FeatureCategory.inventory,
      placement: FeaturePlacement.homeSecondary,
      permissionKey: AppPermissions.viewReorderSuggestions,
      sortOrder: 2,
    ),
    FeatureEntry(
      id: 'stockForecast',
      label: 'Stock Forecast',
      subtitle: 'Project demand and runway',
      icon: Icons.trending_up,
      route: AppRoutes.stockForecast,
      category: FeatureCategory.inventory,
      placement: FeaturePlacement.homeSecondary,
      permissionKey: AppPermissions.viewStockForecast,
      sortOrder: 3,
    ),
    FeatureEntry(
      id: 'stockTake',
      label: 'Stock Take',
      subtitle: 'Count and reconcile inventory',
      icon: Icons.fact_check,
      route: AppRoutes.stockTakes,
      category: FeatureCategory.inventory,
      placement: FeaturePlacement.homeSecondary,
      permissionKey: AppPermissions.manageStockTakes,
      sortOrder: 4,
    ),
    FeatureEntry(
      id: 'stockHolds',
      label: 'Stock Holds',
      subtitle: 'Dashboard of active stock holds',
      icon: Icons.lock_clock_rounded,
      route: AppRoutes.stockHolds,
      category: FeatureCategory.inventory,
      placement: FeaturePlacement.homeSecondary,
      permissionKey: AppPermissions.viewStockHolds,
      sortOrder: 5,
    ),

    // ---------------- Products tab shortcuts ----------------
    FeatureEntry(
      id: 'lowStock',
      label: 'Low Stock',
      subtitle: 'Products below their reorder level',
      icon: Icons.warning_amber_rounded,
      route: AppRoutes.lowStock,
      category: FeatureCategory.inventory,
      placement: FeaturePlacement.tabShortcut,
      permissionKey: AppPermissions.viewProducts,
      sortOrder: 0,
    ),
    FeatureEntry(
      id: 'categories',
      label: 'Categories',
      subtitle: 'Organise products into categories',
      icon: Icons.category_rounded,
      route: AppRoutes.categories,
      category: FeatureCategory.inventory,
      placement: FeaturePlacement.tabShortcut,
      permissionKey: AppPermissions.manageCategories,
      sortOrder: 1,
    ),
    FeatureEntry(
      id: 'expiryAlerts',
      label: 'Expiry Alerts',
      subtitle: 'Batches approaching expiry',
      icon: Icons.timer_rounded,
      route: AppRoutes.expiryAlerts,
      category: FeatureCategory.inventory,
      placement: FeaturePlacement.tabShortcut,
      permissionKey: AppPermissions.viewExpiryAlerts,
      sortOrder: 2,
    ),

    // ---------------- Reports tab shortcuts ----------------
    FeatureEntry(
      id: 'dashboard',
      label: 'Dashboard',
      subtitle: 'Visual overview of inventory health',
      icon: Icons.dashboard_rounded,
      route: AppRoutes.dashboard,
      category: FeatureCategory.reports,
      placement: FeaturePlacement.tabShortcut,
      permissionKey: AppPermissions.viewDashboard,
      sortOrder: 0,
    ),
    FeatureEntry(
      id: 'transactionHistory',
      label: 'Full History',
      subtitle: 'Every stock transaction in one place',
      icon: Icons.history_rounded,
      route: AppRoutes.transactionHistory,
      category: FeatureCategory.reports,
      placement: FeaturePlacement.tabShortcut,
      permissionKey: AppPermissions.viewReports,
      sortOrder: 1,
    ),
    FeatureEntry(
      id: 'damageHistory',
      label: 'Damage Report',
      subtitle: 'History of damaged stock',
      icon: Icons.report_problem_rounded,
      route: AppRoutes.damageHistory,
      category: FeatureCategory.reports,
      placement: FeaturePlacement.tabShortcut,
      permissionKey: AppPermissions.damage,
      sortOrder: 2,
    ),

    // ---------------- Reports (search / deep reports) ----------------
    FeatureEntry(
      id: 'profitLoss',
      label: 'Profit & Loss',
      subtitle: 'Margins across your catalog',
      icon: Icons.account_balance_wallet_rounded,
      route: AppRoutes.profitLoss,
      category: FeatureCategory.reports,
      placement: FeaturePlacement.searchOnly,
      permissionKey: AppPermissions.viewReports,
      sortOrder: 3,
    ),
    FeatureEntry(
      id: 'abcAnalysis',
      label: 'ABC Analysis',
      subtitle: 'Rank products by value contribution',
      icon: Icons.stacked_bar_chart_rounded,
      route: AppRoutes.abcAnalysis,
      category: FeatureCategory.reports,
      placement: FeaturePlacement.searchOnly,
      permissionKey: AppPermissions.viewReports,
      sortOrder: 4,
    ),
    FeatureEntry(
      id: 'valuationTrends',
      label: 'Inventory Valuation',
      subtitle: 'Track stock value over time',
      icon: Icons.trending_up_rounded,
      route: AppRoutes.valuationTrends,
      category: FeatureCategory.reports,
      placement: FeaturePlacement.searchOnly,
      permissionKey: AppPermissions.viewReports,
      sortOrder: 5,
    ),
    FeatureEntry(
      id: 'auditLog',
      label: 'Audit Log',
      subtitle: 'Every change made in the system',
      icon: Icons.history_edu_rounded,
      route: AppRoutes.auditLog,
      category: FeatureCategory.reports,
      placement: FeaturePlacement.searchOnly,
      permissionKey: AppPermissions.viewAuditLog,
      sortOrder: 6,
    ),
    FeatureEntry(
      id: 'priceHistory',
      label: 'Price History',
      subtitle: 'Historical price changes',
      icon: Icons.price_change_rounded,
      route: AppRoutes.priceHistory,
      category: FeatureCategory.reports,
      placement: FeaturePlacement.searchOnly,
      permissionKey: AppPermissions.viewReports,
      sortOrder: 7,
    ),

    // ---------------- Admin & Tools (Settings) ----------------
    FeatureEntry(
      id: 'excelImport',
      label: 'Import from Excel',
      subtitle: 'Bulk import products from a spreadsheet',
      icon: Icons.upload_file_rounded,
      route: AppRoutes.excelImport,
      category: FeatureCategory.admin,
      placement: FeaturePlacement.settingsOnly,
      permissionKey: AppPermissions.importData,
      sortOrder: 0,
    ),
    FeatureEntry(
      id: 'excelUpdate',
      label: 'Update from Excel',
      subtitle: 'Update existing products in bulk',
      icon: Icons.sync_rounded,
      route: AppRoutes.excelUpdate,
      category: FeatureCategory.admin,
      placement: FeaturePlacement.settingsOnly,
      permissionKey: AppPermissions.importData,
      sortOrder: 1,
    ),
    FeatureEntry(
      id: 'excelExport',
      label: 'Export to Excel',
      subtitle: 'Export reports and data',
      icon: Icons.download_rounded,
      route: AppRoutes.excelExport,
      category: FeatureCategory.admin,
      placement: FeaturePlacement.settingsOnly,
      permissionKey: AppPermissions.exportData,
      sortOrder: 2,
    ),
    FeatureEntry(
      id: 'warehouseZones',
      label: 'Warehouse Zones',
      subtitle: 'Define and manage warehouse zones',
      icon: Icons.warehouse_rounded,
      route: AppRoutes.warehouseZones,
      category: FeatureCategory.admin,
      placement: FeaturePlacement.settingsOnly,
      permissionKey: AppPermissions.manageWarehouseZones,
      sortOrder: 3,
    ),
    FeatureEntry(
      id: 'userManagement',
      label: 'User Management',
      subtitle: 'Add team members and assign roles',
      icon: Icons.manage_accounts_rounded,
      route: AppRoutes.userManagement,
      category: FeatureCategory.admin,
      placement: FeaturePlacement.settingsOnly,
      permissionKey: AppPermissions.viewUsers,
      sortOrder: 4,
    ),
    FeatureEntry(
      id: 'roles',
      label: 'Roles',
      subtitle: 'Create and edit permission roles',
      icon: Icons.admin_panel_settings_rounded,
      route: AppRoutes.roles,
      category: FeatureCategory.admin,
      placement: FeaturePlacement.settingsOnly,
      permissionKey: AppPermissions.manageRoles,
      sortOrder: 5,
    ),
  ];

  // --------------------------------------------------------------------------
  // Query helpers (read-only; never mutate permissions).
  // --------------------------------------------------------------------------

  /// True when [entry] passes its permission key and all company feature gates.
  /// Permissions are read exactly as elsewhere in the app (the effective
  /// permissions map from the current user).
  static bool isVisible(
    FeatureEntry entry,
    Map<String, bool> permissions, {
    bool billingEnabled = false,
    bool barcodeEnabled = true,
    bool vendorsEnabled = true,
    bool pricingEnabled = true,
  }) {
    if (entry.permissionKey != null &&
        permissions[entry.permissionKey] != true) {
      return false;
    }
    for (final gate in entry.featureGates) {
      switch (gate) {
        case HomeActionFeatureGate.billing:
          if (!billingEnabled) return false;
        case HomeActionFeatureGate.barcode:
          if (!barcodeEnabled) return false;
        case HomeActionFeatureGate.vendors:
          if (!vendorsEnabled) return false;
        case HomeActionFeatureGate.pricing:
          if (!pricingEnabled) return false;
      }
    }
    return true;
  }

  /// All entries with the given [placement], sorted by [FeatureEntry.sortOrder].
  static List<FeatureEntry> entriesFor(FeaturePlacement placement) {
    final list = all.where((e) => e.placement == placement).toList();
    list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  /// Visible entries with the given [placement] filtered by permission + gates.
  static List<FeatureEntry> visibleEntriesFor(
    FeaturePlacement placement,
    Map<String, bool> permissions, {
    bool billingEnabled = false,
    bool barcodeEnabled = true,
    bool vendorsEnabled = true,
    bool pricingEnabled = true,
  }) {
    return entriesFor(placement)
        .where(
          (e) => isVisible(
            e,
            permissions,
            billingEnabled: billingEnabled,
            barcodeEnabled: barcodeEnabled,
            vendorsEnabled: vendorsEnabled,
            pricingEnabled: pricingEnabled,
          ),
        )
        .toList();
  }

  /// Visible entries in [category] (optionally restricted to a [placement]),
  /// filtered by permission + gates and sorted by [FeatureEntry.sortOrder].
  static List<FeatureEntry> entriesByCategory(
    FeatureCategory category,
    Map<String, bool> permissions, {
    FeaturePlacement? placement,
    bool billingEnabled = false,
    bool barcodeEnabled = true,
    bool vendorsEnabled = true,
    bool pricingEnabled = true,
  }) {
    final list = all
        .where(
          (e) =>
              e.category == category &&
              (placement == null || e.placement == placement) &&
              isVisible(
                e,
                permissions,
                billingEnabled: billingEnabled,
                barcodeEnabled: barcodeEnabled,
                vendorsEnabled: vendorsEnabled,
                pricingEnabled: pricingEnabled,
              ),
        )
        .toList();
    list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  /// Ordered categories that have at least one visible [homeSecondary] entry,
  /// used to build the categorized Home grid.
  static List<FeatureCategory> homeGridCategories(
    Map<String, bool> permissions, {
    bool billingEnabled = false,
    bool barcodeEnabled = true,
    bool vendorsEnabled = true,
    bool pricingEnabled = true,
  }) {
    const order = [
      FeatureCategory.orders,
      FeatureCategory.billing,
      FeatureCategory.inventory,
    ];
    return order
        .where(
          (c) => entriesByCategory(
            c,
            permissions,
            placement: FeaturePlacement.homeSecondary,
            billingEnabled: billingEnabled,
            barcodeEnabled: barcodeEnabled,
            vendorsEnabled: vendorsEnabled,
            pricingEnabled: pricingEnabled,
          ).isNotEmpty,
        )
        .toList();
  }

  static FeatureEntry? getById(String id) {
    final idx = all.indexWhere((e) => e.id == id);
    return idx == -1 ? null : all[idx];
  }

  /// Convenience accent color for a category (reusing [AppTheme] tokens).
  static Color categoryColor(FeatureCategory category) {
    switch (category) {
      case FeatureCategory.dailyOps:
        return AppTheme.primaryColor;
      case FeatureCategory.orders:
        return AppTheme.indigoColor;
      case FeatureCategory.inventory:
        return AppTheme.successColor;
      case FeatureCategory.billing:
        return AppTheme.infoColor;
      case FeatureCategory.reports:
        return AppTheme.warningColor;
      case FeatureCategory.admin:
        return AppTheme.violetColor;
    }
  }
}
