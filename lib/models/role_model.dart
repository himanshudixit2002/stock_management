import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/permissions.dart';
import '../utils/parse_helpers.dart';

class RoleModel {
  final String id;
  final String name;
  final String description;
  final Map<String, bool> permissions;
  final bool isSystem;
  final String companyId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RoleModel({
    required this.id,
    required this.name,
    this.description = '',
    required this.permissions,
    this.isSystem = false,
    required this.companyId,
    required this.createdAt,
    required this.updatedAt,
  });

  bool hasPermission(String key) => permissions[key] ?? false;

  int get enabledCount => permissions.values.where((v) => v).length;
  int get totalCount => AppPermissions.all.length;

  factory RoleModel.fromMap(Map<String, dynamic> map, {required String id}) {
    Map<String, bool> perms = AppPermissions.allFalse();
    if (map['permissions'] is Map) {
      final raw = map['permissions'] as Map;
      for (final entry in raw.entries) {
        perms[safeString(entry.key)] = safeBool(entry.value);
      }
    }

    return RoleModel(
      id: id,
      name: safeString(map['name']),
      description: safeString(map['description']),
      permissions: perms,
      isSystem: safeBool(map['isSystem']),
      companyId: safeString(map['companyId']),
      createdAt: safeTimestamp(map['createdAt']),
      updatedAt: safeTimestamp(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'description': description,
        'permissions': permissions,
        'isSystem': isSystem,
        'companyId': companyId,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  RoleModel copyWith({
    String? id,
    String? name,
    String? description,
    Map<String, bool>? permissions,
    bool? isSystem,
    String? companyId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RoleModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      permissions: permissions ?? this.permissions,
      isSystem: isSystem ?? this.isSystem,
      companyId: companyId ?? this.companyId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // ---------------------------------------------------------------------------
  // System role IDs (well-known, used for seeding and migration)
  // ---------------------------------------------------------------------------
  static const String ownerRoleId = 'owner';
  static const String adminRoleId = 'admin';
  static const String managerRoleId = 'manager';
  static const String staffRoleId = 'staff';
  static const String viewerRoleId = 'viewer';

  /// Maps a roles collection document id to the user document `role` field.
  static String userRoleFieldForRoleId(String roleId) {
    switch (roleId) {
      case ownerRoleId:
      case adminRoleId:
        return 'admin';
      case managerRoleId:
        return 'manager';
      case viewerRoleId:
        return 'viewer';
      case staffRoleId:
        return 'staff';
      default:
        return 'staff';
    }
  }

  static List<RoleModel> defaultRoles(String companyId) {
    final now = DateTime.now();
    return [
      RoleModel(
        id: ownerRoleId,
        name: 'Owner',
        description: 'Full access to everything. Cannot be edited or deleted.',
        permissions: AppPermissions.allTrue(),
        isSystem: true,
        companyId: companyId,
        createdAt: now,
        updatedAt: now,
      ),
      RoleModel(
        id: adminRoleId,
        name: 'Admin',
        description: 'Full access except company deletion. Can manage users and roles.',
        permissions: AppPermissions.allTrue(),
        isSystem: true,
        companyId: companyId,
        createdAt: now,
        updatedAt: now,
      ),
      RoleModel(
        id: managerRoleId,
        name: 'Manager',
        description: 'Can approve orders and returns, manage products and stock, view reports.',
        permissions: {
          ...AppPermissions.allFalse(),
          // Dashboard & Reports
          AppPermissions.viewDashboard: true,
          AppPermissions.viewReports: true,
          AppPermissions.viewAuditLog: true,
          AppPermissions.viewActivityTimeline: true,
          // Products & Categories
          AppPermissions.viewProducts: true,
          AppPermissions.addProducts: true,
          AppPermissions.editProducts: true,
          AppPermissions.deleteProducts: true,
          AppPermissions.manageCategories: true,
          // Stock Operations
          AppPermissions.stockIn: true,
          AppPermissions.stockOut: true,
          AppPermissions.damage: true,
          AppPermissions.transfer: true,
          AppPermissions.adjustStock: true,
          AppPermissions.bulkStockIn: true,
          AppPermissions.bulkEdit: true,
          // Purchase Orders (full)
          AppPermissions.viewPurchaseOrders: true,
          AppPermissions.createPurchaseOrders: true,
          AppPermissions.editPurchaseOrders: true,
          AppPermissions.deletePurchaseOrders: true,
          AppPermissions.approvePurchaseOrders: true,
          AppPermissions.receivePurchaseOrders: true,
          AppPermissions.cancelPurchaseOrders: true,
          // Sales Orders (full)
          AppPermissions.viewSalesOrders: true,
          AppPermissions.createSalesOrders: true,
          AppPermissions.editSalesOrders: true,
          AppPermissions.deleteSalesOrders: true,
          AppPermissions.confirmSalesOrders: true,
          AppPermissions.dispatchSalesOrders: true,
          AppPermissions.deliverSalesOrders: true,
          AppPermissions.cancelSalesOrders: true,
          // Returns (full)
          AppPermissions.viewReturns: true,
          AppPermissions.createReturns: true,
          AppPermissions.approveReturns: true,
          AppPermissions.rejectReturns: true,
          AppPermissions.processReturns: true,
          // Customers
          AppPermissions.viewCustomers: true,
          AppPermissions.addCustomers: true,
          AppPermissions.editCustomers: true,
          AppPermissions.deleteCustomers: true,
          // Vendors
          AppPermissions.viewVendors: true,
          AppPermissions.addVendors: true,
          AppPermissions.editVendors: true,
          AppPermissions.deleteVendors: true,
          // Inventory
          AppPermissions.manageBatches: true,
          AppPermissions.manageStockTakes: true,
          AppPermissions.viewExpiryAlerts: true,
          AppPermissions.viewReorderSuggestions: true,
          AppPermissions.viewStockForecast: true,
          // Billing
          AppPermissions.viewInvoices: true,
          AppPermissions.createInvoices: true,
          AppPermissions.editInvoices: true,
          AppPermissions.deleteInvoices: true,
          AppPermissions.recordPayments: true,
          // Import / Export
          AppPermissions.importData: true,
          AppPermissions.exportData: true,
          // No user management or settings
        },
        isSystem: true,
        companyId: companyId,
        createdAt: now,
        updatedAt: now,
      ),
      RoleModel(
        id: staffRoleId,
        name: 'Staff',
        description: 'Basic stock operations and product viewing. No approvals or management.',
        permissions: {
          ...AppPermissions.allFalse(),
          AppPermissions.viewDashboard: true,
          AppPermissions.viewProducts: true,
          AppPermissions.stockIn: true,
          AppPermissions.stockOut: true,
          AppPermissions.damage: true,
          AppPermissions.transfer: true,
          AppPermissions.viewPurchaseOrders: true,
          AppPermissions.viewSalesOrders: true,
          AppPermissions.viewReturns: true,
          AppPermissions.viewCustomers: true,
          AppPermissions.viewVendors: true,
          AppPermissions.viewExpiryAlerts: true,
          AppPermissions.viewInvoices: true,
          AppPermissions.exportData: true,
        },
        isSystem: true,
        companyId: companyId,
        createdAt: now,
        updatedAt: now,
      ),
      RoleModel(
        id: viewerRoleId,
        name: 'Viewer',
        description: 'Read-only access to products, reports, and dashboards.',
        permissions: {
          ...AppPermissions.allFalse(),
          AppPermissions.viewDashboard: true,
          AppPermissions.viewReports: true,
          AppPermissions.viewProducts: true,
          AppPermissions.viewPurchaseOrders: true,
          AppPermissions.viewSalesOrders: true,
          AppPermissions.viewReturns: true,
          AppPermissions.viewCustomers: true,
          AppPermissions.viewVendors: true,
          AppPermissions.viewInvoices: true,
          AppPermissions.viewExpiryAlerts: true,
          AppPermissions.viewReorderSuggestions: true,
          AppPermissions.viewStockForecast: true,
          AppPermissions.viewActivityTimeline: true,
        },
        isSystem: true,
        companyId: companyId,
        createdAt: now,
        updatedAt: now,
      ),
    ];
  }
}
