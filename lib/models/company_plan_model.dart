import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

/// Lifecycle of a company's plan subscription.
enum PlanStatus { active, pastDue, cancelled }

/// Named caps a plan can carry. Kept as constants rather than bare strings so a
/// typo in a limit key cannot silently mean "unlimited".
class PlanLimitKeys {
  PlanLimitKeys._();

  static const String users = 'users';
  static const String products = 'products';
  static const String invoices = 'invoices';
  static const String salesOrders = 'salesOrders';
  static const String purchaseOrders = 'purchaseOrders';

  /// In the order the console and the tenant's plan screen show them.
  static const List<String> all = [
    users,
    products,
    invoices,
    salesOrders,
    purchaseOrders,
  ];

  static String labelOf(String key) => switch (key) {
    users => 'Team members',
    products => 'Products',
    invoices => 'Invoices',
    salesOrders => 'Sales orders',
    purchaseOrders => 'Purchase orders',
    _ => key,
  };
}

/// A plan the platform offers.
class PlanDefinition {
  final String id;
  final String label;
  final String description;
  final int? nominalPrice;
  final int? promotionalPrice;

  /// Named caps, e.g. `{'products': 500}`. An absent key means "no limit".
  final Map<String, int> limits;

  /// [FeatureMap] entry ids this tier does not include. An empty set means the
  /// tier carries the whole catalog.
  final Set<String> lockedFeatures;

  /// Display order in the console and on the customer-facing plan screen.
  final int sortOrder;

  /// Retired tiers stay readable — companies may still be on them — but are not
  /// offered for new assignments.
  final bool archived;

  const PlanDefinition({
    required this.id,
    required this.label,
    required this.description,
    this.nominalPrice,
    this.promotionalPrice,
    this.limits = const {},
    this.lockedFeatures = const {},
    this.sortOrder = 0,
    this.archived = false,
  });

  /// The cap for [key], or null when this tier does not cap it.
  int? limitFor(String key) => limits[key];

