import 'package:flutter/material.dart';

class PermissionDef {
  final String key;
  final String label;
  final String description;
  final String group;
  final IconData icon;

  const PermissionDef({
    required this.key,
    required this.label,
    required this.description,
    required this.group,
    required this.icon,
  });
}

class PermissionGroup {
  final String id;
  final String label;
  final IconData icon;

  const PermissionGroup({
    required this.id,
    required this.label,
    required this.icon,
  });
}

class AppPermissions {
  AppPermissions._();

  // ---------------------------------------------------------------------------
  // Permission Groups
  // ---------------------------------------------------------------------------
  static const List<PermissionGroup> groups = [
    PermissionGroup(id: 'dashboard', label: 'Dashboard & Reports', icon: Icons.dashboard_rounded),
    PermissionGroup(id: 'products', label: 'Products & Categories', icon: Icons.inventory_2_rounded),
    PermissionGroup(id: 'stock', label: 'Stock Operations', icon: Icons.swap_vert_rounded),
    PermissionGroup(id: 'purchaseOrders', label: 'Purchase Orders', icon: Icons.receipt_long_rounded),
    PermissionGroup(id: 'salesOrders', label: 'Sales Orders', icon: Icons.local_shipping_rounded),
    PermissionGroup(id: 'returns', label: 'Returns', icon: Icons.assignment_return_rounded),
    PermissionGroup(id: 'customers', label: 'Customers', icon: Icons.people_rounded),
    PermissionGroup(id: 'vendors', label: 'Vendors', icon: Icons.store_rounded),
    PermissionGroup(id: 'inventory', label: 'Inventory & Batches', icon: Icons.layers_rounded),
    PermissionGroup(id: 'billing', label: 'Billing & Invoices', icon: Icons.receipt_rounded),
    PermissionGroup(id: 'importExport', label: 'Import / Export', icon: Icons.import_export_rounded),
    PermissionGroup(id: 'users', label: 'User Management', icon: Icons.admin_panel_settings_rounded),
    PermissionGroup(id: 'settings', label: 'Settings & Company', icon: Icons.settings_rounded),
  ];

  // ---------------------------------------------------------------------------
  // Permission Keys (constants for compile-time safety)
  // ---------------------------------------------------------------------------

  // Dashboard & Reports
  static const String viewDashboard = 'canViewDashboard';
  static const String viewReports = 'canViewReports';
  static const String viewAuditLog = 'canViewAuditLog';
  static const String viewActivityTimeline = 'canViewActivityTimeline';

  // Products & Categories
  static const String viewProducts = 'canViewProducts';
  static const String addProducts = 'canAddProducts';
  static const String editProducts = 'canEditProducts';
  static const String deleteProducts = 'canDeleteProducts';
  static const String manageCategories = 'canManageCategories';

  // Stock Operations
  static const String stockIn = 'canStockIn';
  static const String stockOut = 'canStockOut';
  static const String damage = 'canDamage';
  static const String transfer = 'canTransfer';
  static const String adjustStock = 'canAdjustStock';
  static const String bulkStockIn = 'canBulkStockIn';
  static const String bulkEdit = 'canBulkEdit';

  // Purchase Orders
  static const String viewPurchaseOrders = 'canViewPurchaseOrders';
  static const String createPurchaseOrders = 'canCreatePurchaseOrders';
  static const String editPurchaseOrders = 'canEditPurchaseOrders';
  static const String deletePurchaseOrders = 'canDeletePurchaseOrders';
  static const String approvePurchaseOrders = 'canApprovePurchaseOrders';
  static const String receivePurchaseOrders = 'canReceivePurchaseOrders';
  static const String cancelPurchaseOrders = 'canCancelPurchaseOrders';

  // Sales Orders
  static const String viewSalesOrders = 'canViewSalesOrders';
  static const String createSalesOrders = 'canCreateSalesOrders';
  static const String editSalesOrders = 'canEditSalesOrders';
  static const String deleteSalesOrders = 'canDeleteSalesOrders';
  static const String confirmSalesOrders = 'canConfirmSalesOrders';
  static const String dispatchSalesOrders = 'canDispatchSalesOrders';
  static const String deliverSalesOrders = 'canDeliverSalesOrders';
  static const String cancelSalesOrders = 'canCancelSalesOrders';

  // Returns
  static const String viewReturns = 'canViewReturns';
  static const String createReturns = 'canCreateReturns';
  static const String approveReturns = 'canApproveReturns';
  static const String rejectReturns = 'canRejectReturns';
  static const String processReturns = 'canProcessReturns';

  // Customers
  static const String viewCustomers = 'canViewCustomers';
  static const String addCustomers = 'canAddCustomers';
  static const String editCustomers = 'canEditCustomers';
  static const String deleteCustomers = 'canDeleteCustomers';

