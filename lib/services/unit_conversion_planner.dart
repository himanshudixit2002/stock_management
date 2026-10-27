import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/product_model.dart';
import '../models/unit_conversion_rule.dart';
import '../utils/parse_helpers.dart';
import '../utils/unit_conversion.dart';

/// Which of [rules] covers a product with these attributes, or null if none.
///
/// The rule pinning the most of category, brand and sub-category wins, so
/// "Tiles · Kajaria" beats "Tiles". Between rules pinning the same number, a
/// sub-category beats a brand and a brand beats a category
/// ([UnitConversionRule.precedence]). Saving refuses two rules with the same
/// scope, so there is always a single answer.
UnitConversionRule? resolveUnitConversion(
  Iterable<UnitConversionRule> rules, {
  required String categoryId,
  required String company,
  required String size,
}) {
  UnitConversionRule? best;
  for (final rule in rules) {
    if (!rule.matches(categoryId: categoryId, company: company, size: size)) {
      continue;
    }
    if (best == null || _outranks(rule, best)) best = rule;
  }
  return best;
}

/// [resolveUnitConversion] for an existing product.
UnitConversionRule? resolveUnitConversionFor(
  Iterable<UnitConversionRule> rules,
  ProductModel product,
) => resolveUnitConversion(
  rules,
  categoryId: product.categoryId,
  company: product.company,
  size: product.size,
);

bool _outranks(UnitConversionRule a, UnitConversionRule b) {
  if (a.specificity != b.specificity) return a.specificity > b.specificity;
  return a.precedence > b.precedence;
}

enum UnitChangeKind {
  /// No rule covers the product, or it already follows its rule.
  none,

  /// Counted in the rule's base unit already: only the pack changes, and no
  /// stored quantity moves.
  repack,

  /// Counted in the rule's *pack* unit: every quantity is re-counted in the
  /// base unit and every per-unit price divided ([convertedProductFields]).
  convertStock,

  /// The conversion was set by hand on the product, which rules leave alone.
  keptCustom,

  /// Counted in a unit the rule does not mention — kg under "1 box = 10 pcs".
  unitMismatch,
}

/// What following its rule would do to one product.
class UnitChange {
  const UnitChange({required this.product, required this.kind, this.rule});

  final ProductModel product;
  final UnitChangeKind kind;
  final UnitConversionRule? rule;

  bool get writes =>
      kind == UnitChangeKind.repack || kind == UnitChangeKind.convertStock;

  /// How many new base units one old base unit becomes.
  int get factor =>
      kind == UnitChangeKind.convertStock ? rule!.unitsPerPack : 1;
}

/// Whether [product] already counts and packs the way [rule] says.
bool followsRule(ProductModel product, UnitConversionRule rule) =>
    sameLabel(product.baseUnit, rule.baseUnit) &&
    sameLabel(product.packUnit, rule.packUnit) &&
    product.unitsPerPack == rule.unitsPerPack;

UnitChange planUnitChange(
  ProductModel product,
  UnitConversionRule? rule, {
  bool includeCustom = false,
}) {
  UnitChange change(UnitChangeKind kind) =>
      UnitChange(product: product, kind: kind, rule: rule);

  if (rule == null || followsRule(product, rule)) {
    return change(UnitChangeKind.none);
  }
  if (product.customConversion && !includeCustom) {
    return change(UnitChangeKind.keptCustom);
  }
  if (sameLabel(product.baseUnit, rule.baseUnit)) {
    return change(UnitChangeKind.repack);
  }
  if (sameLabel(product.baseUnit, rule.packUnit)) {
    return change(UnitChangeKind.convertStock);
  }
  return change(UnitChangeKind.unitMismatch);
}