  /// Reads a tier from its `plans/{id}` document.
  ///
  /// Every field is coerced rather than cast: these documents are edited by
  /// hand from the console, and one malformed value must not take the whole
  /// catalog down with it.
  factory PlanDefinition.fromMap(Map<String, dynamic> map, String id) {
    return PlanDefinition(
      id: id,
      label: safeString(map['label'], id),
      description: safeString(map['description']),
      nominalPrice: _asInt(map['nominalPrice']),
      promotionalPrice: _asInt(map['promotionalPrice']),
      limits: _limitsFrom(map['limits']),
      lockedFeatures: _stringSetFrom(map['lockedFeatures']),
      sortOrder: _asInt(map['sortOrder']) ?? 0,
      archived: map['archived'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
    'label': label,
    'description': description,
    'nominalPrice': ?nominalPrice,
    'promotionalPrice': ?promotionalPrice,
    'limits': limits,
    'lockedFeatures': lockedFeatures.toList(),
    'sortOrder': sortOrder,
    'archived': archived,
  };

  PlanDefinition copyWith({
    String? id,
    String? label,
    String? description,
    int? nominalPrice,
    int? promotionalPrice,
    Map<String, int>? limits,
    Set<String>? lockedFeatures,
    int? sortOrder,
    bool? archived,
  }) {
    return PlanDefinition(
      id: id ?? this.id,
      label: label ?? this.label,
      description: description ?? this.description,
      nominalPrice: nominalPrice ?? this.nominalPrice,
      promotionalPrice: promotionalPrice ?? this.promotionalPrice,
      limits: limits ?? this.limits,
      lockedFeatures: lockedFeatures ?? this.lockedFeatures,
      sortOrder: sortOrder ?? this.sortOrder,
      archived: archived ?? this.archived,
    );
  }

  static int? _asInt(dynamic value) => value is num ? value.toInt() : null;

  static Map<String, int> _limitsFrom(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, int>{};
    raw.forEach((key, value) {
      if (key is String && value is num) out[key] = value.toInt();
    });
    return out;
  }

  static Set<String> _stringSetFrom(dynamic raw) {
    if (raw is! List) return const {};
    return raw.whereType<String>().toSet();
  }
}

/// Every plan the platform offers, in display order.
class PlanCatalog {
  PlanCatalog._();

  static const String starterId = 'starter';
  static const String growthId = 'growth';
  static const String proId = 'pro';
  static const String maxId = 'max';

  static const PlanDefinition starter = PlanDefinition(
    id: starterId,
    label: 'Starter',
    description: 'For a single location finding its feet. Core stock control.',
    nominalPrice: 999,
    promotionalPrice: 0,
    limits: {
      PlanLimitKeys.users: 3,
      PlanLimitKeys.products: 250,
      PlanLimitKeys.invoices: 100,
      PlanLimitKeys.salesOrders: 100,
      PlanLimitKeys.purchaseOrders: 100,
    },
    lockedFeatures: {'aiAssistant'},
  );

  static const PlanDefinition growth = PlanDefinition(
    id: growthId,
    label: 'Growth',
    description: 'A growing team with real order volume and multiple locations.',
    nominalPrice: 2999,
    promotionalPrice: 0,
    limits: {
      PlanLimitKeys.users: 10,
      PlanLimitKeys.products: 2000,
      PlanLimitKeys.invoices: 1000,
      PlanLimitKeys.salesOrders: 1000,
      PlanLimitKeys.purchaseOrders: 1000,
    },
    lockedFeatures: {'aiAssistant'},
  );

  static const PlanDefinition pro = PlanDefinition(
    id: proId,
    label: 'Pro',
    description: 'Full operations suite with generous headroom.',
    nominalPrice: 5999,
    promotionalPrice: 0,
    limits: {
      PlanLimitKeys.users: 50,
      PlanLimitKeys.products: 20000,
    },
  );

  static const PlanDefinition maxTier = PlanDefinition(
    id: maxId,
    label: 'MAX Tier',
    description:
        'Ultimate business suite. Full access to every feature including AI Assistant.',
    nominalPrice: 9999,
    promotionalPrice: 0,
  );

  /// The tiers this build ships with.
  ///
  /// These are the seed for `plans/{id}` and the fallback whenever Firestore
  /// has not answered — so the app always has a usable catalog, offline or on
  /// a first run against an empty database.
  static const List<PlanDefinition> seedDefaults = [
    starter,
    growth,
    pro,
    maxTier,
  ];

  static List<PlanDefinition> _all = List.unmodifiable(seedDefaults);

  /// Every tier, in display order.
  static List<PlanDefinition> get all => _all;

  /// Tiers that may be assigned to a workspace today.
  static List<PlanDefinition> get assignable =>
      _all.where((p) => !p.archived).toList();

  /// Replaces the catalog with what the platform console has published.
  ///
  /// Deliberately synchronous and global: `CompanyPlan.definition`,
  /// `PlanLimits` and every console widget read the catalog inline, and making
  /// those async to accommodate a live catalog would have rippled through the
  /// whole app for no benefit. An empty list is ignored rather than applied —
  /// a database that has not been seeded yet must not blank the catalog.
  static void hydrate(List<PlanDefinition> plans) {
    if (plans.isEmpty) return;
    final sorted = [...plans]
      ..sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        return byOrder != 0 ? byOrder : a.label.compareTo(b.label);
      });
    _all = List.unmodifiable(sorted);
  }

  /// Restores the tiers compiled into this build. Used by tests and on sign-out.
  static void resetToSeed() {
    _all = List.unmodifiable(seedDefaults);
  }

  /// The tier a company doc with no `plan` field is treated as being on.
  ///
  /// This is MAX on purpose and must stay that way. Every company created
  /// before plans existed — and every company created today, since
  /// AuthService still writes no `plan` field — has nothing to read here. A
  /// lower default would silently downgrade the entire existing tenant base
  /// and start blocking their writes at the first limit. Tiers are assigned
  /// deliberately from the platform console, never inherited by accident.
  static const String defaultId = maxId;

  /// The definition for [planId], falling back to the default tier for an
  /// unknown id so a company can never end up with no plan at all.
  /// Falls back to [maxTier] — not to the first entry — so a workspace on a
  /// tier that was renamed or deleted in the console keeps full access rather
  /// than silently inheriting whatever tier happens to sort first.
  static PlanDefinition byId(String planId) {
    for (final plan in _all) {
      if (plan.id == planId) return plan;
    }
    return maxTier;
  }
}

/// The plan a single company is on.
class CompanyPlan {
  final String planId;
  final PlanStatus status;
  final DateTime? startedAt;

