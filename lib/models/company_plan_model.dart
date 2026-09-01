import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

/// Lifecycle of a company's plan subscription.
enum PlanStatus { active, pastDue, cancelled }

/// A plan the platform offers.
///
/// Only [PlanCatalog.free] exists today. [limits] is carried but read by
/// nothing yet — nothing enforces a plan. Keeping the shape here means paid
/// tiers can be added without touching any call site.
class PlanDefinition {
  final String id;
  final String label;
  final String description;

  /// Named caps, e.g. `{'products': 500}`. An absent key means "no limit".
  /// Nothing reads this yet; see the class doc.
  final Map<String, int> limits;

  const PlanDefinition({
    required this.id,
    required this.label,
    required this.description,
    this.limits = const {},
  });
}

/// Every plan the platform offers, in display order.
class PlanCatalog {
  PlanCatalog._();

  static const String freeId = 'free';

  static const PlanDefinition free = PlanDefinition(
    id: freeId,
    label: 'Free',
    description: 'Full access to every feature. No limits applied.',
  );

  static const List<PlanDefinition> all = [free];

  /// The definition for [planId], falling back to [free] for an unknown id so
  /// a company can never end up with no plan at all.
  static PlanDefinition byId(String planId) {
    for (final plan in all) {
      if (plan.id == planId) return plan;
    }
    return free;
  }
}

/// The plan a single company is on.
class CompanyPlan {
  final String planId;
  final PlanStatus status;
  final DateTime? startedAt;

  /// Free-text note from whoever last changed the plan.
  final String note;

  const CompanyPlan({
    this.planId = PlanCatalog.freeId,
    this.status = PlanStatus.active,
    this.startedAt,
    this.note = '',
  });

  /// The catalog entry this plan refers to.
  PlanDefinition get definition => PlanCatalog.byId(planId);

  String get label => definition.label;

  bool get isActive => status == PlanStatus.active;

  static PlanStatus _statusFromString(String s) => switch (s) {
    'pastDue' => PlanStatus.pastDue,
    'cancelled' => PlanStatus.cancelled,
    _ => PlanStatus.active,
  };

  static String _statusToString(PlanStatus s) => switch (s) {
    PlanStatus.active => 'active',
    PlanStatus.pastDue => 'pastDue',
    PlanStatus.cancelled => 'cancelled',
  };

  /// Reads a plan from a company doc's `plan` map.
  ///
  /// Every company created before plans existed has no `plan` field at all, so
  /// a null map must yield the free plan rather than null. That default is
  /// what lets this ship without a data migration.
  factory CompanyPlan.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const CompanyPlan();
    return CompanyPlan(
      planId: safeString(map['planId'], PlanCatalog.freeId),
      status: _statusFromString(safeString(map['status'], 'active')),
      startedAt: map['startedAt'] == null
          ? null
          : safeTimestamp(map['startedAt']),
      note: safeString(map['note']),
    );
  }

  Map<String, dynamic> toMap() => {
    'planId': planId,
    'status': _statusToString(status),
    if (startedAt != null) 'startedAt': Timestamp.fromDate(startedAt!),
    'note': note,
  };

  CompanyPlan copyWith({
    String? planId,
    PlanStatus? status,
    DateTime? startedAt,
    String? note,
  }) {
    return CompanyPlan(
      planId: planId ?? this.planId,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      note: note ?? this.note,
    );
  }
}