  // Vendors
  static const String viewVendors = 'canViewVendors';
  static const String addVendors = 'canAddVendors';
  static const String editVendors = 'canEditVendors';
  static const String deleteVendors = 'canDeleteVendors';

  // Inventory & Batches
  static const String manageBatches = 'canManageBatches';
  static const String manageStockTakes = 'canManageStockTakes';
  static const String viewExpiryAlerts = 'canViewExpiryAlerts';
  static const String viewReorderSuggestions = 'canViewReorderSuggestions';
  static const String viewStockForecast = 'canViewStockForecast';

  // Billing & Invoices
  static const String viewInvoices = 'canViewInvoices';
  static const String createInvoices = 'canCreateInvoices';
  static const String editInvoices = 'canEditInvoices';
  static const String deleteInvoices = 'canDeleteInvoices';
  static const String recordPayments = 'canRecordPayments';

  // Import / Export
  static const String importData = 'canImport';
  static const String exportData = 'canExport';

  // User Management
  static const String viewUsers = 'canViewUsers';
  static const String manageUsers = 'canManageUsers';
  static const String manageRoles = 'canManageRoles';

  // Settings & Company
  static const String manageCompanySettings = 'canManageCompanySettings';
  static const String manageWarehouseZones = 'canManageWarehouseZones';
  static const String manageNotificationSettings = 'canManageNotificationSettings';

