import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

class UserModel {
  final String uid;
  final String name;
  final String email;
  final String role; // 'admin' or 'staff'
  final String companyId;
  final String companyName;
  final String phone;
  final DateTime createdAt;
  final Map<String, bool> permissions;

  static const List<String> allPermissionKeys = [
    'canStockIn',
    'canStockOut',
    'canDamage',
    'canTransfer',
    'canAdjustStock',
    'canViewProducts',
    'canManageProducts',
    'canManageCategories',
    'canViewReports',
    'canImport',
    'canExport',
  ];

  static const Map<String, String> permissionLabels = {
    'canStockIn': 'Stock In',
    'canStockOut': 'Stock Out',
    'canDamage': 'Record Damage',
    'canTransfer': 'Transfer Stock',
    'canAdjustStock': 'Adjust Stock (Admin)',
    'canViewProducts': 'View Products',
    'canManageProducts': 'Add / Edit Products',
    'canManageCategories': 'Manage Categories',
    'canViewReports': 'View Reports',
    'canImport': 'Import Data',
    'canExport': 'Export Data',
  };

  /// Admin-only permission keys — staff get `false` by default.
  static const Set<String> adminOnlyKeys = {'canAdjustStock'};

  static Map<String, bool> get defaultPermissions => {
    for (final k in allPermissionKeys) k: !adminOnlyKeys.contains(k),
  };

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.companyId,
    this.companyName = '',
    this.phone = '',
    required this.createdAt,
    Map<String, bool>? permissions,
  }) : permissions = permissions ?? defaultPermissions;

  bool get isAdmin => role == 'admin';
  bool get isStaff => role == 'staff';

  /// All permissions set to `true` — used for admin.
  static Map<String, bool> get _allPermissions => {
    for (final k in allPermissionKeys) k: true,
  };

  Map<String, bool> get effectivePermissions {
    if (isAdmin) return _allPermissions;
    return {...defaultPermissions, ...permissions};
  }

  bool hasPermission(String key) => effectivePermissions[key] ?? false;

  factory UserModel.fromMap(Map<String, dynamic> map) {
    Map<String, bool> perms = UserModel.defaultPermissions;
    if (map['permissions'] != null && map['permissions'] is Map) {
      final raw = map['permissions'] as Map;
      perms = raw.map((k, v) => MapEntry(safeString(k), safeBool(v)));
    }

    return UserModel(
      uid: safeString(map['uid']),
      name: safeString(map['name']),
      email: safeString(map['email']),
      role: safeString(map['role'], 'staff'),
      companyId: safeString(map['companyId']),
      companyName: safeString(map['companyName']),
      phone: safeString(map['phone']),
      createdAt: safeTimestamp(map['createdAt']),
      permissions: perms,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'role': role,
      'companyId': companyId,
      'companyName': companyName,
      'phone': phone,
      'createdAt': Timestamp.fromDate(createdAt),
      'permissions': permissions,
    };
  }

  UserModel copyWith({
    String? uid,
    String? name,
    String? email,
    String? role,
    String? companyId,
    String? companyName,
    String? phone,
    DateTime? createdAt,
    Map<String, bool>? permissions,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      companyId: companyId ?? this.companyId,
      companyName: companyName ?? this.companyName,
      phone: phone ?? this.phone,
      createdAt: createdAt ?? this.createdAt,
      permissions: permissions ?? this.permissions,
    );
  }
}