  /// When a trial ends. Null for a plan that is not on trial.
  final DateTime? trialEndsAt;

  /// Per-company caps that win over the tier's own, so one workspace can be
  /// given headroom without inventing a bespoke tier for it. A value of -1
  /// means "explicitly unlimited", which a plain absence cannot express.
  final Map<String, int> limitOverrides;

  /// Free-text note from whoever last changed the plan.
  final String note;

  const CompanyPlan({
    this.planId = PlanCatalog.defaultId,
    this.status = PlanStatus.active,
    this.startedAt,
    this.trialEndsAt,
    this.limitOverrides = const {},
    this.note = '',
  });

  /// The catalog entry this plan refers to.
  PlanDefinition get definition => PlanCatalog.byId(planId);

  String get label => definition.label;

  bool get isActive => status == PlanStatus.active;

  bool get isOnTrial =>
      trialEndsAt != null && trialEndsAt!.isAfter(DateTime.now());

  bool get trialExpired =>
      trialEndsAt != null && !trialEndsAt!.isAfter(DateTime.now());

  /// The caps that actually apply: the tier's, with any per-company override
  /// on top. An override of -1 removes the cap entirely.
  Map<String, int> get effectiveLimits {
    final merged = <String, int>{...definition.limits};
    limitOverrides.forEach((key, value) {
      if (value < 0) {
        merged.remove(key);
      } else {
        merged[key] = value;
      }
    });
    return merged;
  }

  /// The cap for [key], or null when nothing caps it.
  int? limitFor(String key) => effectiveLimits[key];

  bool allowsFeature(String featureId) =>
      !definition.lockedFeatures.contains(featureId);

  static PlanStatus _statusFromString(String s) => switch (s) {
    'pastDue' => PlanStatus.pastDue,
    'cancelled' => PlanStatus.cancelled,
    _ => PlanStatus.active,
  };

  static String statusToString(PlanStatus s) => switch (s) {
    PlanStatus.active => 'active',
    PlanStatus.pastDue => 'pastDue',
    PlanStatus.cancelled => 'cancelled',
  };

  static String statusLabel(PlanStatus s) => switch (s) {
    PlanStatus.active => 'Active',
    PlanStatus.pastDue => 'Past due',
    PlanStatus.cancelled => 'Cancelled',
  };

  /// Reads a plan from a company doc's `plan` map.
  ///
  /// A null map must yield the default tier rather than null — see
  /// [PlanCatalog.defaultId] for why that default is MAX.
  factory CompanyPlan.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const CompanyPlan();
    return CompanyPlan(
      planId: safeString(map['planId'], PlanCatalog.defaultId),
      status: _statusFromString(safeString(map['status'], 'active')),
      startedAt: map['startedAt'] == null
          ? null
          : safeTimestamp(map['startedAt']),
      trialEndsAt: map['trialEndsAt'] == null
          ? null
          : safeTimestamp(map['trialEndsAt']),
      limitOverrides: _limitsFromMap(map['limitOverrides']),
      note: safeString(map['note']),
    );
  }

  /// Overrides arrive from Firestore as num, so coerce rather than cast — a
  /// value written as 500.0 would otherwise throw and lose the whole plan.
  static Map<String, int> _limitsFromMap(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, int>{};
    raw.forEach((key, value) {
      if (key is String && value is num) out[key] = value.toInt();
    });
    return out;
  }

  Map<String, dynamic> toMap() => {
    'planId': planId,
    'status': statusToString(status),
    if (startedAt != null) 'startedAt': Timestamp.fromDate(startedAt!),
    if (trialEndsAt != null) 'trialEndsAt': Timestamp.fromDate(trialEndsAt!),
    if (limitOverrides.isNotEmpty) 'limitOverrides': limitOverrides,
    'note': note,
  };

  CompanyPlan copyWith({
    String? planId,
    PlanStatus? status,
    DateTime? startedAt,
    DateTime? trialEndsAt,
    Map<String, int>? limitOverrides,
    String? note,
  }) {
    return CompanyPlan(
      planId: planId ?? this.planId,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      trialEndsAt: trialEndsAt ?? this.trialEndsAt,
      limitOverrides: limitOverrides ?? this.limitOverrides,
      note: note ?? this.note,
    );
  }
}
