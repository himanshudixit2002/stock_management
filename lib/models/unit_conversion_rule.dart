import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/parse_helpers.dart';
import '../utils/unit_conversion.dart';

/// "1 box = 10 pcs" for a slice of the catalog, set once in Settings rather
/// than typed into every product.
///
/// The scope is any mix of category, brand (`ProductModel.company`) and
/// sub-category (`ProductModel.size`). An empty field matches anything, so a
/// rule with all three empty covers the whole catalog. When several rules
/// cover a product, `resolveUnitConversion` picks the most specific.
///
/// Stored as one map in the `settings.unitConversions` list on the company
/// document, next to the brand and sub-category lists it refers to.
class UnitConversionRule {
  const UnitConversionRule({
    required this.id,
    this.categoryId = '',
    this.company = '',
    this.size = '',
    required this.packUnit,
    required this.unitsPerPack,
    required this.baseUnit,
    this.updatedAt,
    this.updatedBy = '',
    this.updatedByName = '',
  });

  /// A pack of one is no pack at all, so a rule has to describe at least two.
  static const int minUnitsPerPack = 2;

  final String id;

  /// Category document id, compared exactly. Empty matches any category.
  final String categoryId;

  /// Brand, as stored on `ProductModel.company`. Empty matches any brand.
  final String company;

  /// Sub-category, as stored on `ProductModel.size`. Empty matches any.
  final String size;

  final String packUnit;
  final int unitsPerPack;
  final String baseUnit;
  final DateTime? updatedAt;
  final String updatedBy;
  final String updatedByName;

  bool get coversEverything => specificity == 0;

  /// How many of the three scope fields are pinned. More is more specific.
  int get specificity =>
      (categoryId.isNotEmpty ? 1 : 0) +
      (company.trim().isNotEmpty ? 1 : 0) +
      (size.trim().isNotEmpty ? 1 : 0);

  /// Orders rules of equal [specificity]: a sub-category outranks a brand,
  /// which outranks a category. Pack sizes follow the size of the thing more
  /// often than its maker, and its maker more often than its shelf.
  int get precedence =>
      (size.trim().isNotEmpty ? 4 : 0) +
      (company.trim().isNotEmpty ? 2 : 0) +
      (categoryId.isNotEmpty ? 1 : 0);

  bool matches({
    required String categoryId,
    required String company,
    required String size,
  }) {
    if (this.categoryId.isNotEmpty && this.categoryId != categoryId) {
      return false;
    }
    if (this.company.trim().isNotEmpty && !sameLabel(this.company, company)) {
      return false;
    }
    if (this.size.trim().isNotEmpty && !sameLabel(this.size, size)) {
      return false;
    }
    return true;
  }

  /// Whether [other] covers exactly the same products. Two such rules would
  /// leave a product with two answers, so saving refuses the second.
  bool sameScopeAs(UnitConversionRule other) =>
      categoryId == other.categoryId &&
      sameLabel(company, other.company) &&
      sameLabel(size, other.size);

  /// "1 box = 10 pcs".
  String get label => '1 $packUnit = $unitsPerPack $baseUnit';

  /// Why this rule cannot be saved, or null when it can.
  String? get validationError {
    if (packUnit.trim().isEmpty || baseUnit.trim().isEmpty) {
      return 'Pick both units';
    }
    if (sameLabel(packUnit, baseUnit)) {
      return 'The pack and the unit inside it must differ';
    }
    if (unitsPerPack < minUnitsPerPack) {
      return 'A pack holds at least $minUnitsPerPack';
    }
    return null;
  }

  factory UnitConversionRule.fromMap(Map<String, dynamic> map) {
    final updatedAt = map['updatedAt'];
    return UnitConversionRule(
      id: safeString(map['id']),
      categoryId: safeString(map['categoryId']),
      company: safeString(map['company']),
      size: safeString(map['size']),
      packUnit: safeString(map['packUnit']),
      unitsPerPack: safeInt(map['unitsPerPack']),
      baseUnit: safeString(map['baseUnit']),
      updatedAt: updatedAt == null ? null : safeTimestamp(updatedAt),
      updatedBy: safeString(map['updatedBy']),
      updatedByName: safeString(map['updatedByName']),
    );
  }

  /// Reads `settings.unitConversions`, dropping entries a save could never
  /// have produced rather than letting one bad map hide every rule.
  static List<UnitConversionRule> listFromSettings(dynamic raw) {
    if (raw is! List) return const [];
    final rules = <UnitConversionRule>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final rule = UnitConversionRule.fromMap(Map<String, dynamic>.from(entry));
      if (rule.id.isEmpty || rule.validationError != null) continue;
      rules.add(rule);
    }
    return rules;
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'categoryId': categoryId,
    'company': company.trim(),
    'size': size.trim(),
    'packUnit': packUnit.trim(),
    'unitsPerPack': unitsPerPack,
    'baseUnit': baseUnit.trim(),
    if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    'updatedBy': updatedBy,
    'updatedByName': updatedByName,
  };

  UnitConversionRule copyWith({
    String? id,
    String? categoryId,
    String? company,
    String? size,
    String? packUnit,
    int? unitsPerPack,
    String? baseUnit,
    DateTime? updatedAt,
    String? updatedBy,
    String? updatedByName,
  }) {
    return UnitConversionRule(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      company: company ?? this.company,
      size: size ?? this.size,
      packUnit: packUnit ?? this.packUnit,
      unitsPerPack: unitsPerPack ?? this.unitsPerPack,
      baseUnit: baseUnit ?? this.baseUnit,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
      updatedByName: updatedByName ?? this.updatedByName,
    );
  }
}

/// [rules] after a rename of brand [from] to [to] in Settings, or null when no
/// rule named it. Renames carry into rules the way they carry into products,
/// or a renamed brand would silently stop matching its own conversion.
List<UnitConversionRule>? renameBrandInRules(
  List<UnitConversionRule> rules,
  String from,
  String to,
) => _renamed(
  rules,
  (rule) => sameLabel(rule.company, from) ? rule.copyWith(company: to) : null,
);

/// [renameBrandInRules] for a sub-category.
List<UnitConversionRule>? renameSizeInRules(
  List<UnitConversionRule> rules,
  String from,
  String to,
) => _renamed(
  rules,
  (rule) => sameLabel(rule.size, from) ? rule.copyWith(size: to) : null,
);

/// [renameBrandInRules] for a unit, which a rule can name on either side.
List<UnitConversionRule>? renameUnitInRules(
  List<UnitConversionRule> rules,
  String from,
  String to,
) => _renamed(rules, (rule) {
  final pack = sameLabel(rule.packUnit, from);
  final base = sameLabel(rule.baseUnit, from);
  if (!pack && !base) return null;
  return rule.copyWith(
    packUnit: pack ? to : rule.packUnit,
    baseUnit: base ? to : rule.baseUnit,
  );
});

List<UnitConversionRule>? _renamed(
  List<UnitConversionRule> rules,
  UnitConversionRule? Function(UnitConversionRule rule) rename,
) {
  var changed = false;
  final out = <UnitConversionRule>[];
  for (final rule in rules) {
    final renamed = rename(rule);
    if (renamed != null) changed = true;
    out.add(renamed ?? rule);
  }
  return changed ? out : null;
}
