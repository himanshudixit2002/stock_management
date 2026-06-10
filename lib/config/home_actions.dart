import 'package:flutter/material.dart';
import 'permissions.dart';
import 'routes.dart';
import 'theme.dart';

/// Company-level feature toggles (Settings) required before a home action applies.
enum HomeActionFeatureGate { billing, barcode, vendors, pricing }

class HomeAction {
  final String id;
  final String label;
  final IconData icon;
  final LinearGradient gradient;
  final String route;
  final String? permissionKey;

  /// All gates must be satisfied (AND). Empty means no feature flags apply.
  final List<HomeActionFeatureGate> featureGates;

  const HomeAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.gradient,
    required this.route,
    this.permissionKey,
    this.featureGates = const [],
  });
}

class HomeActionsRegistry {
  static const List<String> defaultActionIds = [
    'fastPos',
    'stockIn',
    'stockOut',
    'holds',
    'release',
    'hold',
  ];

  static const int maxActions = 6;

  static final List<HomeAction> allActions = [
    HomeAction(
      id: 'stockIn',
      label: 'Stock In',
      icon: Icons.add_circle_rounded,
      gradient: AppTheme.successGradient,
      route: AppRoutes.stockIn,
      permissionKey: AppPermissions.stockIn,
    ),
    HomeAction(
      id: 'stockOut',
      label: 'Stock Out',
      icon: Icons.remove_circle_rounded,
      gradient: AppTheme.primaryGradient,
      route: AppRoutes.stockOut,
      permissionKey: AppPermissions.stockOut,
    ),
    HomeAction(
      id: 'damage',
      label: 'Damage',
      icon: Icons.broken_image_rounded,
      gradient: AppTheme.dangerGradient,
      route: AppRoutes.damageReport,
      permissionKey: AppPermissions.damage,
    ),
    HomeAction(
      id: 'transfer',
      label: 'Transfer',
      icon: Icons.swap_horiz_rounded,
      gradient: AppTheme.indigoGradient,
      route: AppRoutes.stockTransfer,
      permissionKey: AppPermissions.transfer,
    ),
    HomeAction(
      id: 'adjust',
      label: 'Adjust',
      icon: Icons.tune_rounded,
      gradient: AppTheme.warningGradient,
      route: AppRoutes.stockAdjustment,
      permissionKey: AppPermissions.adjustStock,
    ),
    HomeAction(
      id: 'hold',
      label: 'Hold Stock',
      icon: Icons.pause_circle_rounded,
      gradient: AppTheme.warningGradient,
      route: AppRoutes.stockHold,
      permissionKey: AppPermissions.holdStock,
    ),
    HomeAction(
      id: 'release',
      label: 'Release Hold',
      icon: Icons.play_circle_rounded,
      gradient: AppTheme.successGradient,
      route: AppRoutes.stockRelease,
      permissionKey: AppPermissions.releaseStock,
    ),
    HomeAction(
      id: 'holds',
      label: 'Hold Dashboard',
      icon: Icons.lock_clock_rounded,
      gradient: AppTheme.indigoGradient,
      route: AppRoutes.stockHolds,
      permissionKey: AppPermissions.viewStockHolds,
    ),
    HomeAction(
      id: 'purchaseOrders',
      label: 'Purchase Orders',
      icon: Icons.receipt_long,
      gradient: AppTheme.primaryGradient,
      route: AppRoutes.purchaseOrders,
      permissionKey: AppPermissions.viewPurchaseOrders,
    ),
    HomeAction(
      id: 'salesOrders',
      label: 'Sales Orders',
      icon: Icons.local_shipping,
      gradient: AppTheme.successGradient,
      route: AppRoutes.salesOrders,
      permissionKey: AppPermissions.viewSalesOrders,
    ),
    HomeAction(
      id: 'returns',
      label: 'Returns',
      icon: Icons.assignment_return,
      gradient: AppTheme.warmGradient,
      route: AppRoutes.returns,
      permissionKey: AppPermissions.viewReturns,
    ),
    HomeAction(
      id: 'customers',
      label: 'Customers',
      icon: Icons.people,
      gradient: AppTheme.indigoGradient,
      route: AppRoutes.customers,
      permissionKey: AppPermissions.viewCustomers,
    ),
    HomeAction(
      id: 'batchTracking',
      label: 'Batch Tracking',
      icon: Icons.layers,
      gradient: AppTheme.warningGradient,
      route: AppRoutes.batches,
      permissionKey: AppPermissions.manageBatches,
    ),
    HomeAction(
      id: 'reorder',
      label: 'Reorder',
      icon: Icons.shopping_cart_checkout,
      gradient: AppTheme.dangerGradient,
      route: AppRoutes.reorderSuggestions,
      permissionKey: AppPermissions.viewReorderSuggestions,
    ),
    HomeAction(
      id: 'stockForecast',
      label: 'Stock Forecast',
      icon: Icons.trending_up,
      gradient: AppTheme.primaryGradient,
      route: AppRoutes.stockForecast,
      permissionKey: AppPermissions.viewStockForecast,
    ),
    HomeAction(
      id: 'stockTake',
      label: 'Stock Take',
      icon: Icons.fact_check,
      gradient: AppTheme.successGradient,
      route: AppRoutes.stockTakes,
      permissionKey: AppPermissions.manageStockTakes,
    ),
    HomeAction(
      id: 'dashboard',
      label: 'Dashboard',
      icon: Icons.dashboard_rounded,
      gradient: AppTheme.heroGradient,
      route: AppRoutes.dashboard,
      permissionKey: AppPermissions.viewDashboard,
    ),
    HomeAction(
      id: 'lowStock',
      label: 'Low Stock',
      icon: Icons.warning_amber_rounded,
      gradient: AppTheme.warningGradient,
      route: AppRoutes.lowStock,
      permissionKey: AppPermissions.viewProducts,
    ),
    HomeAction(
      id: 'barcodeScanner',
      label: 'Barcode Scanner',
      icon: Icons.qr_code_scanner,
      gradient: AppTheme.indigoGradient,
      route: AppRoutes.barcodeScanner,
      featureGates: [HomeActionFeatureGate.barcode],
    ),
    HomeAction(
      id: 'fastPos',
      label: 'Fast POS',
      icon: Icons.point_of_sale_rounded,
      gradient: AppTheme.successGradient,
      route: AppRoutes.fastPos,
      permissionKey: AppPermissions.useFastPos,
      featureGates: [HomeActionFeatureGate.billing],
    ),
    HomeAction(
      id: 'invoices',
      label: 'Billing',
      icon: Icons.receipt_long_rounded,
      gradient: AppTheme.successGradient,
      route: AppRoutes.invoices,
      permissionKey: AppPermissions.viewInvoices,
      featureGates: [HomeActionFeatureGate.billing],
    ),
    HomeAction(
      id: 'billingReports',
      label: 'Billing Reports',
      icon: Icons.bar_chart_rounded,
      gradient: AppTheme.primaryGradient,
      route: AppRoutes.billingReports,
      permissionKey: AppPermissions.viewInvoices,
      featureGates: [HomeActionFeatureGate.billing],
    ),
  ];

  static HomeAction? getById(String id) {
    final idx = allActions.indexWhere((a) => a.id == id);
    return idx == -1 ? null : allActions[idx];
  }
}