/// Every product in [products] that does not follow its rule, with what
/// following it would take. Products no rule covers are left out.
List<UnitChange> planUnitChanges(
  Iterable<ProductModel> products,
  Iterable<UnitConversionRule> rules, {
  bool includeCustom = false,
}) {
  final ruleList = rules.toList(growable: false);
  final changes = <UnitChange>[];
  for (final product in products) {
    final change = planUnitChange(
      product,
      resolveUnitConversionFor(ruleList, product),
      includeCustom: includeCustom,
    );
    if (change.kind != UnitChangeKind.none) changes.add(change);
  }
  return changes;
}

/// [product] with its pack taken from [rules], when following them needs no
/// stock conversion; unchanged otherwise. For a product being created, which
/// has no stock or history yet that a conversion would have to re-count.
ProductModel withRulePack(
  ProductModel product,
  Iterable<UnitConversionRule> rules,
) {
  final change = planUnitChange(
    product,
    resolveUnitConversionFor(rules, product),
  );
  if (change.kind != UnitChangeKind.repack) return product;
  return product.copyWith(
    packUnit: change.rule!.packUnit,
    unitsPerPack: change.rule!.unitsPerPack,
  );
}

/// The product fields a [UnitChangeKind.repack] writes. Nothing stock-owned:
/// the pack only changes how a quantity is entered and shown.
Map<String, Object?> repackFields(UnitConversionRule rule) => {
  'packUnit': rule.packUnit,
  'unitsPerPack': rule.unitsPerPack,
  // Following a rule again is the point of including a custom product.
  'customConversion': false,
};

/// A per-unit price after re-counting in units [factor] times smaller.
///
/// Rounded to six places rather than to cents: ₹100 a box of 12 is ₹8.33 at
/// cents, and twelve of those re-total to ₹99.96. At six places a whole pack
/// still re-totals to the old pack price once invoice totals round to cents.
double perUnitPrice(double price, int factor) =>
    (price / factor * 1e6).roundToDouble() / 1e6;

Map<String, int> _scaled(Map<String, int> quantities, int factor) => {
  for (final entry in quantities.entries) entry.key: entry.value * factor,
};

/// The product fields a [UnitChangeKind.convertStock] writes: stock re-counted
/// in [rule]'s base unit, prices per that unit.
///
/// Every location bucket scales, including the `(unassigned)` hold bucket and
/// the 'In transit' / 'At vendor' places, since each holds old units.
Map<String, Object?> convertedProductFields(
  ProductModel product,
  UnitConversionRule rule, {
  required DateTime at,
}) {
  final factor = rule.unitsPerPack;
  return {
    'quantity': product.quantity * factor,
    'locationQuantities': _scaled(product.locationQuantities, factor),
    'heldQuantity': product.heldQuantity * factor,
    'heldLocationQuantities': _scaled(product.heldLocationQuantities, factor),
    'lowStockThreshold': product.lowStockThreshold * factor,
    'costPrice': perUnitPrice(product.costPrice, factor),
    'sellingPrice': perUnitPrice(product.sellingPrice, factor),
    'vendorPrices': {
      for (final entry in product.vendorPrices.entries)
        entry.key: perUnitPrice(entry.value, factor),
    },
    'unit': rule.baseUnit,
    'baseUnit': rule.baseUnit,
    'packUnit': rule.packUnit,
    'unitsPerPack': factor,
    'customConversion': false,
    'unitsConvertedAt': Timestamp.fromDate(at),
  };
}

// --- Records that hold a product's quantity or price elsewhere -------------
//
// Each takes the raw document data and returns the fields to write, or null
// when nothing in it belongs to the product. Raw maps rather than models so a
// conversion rewrites only what it means to and never round-trips a document
// through a model that might drop a field it does not know about.

/// A hold still reserving stock, re-counted. Remaining stock is
/// quantity − consumed − released, so all three scale together.
Map<String, Object?> convertedHoldFields(
  Map<String, dynamic> hold,
  int factor,
) => {
  'quantity': safeInt(hold['quantity']) * factor,
  'consumedQuantity': safeInt(hold['consumedQuantity']) * factor,
  'releasedQuantity': safeInt(hold['releasedQuantity']) * factor,
};

