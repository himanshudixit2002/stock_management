import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

/// Lifecycle of a bill of materials.
///
/// A [draft] is still being edited and cannot be built from; [active] is the
/// recipe currently in use; [archived] keeps historical builds readable without
/// offering the recipe for new ones.
enum BomStatus { draft, active, archived }

/// One component line of a [BomModel]: how much of [productId] one build run
/// consumes.
class BomComponent {
  final String productId;
  final String productName;

  /// Quantity of this component consumed per [BomModel.outputQuantity] units
  /// of output — not per single unit. Storing it per run avoids fractional
  /// component quantities for recipes like "3 units from 2 sheets".
  final int quantity;
  final String unit;

  /// Expected loss on this component, as a percentage of [quantity]. Rounded up
  /// when a build is costed so a recipe never under-consumes.
  final double wastagePercent;

  const BomComponent({
    required this.productId,
    this.productName = '',
    required this.quantity,
    this.unit = '',
    this.wastagePercent = 0,
  });

  /// Units of this component consumed by [runs] build runs, including wastage.
  ///
  /// Wastage rounds up: consuming 10.2 units means 11 leave the shelf, and
  /// rounding down would let a build succeed on stock that is not there.
  int consumptionFor(int runs) {
    if (runs <= 0) return 0;
    final base = quantity * runs;
    if (wastagePercent <= 0) return base;
    return (base * (1 + wastagePercent / 100)).ceil();
  }

  factory BomComponent.fromMap(Map<String, dynamic> map) => BomComponent(
    productId: safeString(map['productId']),
    productName: safeString(map['productName']),
    quantity: safeInt(map['quantity']),
    unit: safeString(map['unit']),
    wastagePercent: safeDouble(map['wastagePercent']),
  );

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'productName': productName,
    'quantity': quantity,
    'unit': unit,
    'wastagePercent': wastagePercent,
  };

  BomComponent copyWith({
    String? productId,
    String? productName,
    int? quantity,
    String? unit,
    double? wastagePercent,
  }) => BomComponent(
    productId: productId ?? this.productId,
    productName: productName ?? this.productName,
    quantity: quantity ?? this.quantity,
    unit: unit ?? this.unit,
    wastagePercent: wastagePercent ?? this.wastagePercent,
  );
}

/// A recipe: [outputQuantity] units of [outputProductId] made from
/// [components].
class BomModel {
  final String id;
  final String name;
  final String outputProductId;
  final String outputProductName;

  /// Units of output produced by one build run. Always >= 1.
  final int outputQuantity;
  final List<BomComponent> components;
  final BomStatus status;
  final String notes;

  /// Running total of output units ever produced from this recipe. Maintained
  /// by the build path so the list can rank recipes by use without a query.
  final int totalBuilt;
  final DateTime? lastBuiltAt;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;

