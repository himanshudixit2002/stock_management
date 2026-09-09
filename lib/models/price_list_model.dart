import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

/// How a price list decides what a customer pays for one product.
enum PriceListMode {
  /// A fixed price per unit, ignoring the product's own selling price.
  fixedPrice,

  /// A percentage off the product's selling price.
  discountPercent,

  /// A margin over the product's cost price.
  marginOverCost,
}

/// One product's entry on a price list.
class PriceListEntry {
  final String productId;
  final String productName;
  final PriceListMode mode;

  /// The number [mode] interprets: a price, a percentage off, or a margin
  /// percentage over cost.
  final double value;

  /// Optional quantity floor. The entry only applies from this quantity up,
  /// which is how a slab ("100+ units at 12% off") is expressed.
  final int minQuantity;

  const PriceListEntry({
    required this.productId,
    this.productName = '',
    this.mode = PriceListMode.discountPercent,
    this.value = 0,
    this.minQuantity = 0,
  });

  /// The unit price this entry yields, or null when it does not apply at
  /// [quantity].
  ///
  /// Never returns a negative price: a 120% discount is a data-entry error, not
  /// an instruction to pay the customer.
  double? priceFor({
    required double sellingPrice,
    required double costPrice,
    int quantity = 1,
  }) {
    if (minQuantity > 0 && quantity < minQuantity) return null;
    final raw = switch (mode) {
      PriceListMode.fixedPrice => value,
      PriceListMode.discountPercent =>
        sellingPrice * (1 - value.clamp(0, 100) / 100),
      PriceListMode.marginOverCost => costPrice * (1 + value / 100),
    };
    return raw < 0 ? 0 : raw;
  }

  static PriceListMode modeFromString(String s) => switch (s) {
    'fixedPrice' => PriceListMode.fixedPrice,
    'marginOverCost' => PriceListMode.marginOverCost,
    _ => PriceListMode.discountPercent,
  };

  static String modeToString(PriceListMode m) => switch (m) {
    PriceListMode.fixedPrice => 'fixedPrice',
    PriceListMode.discountPercent => 'discountPercent',
    PriceListMode.marginOverCost => 'marginOverCost',
  };

  static String modeLabelOf(PriceListMode m) => switch (m) {
    PriceListMode.fixedPrice => 'Fixed price',
    PriceListMode.discountPercent => 'Discount %',
    PriceListMode.marginOverCost => 'Margin over cost',
  };

  String get modeLabel => modeLabelOf(mode);

  factory PriceListEntry.fromMap(Map<String, dynamic> map) => PriceListEntry(
    productId: safeString(map['productId']),
    productName: safeString(map['productName']),
    mode: modeFromString(safeString(map['mode'], 'discountPercent')),
    value: safeDouble(map['value']),
    minQuantity: safeInt(map['minQuantity']),
  );

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'productName': productName,
    'mode': modeToString(mode),
    'value': value,
    'minQuantity': minQuantity,
  };

  PriceListEntry copyWith({
    String? productId,
    String? productName,
    PriceListMode? mode,
    double? value,
    int? minQuantity,
  }) => PriceListEntry(
    productId: productId ?? this.productId,
    productName: productName ?? this.productName,
    mode: mode ?? this.mode,
    value: value ?? this.value,
    minQuantity: minQuantity ?? this.minQuantity,
  );
}

/// A named set of prices, assignable to customers.
class PriceListModel {
  final String id;
  final String name;
  final String description;

  /// Applied to any product with no entry of its own. This is what makes a
  /// list useful before anyone has filled in a single product.
  final double defaultDiscountPercent;

  final List<PriceListEntry> entries;

  /// Customer ids this list applies to. Denormalised onto the list rather than
  /// onto each customer so assigning a list is one write, and so the list
  /// screen can show its reach without reading the customer collection.
  final List<String> customerIds;

  final bool isActive;

  /// When set, the list stops applying after this date.
  final DateTime? validUntil;

  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;

  PriceListModel({
    required this.id,
    required this.name,
    this.description = '',
    this.defaultDiscountPercent = 0,
    this.entries = const [],
    this.customerIds = const [],
    this.isActive = true,
    this.validUntil,
    this.createdBy = '',
    this.createdByName = '',
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isExpired =>
      validUntil != null && validUntil!.isBefore(DateTime.now());

  /// True when this list should be applied at all.
  bool get isApplicable => isActive && !isExpired;

  bool appliesTo(String customerId) =>
      customerId.isNotEmpty && customerIds.contains(customerId);

  /// The best-matching entry for [productId] at [quantity], or null.
  ///
  /// "Best" means the highest [PriceListEntry.minQuantity] the quantity
  /// reaches, so slabs stack in the customer's favour without needing to be
  /// stored in order.
  PriceListEntry? entryFor(String productId, {int quantity = 1}) {
    PriceListEntry? best;
    for (final e in entries) {
      if (e.productId != productId) continue;
      if (e.minQuantity > 0 && quantity < e.minQuantity) continue;
      if (best == null || e.minQuantity > best.minQuantity) best = e;
    }
    return best;
  }

  factory PriceListModel.fromMap(Map<String, dynamic> map, String docId) {
    final rawEntries = map['entries'];
    final rawCustomers = map['customerIds'];
    return PriceListModel(
      id: docId,
      name: safeString(map['name']),
      description: safeString(map['description']),
      defaultDiscountPercent: safeDouble(map['defaultDiscountPercent']),
      entries: rawEntries is List
          ? rawEntries
                .whereType<Map>()
                .map((e) => PriceListEntry.fromMap(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
      customerIds: rawCustomers is List
          ? rawCustomers.whereType<String>().toList()
          : const [],
      isActive: safeBool(map['isActive'], true),
      validUntil: map['validUntil'] == null
          ? null
          : safeTimestamp(map['validUntil']),
      createdBy: safeString(map['createdBy']),
      createdByName: safeString(map['createdByName']),
      createdAt: safeTimestamp(map['createdAt']),
      updatedAt: safeTimestamp(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'description': description,
    'defaultDiscountPercent': defaultDiscountPercent,
    'entries': entries.map((e) => e.toMap()).toList(),
    'customerIds': customerIds,
    'isActive': isActive,
    if (validUntil != null) 'validUntil': Timestamp.fromDate(validUntil!),
    'createdBy': createdBy,
    'createdByName': createdByName,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  PriceListModel copyWith({
    String? id,
    String? name,
    String? description,
    double? defaultDiscountPercent,
    List<PriceListEntry>? entries,
    List<String>? customerIds,
    bool? isActive,
    DateTime? validUntil,
    String? createdBy,
    String? createdByName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => PriceListModel(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    defaultDiscountPercent:
        defaultDiscountPercent ?? this.defaultDiscountPercent,
    entries: entries ?? this.entries,
    customerIds: customerIds ?? this.customerIds,
    isActive: isActive ?? this.isActive,
    validUntil: validUntil ?? this.validUntil,
    createdBy: createdBy ?? this.createdBy,
    createdByName: createdByName ?? this.createdByName,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