Map<String, Object?> convertedBatchFields(
  Map<String, dynamic> batch,
  int factor,
) => {'quantity': safeInt(batch['quantity']) * factor};

List<Map<String, dynamic>> _maps(dynamic raw) => [
  if (raw is List)
    for (final entry in raw)
      if (entry is Map) Map<String, dynamic>.from(entry),
];

/// The list in [raw] with each entry for [productId] passed through
/// [convert], or null when no entry was for it.
List<Map<String, dynamic>>? _convertEntries(
  dynamic raw,
  String productId,
  Map<String, dynamic> Function(Map<String, dynamic> entry) convert,
) {
  var touched = false;
  final entries = <Map<String, dynamic>>[];
  for (final entry in _maps(raw)) {
    if (safeString(entry['productId']) == productId) {
      touched = true;
      entries.add(convert(entry));
    } else {
      entries.add(entry);
    }
  }
  return touched ? entries : null;
}

/// A price list's entries with [productId]'s quantity slab re-counted and, in
/// fixed-price mode, its price per new unit. The percentage modes are relative
/// to the product's own prices, which convert with it.
Map<String, Object?>? convertedPriceListFields(
  Map<String, dynamic> priceList,
  String productId,
  int factor,
) {
  final entries = _convertEntries(
    priceList['entries'],
    productId,
    (entry) => {
      ...entry,
      'minQuantity': safeInt(entry['minQuantity']) * factor,
      if (safeString(entry['mode']) == 'fixedPrice')
        'value': perUnitPrice(safeDouble(entry['value']), factor),
    },
  );
  return entries == null ? null : {'entries': entries};
}

/// A bill of materials re-counted wherever it names [productId]: as a
/// component, how many go into the output; as the output, how many a build
/// makes and how many have been built.
Map<String, Object?>? convertedBomFields(
  Map<String, dynamic> bom,
  String productId,
  int factor,
  String baseUnit,
) {
  final components = _convertEntries(
    bom['components'],
    productId,
    (component) => {
      ...component,
      'quantity': safeInt(component['quantity']) * factor,
      'unit': baseUnit,
    },
  );
  final isOutput = safeString(bom['outputProductId']) == productId;
  if (components == null && !isOutput) return null;
  return {
    'components': ?components,
    if (isOutput) ...{
      'outputQuantity': safeInt(bom['outputQuantity']) * factor,
      'totalBuilt': safeInt(bom['totalBuilt']) * factor,
    },
  };
}

/// A recurring invoice's template lines for [productId], re-counted with the
/// price per new unit, so every invoice it raises keeps the same total.
Map<String, Object?>? convertedRecurringInvoiceFields(
  Map<String, dynamic> template,
  String productId,
  int factor,
  String baseUnit,
) {
  final items = _convertEntries(
    template['items'],
    productId,
    (item) => {
      ...item,
      'quantity': safeInt(item['quantity']) * factor,
      'unitPrice': perUnitPrice(safeDouble(item['unitPrice']), factor),
      'unit': baseUnit,
    },
  );
  return items == null ? null : {'items': items};
}

/// An applied landed cost's lines for [productId], re-counted. Reversing it
/// writes `previousUnitCost` back as the product's cost price, which has to be
/// a per-new-unit cost by then. `allocatedAmount` is a line total, so it stays.
Map<String, Object?>? convertedLandedCostFields(
  Map<String, dynamic> landedCost,
  String productId,
  int factor,
) {
  final lines = _convertEntries(
    landedCost['lines'],
    productId,
    (line) => {
      ...line,
      'quantity': safeInt(line['quantity']) * factor,
      'baseUnitCost': perUnitPrice(safeDouble(line['baseUnitCost']), factor),
      'previousUnitCost': perUnitPrice(
        safeDouble(line['previousUnitCost']),
        factor,
      ),
    },
  );
  return lines == null ? null : {'lines': lines};
}