  BomModel({
    required this.id,
    required this.name,
    required this.outputProductId,
    this.outputProductName = '',
    this.outputQuantity = 1,
    this.components = const [],
    this.status = BomStatus.draft,
    this.notes = '',
    this.totalBuilt = 0,
    this.lastBuiltAt,
    this.createdBy = '',
    this.createdByName = '',
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isBuildable => status == BomStatus.active && components.isNotEmpty;

  String get statusLabel => switch (status) {
    BomStatus.draft => 'Draft',
    BomStatus.active => 'Active',
    BomStatus.archived => 'Archived',
  };

  /// Output units produced by [runs] runs.
  int outputFor(int runs) => runs <= 0 ? 0 : outputQuantity * runs;

  /// What [runs] runs consume, keyed by component product id.
  ///
  /// Components are summed rather than replaced, so a recipe that lists the
  /// same product twice consumes both lines instead of silently dropping one.
  Map<String, int> consumptionFor(int runs) {
    final out = <String, int>{};
    for (final c in components) {
      if (c.productId.isEmpty) continue;
      out[c.productId] = (out[c.productId] ?? 0) + c.consumptionFor(runs);
    }
    return out;
  }

  /// The largest number of runs [available] on-hand quantities can support.
  ///
  /// Returns 0 for a recipe with no components rather than infinity: a recipe
  /// that consumes nothing is a data error, not a licence to print stock.
  int maxRunsFrom(Map<String, int> available) {
    if (components.isEmpty) return 0;
    var best = -1;
    for (final c in components) {
      if (c.productId.isEmpty || c.quantity <= 0) continue;
      final onHand = available[c.productId] ?? 0;
      // Search down from the naive ratio: wastage rounds up, so the exact
      // answer is at most what ignoring wastage would allow.
      var runs = onHand ~/ c.quantity;
      while (runs > 0 && c.consumptionFor(runs) > onHand) {
        runs--;
      }
      if (best == -1 || runs < best) best = runs;
    }
    return best == -1 ? 0 : best;
  }

  static BomStatus _statusFromString(String s) => switch (s) {
    'active' => BomStatus.active,
    'archived' => BomStatus.archived,
    _ => BomStatus.draft,
  };

  static String statusToString(BomStatus s) => switch (s) {
    BomStatus.draft => 'draft',
    BomStatus.active => 'active',
    BomStatus.archived => 'archived',
  };

  factory BomModel.fromMap(Map<String, dynamic> map, String docId) {
    final rawComponents = map['components'];
    return BomModel(
      id: docId,
      name: safeString(map['name']),
      outputProductId: safeString(map['outputProductId']),
      outputProductName: safeString(map['outputProductName']),
      // Clamped rather than trusted: a zero here would make every build
      // produce nothing while still consuming components.
      outputQuantity: safeInt(map['outputQuantity'], 1).clamp(1, 1000000),
      components: rawComponents is List
          ? rawComponents
                .whereType<Map>()
                .map(
                  (e) => BomComponent.fromMap(Map<String, dynamic>.from(e)),
                )
                .toList()
          : const [],
      status: _statusFromString(safeString(map['status'], 'draft')),
      notes: safeString(map['notes']),
      totalBuilt: safeInt(map['totalBuilt']),
      lastBuiltAt: map['lastBuiltAt'] == null
          ? null
          : safeTimestamp(map['lastBuiltAt']),
      createdBy: safeString(map['createdBy']),
      createdByName: safeString(map['createdByName']),
      createdAt: safeTimestamp(map['createdAt']),
      updatedAt: safeTimestamp(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'outputProductId': outputProductId,
    'outputProductName': outputProductName,
    'outputQuantity': outputQuantity,
    'components': components.map((c) => c.toMap()).toList(),
    'status': statusToString(status),
    'notes': notes,
    'totalBuilt': totalBuilt,
    if (lastBuiltAt != null) 'lastBuiltAt': Timestamp.fromDate(lastBuiltAt!),
    'createdBy': createdBy,
    'createdByName': createdByName,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  BomModel copyWith({
    String? id,
    String? name,
    String? outputProductId,
    String? outputProductName,
    int? outputQuantity,
    List<BomComponent>? components,
    BomStatus? status,
    String? notes,
    int? totalBuilt,
    DateTime? lastBuiltAt,
    String? createdBy,
    String? createdByName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => BomModel(
    id: id ?? this.id,
    name: name ?? this.name,
    outputProductId: outputProductId ?? this.outputProductId,
    outputProductName: outputProductName ?? this.outputProductName,
    outputQuantity: outputQuantity ?? this.outputQuantity,
    components: components ?? this.components,
    status: status ?? this.status,
    notes: notes ?? this.notes,
    totalBuilt: totalBuilt ?? this.totalBuilt,
    lastBuiltAt: lastBuiltAt ?? this.lastBuiltAt,
    createdBy: createdBy ?? this.createdBy,
    createdByName: createdByName ?? this.createdByName,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
