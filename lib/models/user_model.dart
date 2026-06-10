import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/permissions.dart';
import '../utils/parse_helpers.dart';

class CompanyMembership {
  final String companyId;
  final String companyName;
  final String role;
  final String roleId;

  const CompanyMembership({
    required this.companyId,
    required this.companyName,
    required this.role,
    this.roleId = '',
  });

  factory CompanyMembership.fromMap(Map<String, dynamic> map) {
    return CompanyMembership(
      companyId: safeString(map['companyId']),
      companyName: safeString(map['companyName']),
      role: safeString(map['role'], 'staff'),
      roleId: safeString(map['roleId']),
    );
  }

  Map<String, dynamic> toMap() => {
    'companyId': companyId,
    'companyName': companyName,
    'role': role,
    'roleId': roleId,
  };

  bool get isAdmin => role == 'admin' || role == 'owner';
}

class UserModel {
  final String uid;
  final String name;
  final String email;
  final String role;
  final String roleId;
  final String companyId;
  final String companyName;
  final String phone;
  final DateTime createdAt;
  final Map<String, bool> permissions;
  final List<CompanyMembership> companyMemberships;

  /// Resolved permissions from the role + per-user overrides.
  /// Set externally by AuthProvider after loading the role.
  Map<String, bool>? _resolvedPermissions;

  set resolvedPermissions(Map<String, bool>? value) =>
      _resolvedPermissions = value;

  // Legacy keys kept for backward compatibility during migration
  static const List<String> allPermissionKeys = [
    'canStockIn',
    'canStockOut',
    'canDamage',
    'canTransfer',
    'canAdjustStock',
    'canHoldStock',
    'canReleaseStock',
    'canViewStockHolds',
    'canViewProducts',
    'canManageProducts',
    'canManageCategories',
    'canViewReports',
    'canImport',
    'canExport',
    'canManagePurchaseOrders',
    'canManageSalesOrders',
    'canManageReturns',
    'canManageCustomers',
    'canViewAuditLog',
    'canManageBatches',
  ];

  static const Map<String, String> permissionLabels = {
    'canStockIn': 'Stock In',
    'canStockOut': 'Stock Out',
    'canDamage': 'Record Damage',
    'canTransfer': 'Transfer Stock',
    'canAdjustStock': 'Adjust Stock (Admin)',
    'canHoldStock': 'Hold Stock',
    'canReleaseStock': 'Release Held Stock',
    'canViewStockHolds': 'View Stock Holds',
    'canViewProducts': 'View Products',
    'canManageProducts': 'Add / Edit Products',
    'canManageCategories': 'Manage Categories',
    'canViewReports': 'View Reports',
    'canImport': 'Import Data',
    'canExport': 'Export Data',
    'canManagePurchaseOrders': 'Manage Purchase Orders',
    'canManageSalesOrders': 'Manage Sales Orders',
    'canManageReturns': 'Manage Returns',
    'canManageCustomers': 'Manage Customers',
    'canViewAuditLog': 'View Audit Log',
    'canManageBatches': 'Manage Batches',
  };

  static const Set<String> adminOnlyKeys = {'canAdjustStock'};

  static Map<String, bool> get defaultPermissions => {
    for (final k in allPermissionKeys) k: !adminOnlyKeys.contains(k),
  };

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.roleId = '',
    required this.companyId,
    this.companyName = '',
    this.phone = '',
    required this.createdAt,
    Map<String, bool>? permissions,
    List<CompanyMembership>? companyMemberships,
  }) : permissions = permissions ?? defaultPermissions,
       companyMemberships = companyMemberships ?? const [];

  bool get isAdmin => role == 'admin' || role == 'owner';
  bool get isStaff => role == 'staff';
  bool get isOwner => role == 'owner';

  Map<String, bool> get effectivePermissions {
    if (isAdmin) return AppPermissions.allTrue();
    if (_resolvedPermissions != null) return _resolvedPermissions!;
    return {...defaultPermissions, ...permissions};
  }

  bool hasPermission(String key) => effectivePermissions[key] ?? false;

  bool hasAnyPermission(List<String> keys) => keys.any((k) => hasPermission(k));

  bool hasAllPermissions(List<String> keys) =>
      keys.every((k) => hasPermission(k));

  String get roleName {
    if (roleId.isEmpty) {
      return isAdmin ? 'Admin' : 'Staff';
    }
    return role;
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    Map<String, bool> perms = UserModel.defaultPermissions;
    if (map['permissions'] != null && map['permissions'] is Map) {
      final raw = map['permissions'] as Map;
      perms = raw.map((k, v) => MapEntry(safeString(k), safeBool(v)));
    }

    List<CompanyMembership> memberships = [];
    if (map['companyMemberships'] != null &&
        map['companyMemberships'] is List) {
      memberships = (map['companyMemberships'] as List)
          .where((e) => e is Map)
          .map(
            (e) =>
                CompanyMembership.fromMap(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    }

    if (memberships.isEmpty && safeString(map['companyId']).isNotEmpty) {
      memberships = [
        CompanyMembership(
          companyId: safeString(map['companyId']),
          companyName: safeString(map['companyName']),
          role: safeString(map['role'], 'admin'),
          roleId: safeString(map['roleId']),
        ),
      ];
    }

    return UserModel(
      uid: safeString(map['uid']),
      name: safeString(map['name']),
      email: safeString(map['email']),
      role: safeString(map['role'], 'staff'),
      roleId: safeString(map['roleId']),
      companyId: safeString(map['companyId']),
      companyName: safeString(map['companyName']),
      phone: safeString(map['phone']),
      createdAt: safeTimestamp(map['createdAt']),
      permissions: perms,
      companyMemberships: memberships,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'role': role,
      'roleId': roleId,
      'companyId': companyId,
      'companyName': companyName,
      'phone': phone,
      'createdAt': Timestamp.fromDate(createdAt),
      'permissions': permissions,
      'companyMemberships': companyMemberships.map((m) => m.toMap()).toList(),
    };
  }

  UserModel copyWith({
    String? uid,
    String? name,
    String? email,
    String? role,
    String? roleId,
    String? companyId,
    String? companyName,
    String? phone,
    DateTime? createdAt,
    Map<String, bool>? permissions,
    List<CompanyMembership>? companyMemberships,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      roleId: roleId ?? this.roleId,
      companyId: companyId ?? this.companyId,
      companyName: companyName ?? this.companyName,
      phone: phone ?? this.phone,
      createdAt: createdAt ?? this.createdAt,
      permissions: permissions ?? this.permissions,
      companyMemberships: companyMemberships ?? this.companyMemberships,
    );
  }
}