  // ---------------------------------------------------------------------------
  // Full permission definitions list
  // ---------------------------------------------------------------------------
  static const List<PermissionDef> all = [
    // Dashboard & Reports
    PermissionDef(key: viewDashboard, label: 'View Dashboard', description: 'Access the analytics dashboard', group: 'dashboard', icon: Icons.dashboard_rounded),
    PermissionDef(key: viewReports, label: 'View Reports', description: 'Access all report screens', group: 'dashboard', icon: Icons.bar_chart_rounded),
    PermissionDef(key: viewAuditLog, label: 'View Audit Log', description: 'View the audit log history', group: 'dashboard', icon: Icons.history_rounded),
    PermissionDef(key: viewActivityTimeline, label: 'View Activity Timeline', description: 'View the activity timeline', group: 'dashboard', icon: Icons.timeline_rounded),

    // Products & Categories
    PermissionDef(key: viewProducts, label: 'View Products', description: 'View product list and details', group: 'products', icon: Icons.visibility_rounded),
    PermissionDef(key: addProducts, label: 'Add Products', description: 'Create new products', group: 'products', icon: Icons.add_circle_rounded),
    PermissionDef(key: editProducts, label: 'Edit Products', description: 'Modify existing product details', group: 'products', icon: Icons.edit_rounded),
    PermissionDef(key: deleteProducts, label: 'Delete Products', description: 'Remove products from the system', group: 'products', icon: Icons.delete_rounded),
    PermissionDef(key: manageCategories, label: 'Manage Categories', description: 'Create, edit, and delete categories', group: 'products', icon: Icons.category_rounded),

    // Stock Operations
    PermissionDef(key: stockIn, label: 'Stock In', description: 'Add stock to products', group: 'stock', icon: Icons.add_circle_rounded),
    PermissionDef(key: stockOut, label: 'Stock Out', description: 'Remove stock from products', group: 'stock', icon: Icons.remove_circle_rounded),
    PermissionDef(key: damage, label: 'Record Damage', description: 'Record damaged stock', group: 'stock', icon: Icons.broken_image_rounded),
    PermissionDef(key: transfer, label: 'Transfer Stock', description: 'Transfer stock between locations', group: 'stock', icon: Icons.swap_horiz_rounded),
    PermissionDef(key: adjustStock, label: 'Adjust Stock', description: 'Manually adjust stock quantities', group: 'stock', icon: Icons.tune_rounded),
    PermissionDef(key: bulkStockIn, label: 'Bulk Stock In', description: 'Add stock to multiple products at once', group: 'stock', icon: Icons.playlist_add_rounded),
    PermissionDef(key: bulkEdit, label: 'Bulk Edit', description: 'Edit multiple products at once', group: 'stock', icon: Icons.edit_note_rounded),

    // Purchase Orders
    PermissionDef(key: viewPurchaseOrders, label: 'View Purchase Orders', description: 'View purchase order list and details', group: 'purchaseOrders', icon: Icons.visibility_rounded),
    PermissionDef(key: createPurchaseOrders, label: 'Create Purchase Orders', description: 'Create new purchase orders', group: 'purchaseOrders', icon: Icons.add_circle_rounded),
    PermissionDef(key: editPurchaseOrders, label: 'Edit Purchase Orders', description: 'Modify existing purchase orders', group: 'purchaseOrders', icon: Icons.edit_rounded),
    PermissionDef(key: deletePurchaseOrders, label: 'Delete Purchase Orders', description: 'Remove purchase orders', group: 'purchaseOrders', icon: Icons.delete_rounded),
    PermissionDef(key: approvePurchaseOrders, label: 'Approve Purchase Orders', description: 'Approve and send purchase orders to vendors', group: 'purchaseOrders', icon: Icons.check_circle_rounded),
    PermissionDef(key: receivePurchaseOrders, label: 'Receive Purchase Orders', description: 'Mark items as received on purchase orders', group: 'purchaseOrders', icon: Icons.move_to_inbox_rounded),
    PermissionDef(key: cancelPurchaseOrders, label: 'Cancel Purchase Orders', description: 'Cancel purchase orders', group: 'purchaseOrders', icon: Icons.cancel_rounded),

    // Sales Orders
    PermissionDef(key: viewSalesOrders, label: 'View Sales Orders', description: 'View sales order list and details', group: 'salesOrders', icon: Icons.visibility_rounded),
    PermissionDef(key: createSalesOrders, label: 'Create Sales Orders', description: 'Create new sales orders', group: 'salesOrders', icon: Icons.add_circle_rounded),
    PermissionDef(key: editSalesOrders, label: 'Edit Sales Orders', description: 'Modify existing sales orders', group: 'salesOrders', icon: Icons.edit_rounded),
    PermissionDef(key: deleteSalesOrders, label: 'Delete Sales Orders', description: 'Remove sales orders', group: 'salesOrders', icon: Icons.delete_rounded),
    PermissionDef(key: confirmSalesOrders, label: 'Confirm Sales Orders', description: 'Confirm and approve sales orders', group: 'salesOrders', icon: Icons.check_circle_rounded),
    PermissionDef(key: dispatchSalesOrders, label: 'Dispatch Sales Orders', description: 'Mark sales orders as dispatched', group: 'salesOrders', icon: Icons.local_shipping_rounded),
    PermissionDef(key: deliverSalesOrders, label: 'Deliver Sales Orders', description: 'Mark sales orders as delivered', group: 'salesOrders', icon: Icons.done_all_rounded),
    PermissionDef(key: cancelSalesOrders, label: 'Cancel Sales Orders', description: 'Cancel sales orders', group: 'salesOrders', icon: Icons.cancel_rounded),

    // Returns
    PermissionDef(key: viewReturns, label: 'View Returns', description: 'View returns list and details', group: 'returns', icon: Icons.visibility_rounded),
    PermissionDef(key: createReturns, label: 'Create Returns', description: 'Create new return requests', group: 'returns', icon: Icons.add_circle_rounded),
    PermissionDef(key: approveReturns, label: 'Approve Returns', description: 'Approve return requests', group: 'returns', icon: Icons.check_circle_rounded),
    PermissionDef(key: rejectReturns, label: 'Reject Returns', description: 'Reject return requests', group: 'returns', icon: Icons.cancel_rounded),
    PermissionDef(key: processReturns, label: 'Process Returns', description: 'Process approved returns (adjust stock)', group: 'returns', icon: Icons.published_with_changes_rounded),

    // Customers
    PermissionDef(key: viewCustomers, label: 'View Customers', description: 'View customer list and details', group: 'customers', icon: Icons.visibility_rounded),
    PermissionDef(key: addCustomers, label: 'Add Customers', description: 'Create new customers', group: 'customers', icon: Icons.person_add_rounded),
    PermissionDef(key: editCustomers, label: 'Edit Customers', description: 'Modify existing customer details', group: 'customers', icon: Icons.edit_rounded),
    PermissionDef(key: deleteCustomers, label: 'Delete Customers', description: 'Remove customers', group: 'customers', icon: Icons.person_remove_rounded),

    // Vendors
    PermissionDef(key: viewVendors, label: 'View Vendors', description: 'View vendor list and details', group: 'vendors', icon: Icons.visibility_rounded),
    PermissionDef(key: addVendors, label: 'Add Vendors', description: 'Create new vendors', group: 'vendors', icon: Icons.add_business_rounded),
    PermissionDef(key: editVendors, label: 'Edit Vendors', description: 'Modify existing vendor details', group: 'vendors', icon: Icons.edit_rounded),
    PermissionDef(key: deleteVendors, label: 'Delete Vendors', description: 'Remove vendors', group: 'vendors', icon: Icons.delete_rounded),

    // Inventory & Batches
    PermissionDef(key: manageBatches, label: 'Manage Batches', description: 'Create and manage product batches', group: 'inventory', icon: Icons.layers_rounded),
    PermissionDef(key: manageStockTakes, label: 'Manage Stock Takes', description: 'Create and conduct stock takes', group: 'inventory', icon: Icons.fact_check_rounded),
    PermissionDef(key: viewExpiryAlerts, label: 'View Expiry Alerts', description: 'View batch expiry notifications', group: 'inventory', icon: Icons.timer_rounded),
    PermissionDef(key: viewReorderSuggestions, label: 'View Reorder Suggestions', description: 'View reorder point alerts', group: 'inventory', icon: Icons.shopping_cart_checkout_rounded),
    PermissionDef(key: viewStockForecast, label: 'View Stock Forecast', description: 'View stock demand forecasts', group: 'inventory', icon: Icons.trending_up_rounded),

    // Billing & Invoices
    PermissionDef(key: viewInvoices, label: 'View Invoices', description: 'View invoice list and details', group: 'billing', icon: Icons.visibility_rounded),
    PermissionDef(key: createInvoices, label: 'Create Invoices', description: 'Create new invoices', group: 'billing', icon: Icons.add_circle_rounded),
    PermissionDef(key: editInvoices, label: 'Edit Invoices', description: 'Modify existing invoices', group: 'billing', icon: Icons.edit_rounded),
    PermissionDef(key: deleteInvoices, label: 'Delete Invoices', description: 'Remove invoices', group: 'billing', icon: Icons.delete_rounded),
    PermissionDef(key: recordPayments, label: 'Record Payments', description: 'Record payments on invoices', group: 'billing', icon: Icons.payments_rounded),

    // Import / Export
    PermissionDef(key: importData, label: 'Import Data', description: 'Import data from Excel files', group: 'importExport', icon: Icons.upload_file_rounded),
    PermissionDef(key: exportData, label: 'Export Data', description: 'Export data to Excel files', group: 'importExport', icon: Icons.download_rounded),

    // User Management
    PermissionDef(key: viewUsers, label: 'View Users', description: 'View user list', group: 'users', icon: Icons.people_rounded),
    PermissionDef(key: manageUsers, label: 'Manage Users', description: 'Add, edit roles, and remove users', group: 'users', icon: Icons.manage_accounts_rounded),
    PermissionDef(key: manageRoles, label: 'Manage Roles', description: 'Create, edit, and delete roles', group: 'users', icon: Icons.admin_panel_settings_rounded),

    // Settings & Company
    PermissionDef(key: manageCompanySettings, label: 'Manage Company Settings', description: 'Edit company settings and preferences', group: 'settings', icon: Icons.business_rounded),
    PermissionDef(key: manageWarehouseZones, label: 'Manage Warehouse Zones', description: 'Create and manage warehouse zones', group: 'settings', icon: Icons.warehouse_rounded),
    PermissionDef(key: manageNotificationSettings, label: 'Manage Notifications', description: 'Configure notification preferences', group: 'settings', icon: Icons.notifications_rounded),
  ];

