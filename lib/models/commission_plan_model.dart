import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

/// What a commission is a percentage *of*.
///
/// Revenue is what most schemes say and margin is what most of them mean: on a
/// discount-heavy sale a revenue commission can exceed the profit on the deal.
enum CommissionBasis { revenue, margin }

/// A rate that applies to one product category, overriding the plan default.
class CommissionRate {
  final String categoryId;
  final String categoryName;
  final double percent;

  const CommissionRate({
    required this.categoryId,
    this.categoryName = '',
    this.percent = 0,
  });

  factory CommissionRate.fromMap(Map<String, dynamic> map) => CommissionRate(
    categoryId: safeString(map['categoryId']),
    categoryName: safeString(map['categoryName']),
    percent: safeDouble(map['percent']),
  );

  Map<String, dynamic> toMap() => {
    'categoryId': categoryId,
    'categoryName': categoryName,
    'percent': percent,
  };

  CommissionRate copyWith({
    String? categoryId,
    String? categoryName,
    double? percent,
  }) => CommissionRate(
    categoryId: categoryId ?? this.categoryId,
    categoryName: categoryName ?? this.categoryName,
    percent: percent ?? this.percent,
  );
}

/// A commission scheme, and who it applies to.
class CommissionPlanModel {
  final String id;
  final String name;
  final CommissionBasis basis;

  /// The rate used when no category override matches.
  final double defaultPercent;

  final List<CommissionRate> categoryRates;

  /// Users this plan applies to, by uid. Empty means everybody — which is the
  /// common case for a single scheme, and saves maintaining the list as staff
  /// change.
  final List<String> userIds;

  /// When false (the default) an invoice contributes only what has actually
  /// been paid on it. Paying commission on money not yet collected is the
  /// classic way a commission scheme costs more than the sales it rewarded.
  final bool includeUnpaid;

  /// Sales below this value earn nothing, for schemes with a floor.
  final double minimumSaleValue;

  final bool isActive;
  final DateTime? effectiveFrom;
  final DateTime? effectiveTo;
  final String notes;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;

  CommissionPlanModel({
    required this.id,
    required this.name,
    this.basis = CommissionBasis.revenue,
    this.defaultPercent = 0,
    this.categoryRates = const [],
    this.userIds = const [],
    this.includeUnpaid = false,
    this.minimumSaleValue = 0,
    this.isActive = true,
    this.effectiveFrom,
    this.effectiveTo,
    this.notes = '',
    this.createdBy = '',
    this.createdByName = '',
    required this.createdAt,
    required this.updatedAt,
  });

  bool get appliesToEveryone => userIds.isEmpty;

  bool appliesTo(String userId) =>
      isActive && (userIds.isEmpty || userIds.contains(userId));

  /// True when [date] falls inside the plan's effective window.
  bool coversDate(DateTime date) {
    final from = effectiveFrom;
    final to = effectiveTo;
    if (from != null && date.isBefore(from)) return false;
    if (to != null && date.isAfter(to)) return false;
    return true;
  }

  /// The rate for a category: its override when there is one, else the default.
  double percentFor(String categoryId) {
    for (final rate in categoryRates) {
      if (rate.categoryId == categoryId) return rate.percent;
    }
    return defaultPercent;
  }

  String get basisLabel => basisLabelOf(basis);

  static String basisLabelOf(CommissionBasis b) => switch (b) {
    CommissionBasis.revenue => 'Revenue',
    CommissionBasis.margin => 'Gross margin',
  };

  static CommissionBasis basisFromString(String s) =>
      s == 'margin' ? CommissionBasis.margin : CommissionBasis.revenue;

  static String basisToString(CommissionBasis b) => b.name;

  factory CommissionPlanModel.fromMap(
    Map<String, dynamic> map,
    String docId,
  ) {
    final rawRates = map['categoryRates'];
    final rawUsers = map['userIds'];
    return CommissionPlanModel(
      id: docId,
      name: safeString(map['name']),
      basis: basisFromString(safeString(map['basis'], 'revenue')),
      defaultPercent: safeDouble(map['defaultPercent']),
      categoryRates: rawRates is List
          ? rawRates
                .whereType<Map>()
                .map(
                  (e) => CommissionRate.fromMap(Map<String, dynamic>.from(e)),
                )
                .toList()
          : const [],
      userIds: rawUsers is List
          ? rawUsers.map((e) => safeString(e)).where((e) => e.isNotEmpty).toList()
          : const [],
      includeUnpaid: safeBool(map['includeUnpaid']),
      minimumSaleValue: safeDouble(map['minimumSaleValue']),
      isActive: safeBool(map['isActive'], true),
      effectiveFrom: map['effectiveFrom'] == null
          ? null
          : safeTimestamp(map['effectiveFrom']),
      effectiveTo: map['effectiveTo'] == null
          ? null
          : safeTimestamp(map['effectiveTo']),
      notes: safeString(map['notes']),
      createdBy: safeString(map['createdBy']),
      createdByName: safeString(map['createdByName']),
      createdAt: safeTimestamp(map['createdAt']),
      updatedAt: safeTimestamp(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'basis': basisToString(basis),
    'defaultPercent': defaultPercent,
    'categoryRates': categoryRates.map((r) => r.toMap()).toList(),
    'userIds': userIds,
    'includeUnpaid': includeUnpaid,
    'minimumSaleValue': minimumSaleValue,
    'isActive': isActive,
    if (effectiveFrom != null)
      'effectiveFrom': Timestamp.fromDate(effectiveFrom!),
    if (effectiveTo != null) 'effectiveTo': Timestamp.fromDate(effectiveTo!),
    'notes': notes,
    'createdBy': createdBy,
    'createdByName': createdByName,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  CommissionPlanModel copyWith({
    String? id,
    String? name,
    CommissionBasis? basis,
    double? defaultPercent,
    List<CommissionRate>? categoryRates,
    List<String>? userIds,
    bool? includeUnpaid,
    double? minimumSaleValue,
    bool? isActive,
    DateTime? effectiveFrom,
    DateTime? effectiveTo,
    String? notes,
    String? createdBy,
    String? createdByName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => CommissionPlanModel(
    id: id ?? this.id,
    name: name ?? this.name,
    basis: basis ?? this.basis,
    defaultPercent: defaultPercent ?? this.defaultPercent,
    categoryRates: categoryRates ?? this.categoryRates,
    userIds: userIds ?? this.userIds,
    includeUnpaid: includeUnpaid ?? this.includeUnpaid,
    minimumSaleValue: minimumSaleValue ?? this.minimumSaleValue,
    isActive: isActive ?? this.isActive,
    effectiveFrom: effectiveFrom ?? this.effectiveFrom,
    effectiveTo: effectiveTo ?? this.effectiveTo,
    notes: notes ?? this.notes,
    createdBy: createdBy ?? this.createdBy,
    createdByName: createdByName ?? this.createdByName,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
