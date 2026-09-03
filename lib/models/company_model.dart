import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';
import 'company_plan_model.dart';

/// Operational state of a workspace.
///
/// `suspended` stops writes (enforced by companyActive() in firestore.rules)
/// while leaving the tenant's own data readable, so they can still see their
/// books and the reason. `deleted` is a soft delete: reversible, and separate
/// from the irreversible purge.
enum CompanyStatus { active, suspended, deleted }

/// A company (workspace).
///
/// Company docs were read as bare maps everywhere before this existed, so every
/// field must tolerate being absent — the 14 companies in production predate
/// both `status` and `plan`.
class CompanyModel {
  final String id;
  final String companyName;
  final String adminUid;
  final String permanentJoinCode;
  final CompanyStatus status;
  final CompanyPlan plan;
  final DateTime? createdAt;

  /// Why the company was suspended or deleted, shown to the tenant.
  final String statusNote;
  final DateTime? statusChangedAt;

  const CompanyModel({
    required this.id,
    this.companyName = '',
    this.adminUid = '',
    this.permanentJoinCode = '',
    this.status = CompanyStatus.active,
    this.plan = const CompanyPlan(),
    this.createdAt,
    this.statusNote = '',
    this.statusChangedAt,
  });

  bool get isActive => status == CompanyStatus.active;
  bool get isSuspended => status == CompanyStatus.suspended;
  bool get isDeleted => status == CompanyStatus.deleted;

  /// True when the workspace should be usable by its members.
  bool get isUsable => status == CompanyStatus.active;

  String get displayName =>
      companyName.trim().isNotEmpty ? companyName.trim() : 'Unnamed workspace';

  String get statusLabel => switch (status) {
    CompanyStatus.active => 'Active',
    CompanyStatus.suspended => 'Suspended',
    CompanyStatus.deleted => 'Deleted',
  };

  /// Absent status means active: that is how every pre-existing company doc
  /// reads, and treating it as anything else would lock all of them out.
  static CompanyStatus _statusFromString(String s) => switch (s) {
    'suspended' => CompanyStatus.suspended,
    'deleted' => CompanyStatus.deleted,
    _ => CompanyStatus.active,
  };

  static String statusToString(CompanyStatus s) => switch (s) {
    CompanyStatus.active => 'active',
    CompanyStatus.suspended => 'suspended',
    CompanyStatus.deleted => 'deleted',
  };

  factory CompanyModel.fromMap(Map<String, dynamic> map, String docId) {
    return CompanyModel(
      id: docId,
      companyName: safeString(map['companyName']),
      adminUid: safeString(map['adminUid']),
      permanentJoinCode: safeString(map['permanentJoinCode']),
      status: _statusFromString(safeString(map['status'], 'active')),
      plan: CompanyPlan.fromMap(
        map['plan'] is Map
            ? Map<String, dynamic>.from(map['plan'] as Map)
            : null,
      ),
      createdAt: map['createdAt'] == null
          ? null
          : safeTimestamp(map['createdAt']),
      statusNote: safeString(map['statusNote']),
      statusChangedAt: map['statusChangedAt'] == null
          ? null
          : safeTimestamp(map['statusChangedAt']),
    );
  }

  /// Only the fields this app owns. Company docs carry a `settings` map written
  /// elsewhere (SettingsProvider, BillingSettingsProvider), so writes must
  /// always be merges or targeted field updates — never a whole-document set,
  /// which would drop those.
  Map<String, dynamic> toMap() => {
    'companyName': companyName,
    'adminUid': adminUid,
    'permanentJoinCode': permanentJoinCode,
    'status': statusToString(status),
    'plan': plan.toMap(),
    if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
    'statusNote': statusNote,
    if (statusChangedAt != null)
      'statusChangedAt': Timestamp.fromDate(statusChangedAt!),
  };

  CompanyModel copyWith({
    String? id,
    String? companyName,
    String? adminUid,
    String? permanentJoinCode,
    CompanyStatus? status,
    CompanyPlan? plan,
    DateTime? createdAt,
    String? statusNote,
    DateTime? statusChangedAt,
  }) {
    return CompanyModel(
      id: id ?? this.id,
      companyName: companyName ?? this.companyName,
      adminUid: adminUid ?? this.adminUid,
      permanentJoinCode: permanentJoinCode ?? this.permanentJoinCode,
      status: status ?? this.status,
      plan: plan ?? this.plan,
      createdAt: createdAt ?? this.createdAt,
      statusNote: statusNote ?? this.statusNote,
      statusChangedAt: statusChangedAt ?? this.statusChangedAt,
    );
  }
}

/// Counts for one company, shown on the super admin dashboard.
///
/// Gathered with Firestore count() aggregations, so this never downloads a
/// tenant's documents.
class CompanyStats {
  final int users;
  final int products;
  final int invoices;
  final int salesOrders;
  final int purchaseOrders;
  final int transactions;
  final int customers;
  final int vendors;
  final int batches;
  final int returns;
  final int categories;
  final int roles;

  /// True when the user count could not be read at all, as opposed to being
  /// genuinely zero.
  ///
  /// Users are the one figure that comes from a root collection rather than a
  /// company subcollection, so it is the one a rules gap can deny on its own.
  /// Reporting a denied count as 0 is what let a missing rule look like an
  /// empty workspace; the UI shows "—" instead when this is set.
  final bool usersUnknown;

  const CompanyStats({
    this.users = 0,
    this.usersUnknown = false,
    this.products = 0,
    this.invoices = 0,
    this.salesOrders = 0,
    this.purchaseOrders = 0,
    this.transactions = 0,
    this.customers = 0,
    this.vendors = 0,
    this.batches = 0,
    this.returns = 0,
    this.categories = 0,
    this.roles = 0,
  });

  static const CompanyStats empty = CompanyStats();
}