  static List<String> get allKeys => all.map((p) => p.key).toList();

  static List<PermissionDef> byGroup(String groupId) =>
      all.where((p) => p.group == groupId).toList();

  static PermissionDef? byKey(String key) {
    final idx = all.indexWhere((p) => p.key == key);
    return idx == -1 ? null : all[idx];
  }

  static String labelFor(String key) => byKey(key)?.label ?? key;

  static Map<String, bool> allTrue() =>
      {for (final p in all) p.key: true};

  static Map<String, bool> allFalse() =>
      {for (final p in all) p.key: false};

  /// Backward-compatibility mapping from old permission keys to new ones.
  /// Used during migration of existing user documents.
  static const Map<String, List<String>> legacyKeyMapping = {
    'canManageProducts': ['canAddProducts', 'canEditProducts', 'canDeleteProducts'],
    'canManagePurchaseOrders': [
      'canViewPurchaseOrders', 'canCreatePurchaseOrders', 'canEditPurchaseOrders',
      'canDeletePurchaseOrders', 'canApprovePurchaseOrders', 'canReceivePurchaseOrders',
      'canCancelPurchaseOrders',
    ],
    'canManageSalesOrders': [
      'canViewSalesOrders', 'canCreateSalesOrders', 'canEditSalesOrders',
      'canDeleteSalesOrders', 'canConfirmSalesOrders', 'canDispatchSalesOrders',
      'canDeliverSalesOrders', 'canCancelSalesOrders',
    ],
    'canManageReturns': [
      'canViewReturns', 'canCreateReturns', 'canApproveReturns',
      'canRejectReturns', 'canProcessReturns',
    ],
    'canManageCustomers': [
      'canViewCustomers', 'canAddCustomers', 'canEditCustomers', 'canDeleteCustomers',
    ],
  };

  /// Expand a legacy permissions map to the new granular keys.
  static Map<String, bool> migrateLegacyPermissions(Map<String, bool> old) {
    final result = <String, bool>{};
    for (final entry in old.entries) {
      final expanded = legacyKeyMapping[entry.key];
      if (expanded != null) {
        for (final k in expanded) {
          result[k] = entry.value;
        }
      }
      if (allKeys.contains(entry.key)) {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }
}
