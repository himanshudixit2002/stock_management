import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';
import '../utils/unit_conversion.dart';

/// Sentinel key used inside [ProductModel.heldLocationQuantities] to track
/// reservations from location-less (manual, product-level) stock holds. Keeping
/// the reservation in the same map means `heldQuantity` stays consistent and the
/// units are blocked from being sold elsewhere until despatched or unheld.
///
/// NOTE: This must NOT match Firestore's reserved field-name pattern `__.*__`
/// (names beginning and ending with double underscores are rejected as map
/// keys). The parentheses also guarantee it can never collide with a real
/// user-entered location name.
const String kUnassignedHoldLocation = '(unassigned)';

class ProductModel {
  final String id;
  final String name;
  final String categoryId;
  final String categoryName;
  final String company;
  final String size;
  final int quantity;
  final int heldQuantity;
  final String unit;
  final String baseUnit;
  final String packUnit;
  final int unitsPerPack;
  final Map<String, int> locationQuantities;
  final Map<String, int> heldLocationQuantities;
  final String description;
  final int lowStockThreshold;
  final double costPrice;
  final double sellingPrice;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;
  final String createdByName;
  final String updatedBy;
  final String updatedByName;
  final String preferredVendorId;
  final String preferredVendorName;
  final String lastVendorId;
  final String lastVendorName;
  final Map<String, double> vendorPrices;
  final String barcode;

  ProductModel({
    required this.id,
    required this.name,
    required this.categoryId,
    this.categoryName = '',
    this.company = '',
    this.size = '',
    required this.quantity,
    this.heldQuantity = 0,
    this.unit = 'pcs',
    this.baseUnit = 'pcs',
    this.packUnit = 'box',
    this.unitsPerPack = 1,
    this.locationQuantities = const {},
    this.heldLocationQuantities = const {},
    this.description = '',
    this.lowStockThreshold = 10,
    this.costPrice = 0,
    this.sellingPrice = 0,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy = '',
    this.createdByName = '',
    this.updatedBy = '',
    this.updatedByName = '',
    this.preferredVendorId = '',
    this.preferredVendorName = '',
    this.lastVendorId = '',
    this.lastVendorName = '',
    this.vendorPrices = const {},
    this.barcode = '',
  });

  bool get isOutOfStock => quantity <= 0;
  bool get isLowStock => quantity > 0 && quantity <= lowStockThreshold;
  bool get isInStock => quantity > lowStockThreshold;
  int get availableQuantity =>
      quantity - heldQuantity < 0 ? 0 : quantity - heldQuantity;
  bool get hasPackUnit => unitsPerPack > 1;

  List<String> get locations => locationQuantities.keys.toList();
  List<String> get holdLocations => heldLocationQuantities.keys
      .where((loc) => loc != kUnassignedHoldLocation)
      .toList();

  /// Quantity reserved by location-less (product-level) holds.
  int get unassignedHeldQuantity =>
      heldLocationQuantities[kUnassignedHoldLocation] ?? 0;

  int availableAtLocation(String location) {
    final onHand = locationQuantities[location] ?? 0;
    final held = heldLocationQuantities[location] ?? 0;
    final available = onHand - held;
    return available < 0 ? 0 : available;
  }

  /// On-hand units that can actually be despatched from [location], capped by
  /// the product-level available quantity. This prevents despatching more than
  /// the global available when reservations are not tied to a location.
  int availableForDispatchAtLocation(String location) {
    final onHand = locationQuantities[location] ?? 0;
    final cap = onHand < availableQuantity ? onHand : availableQuantity;
    return cap < 0 ? 0 : cap;
  }
  String formatQuantity(int baseQuantity) => formatQuantityWithUnits(
    baseQuantity: baseQuantity,
    baseUnit: baseUnit,
    packUnit: packUnit,
    unitsPerPack: unitsPerPack,
  );

  double get profit => sellingPrice - costPrice;
  double get totalStockValue => sellingPrice * quantity;
  double get totalCostValue => costPrice * quantity;

  String get stockStatus {
    if (isOutOfStock) return 'Out of Stock';
    if (isLowStock) return 'Low Stock';
    return 'In Stock';
  }

  factory ProductModel.fromMap(Map<String, dynamic> map, String docId) {
    Map<String, int> locQty = {};
    if (map['locationQuantities'] != null && map['locationQuantities'] is Map) {
      final raw = map['locationQuantities'] as Map;
      locQty = raw.map((k, v) => MapEntry(safeString(k), safeInt(v)));
    } else {
      final loc = safeString(map['location']);
      if (loc.isNotEmpty) {
        locQty = {loc: safeInt(map['quantity'])};
      }
    }

    Map<String, double> vPrices = {};
    if (map['vendorPrices'] != null && map['vendorPrices'] is Map) {
      final raw = map['vendorPrices'] as Map;
      vPrices = raw.map((k, v) => MapEntry(safeString(k), safeDouble(v)));
    }

    Map<String, int> heldLocQty = {};
    if (map['heldLocationQuantities'] != null &&
        map['heldLocationQuantities'] is Map) {
      final raw = map['heldLocationQuantities'] as Map;
      heldLocQty = raw.map((k, v) => MapEntry(safeString(k), safeInt(v)));
    }

    final rawQty = safeInt(map['quantity']);
    final rawHeldQty = safeInt(map['heldQuantity']);
    final rawThreshold = safeInt(map['lowStockThreshold'], 10);
    final rawCost = safeDouble(map['costPrice']);
    final rawSelling = safeDouble(map['sellingPrice']);

    return ProductModel(
      id: docId,
      name: safeString(map['name']),
      categoryId: safeString(map['categoryId']),
      categoryName: safeString(map['categoryName']),
      company: safeString(map['company']),
      size: safeString(map['size']),
      quantity: rawQty < 0 ? 0 : rawQty,
      heldQuantity: rawHeldQty < 0 ? 0 : rawHeldQty,
      unit: safeString(map['unit'], 'pcs'),
      baseUnit: safeString(
        map['baseUnit'],
        safeString(map['unit'], 'pcs'),
      ),
      packUnit: safeString(map['packUnit'], 'box'),
      unitsPerPack: normalizeUnitsPerPack(safeInt(map['unitsPerPack'], 1)),
      locationQuantities: locQty,
      heldLocationQuantities: heldLocQty,
      description: safeString(map['description']),
      lowStockThreshold: rawThreshold < 0 ? 0 : rawThreshold,
      costPrice: rawCost < 0 ? 0 : rawCost,
      sellingPrice: rawSelling < 0 ? 0 : rawSelling,
      createdAt: safeTimestamp(map['createdAt']),
      updatedAt: safeTimestamp(map['updatedAt']),
      createdBy: safeString(map['createdBy']),
      createdByName: safeString(map['createdByName']),
      updatedBy: safeString(map['updatedBy']),
      updatedByName: safeString(map['updatedByName']),
      preferredVendorId: safeString(map['preferredVendorId']),
      preferredVendorName: safeString(map['preferredVendorName']),
      lastVendorId: safeString(map['lastVendorId']),
      lastVendorName: safeString(map['lastVendorName']),
      vendorPrices: vPrices,
      barcode: safeString(map['barcode']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'categoryId': categoryId,
      'categoryName': categoryName,
      'company': company,
      'size': size,
      'quantity': quantity,
      'heldQuantity': heldQuantity,
      'unit': unit,
      'baseUnit': baseUnit,
      'packUnit': packUnit,
      'unitsPerPack': normalizeUnitsPerPack(unitsPerPack),
      'locationQuantities': locationQuantities,
      'heldLocationQuantities': heldLocationQuantities,
      'description': description,
      'lowStockThreshold': lowStockThreshold,
      'costPrice': costPrice,
      'sellingPrice': sellingPrice,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'createdBy': createdBy,
      'createdByName': createdByName,
      'updatedBy': updatedBy,
      'updatedByName': updatedByName,
      'preferredVendorId': preferredVendorId,
      'preferredVendorName': preferredVendorName,
      'lastVendorId': lastVendorId,
      'lastVendorName': lastVendorName,
      'vendorPrices': vendorPrices,
      'barcode': barcode,
    };
  }

  ProductModel copyWith({
    String? id,
    String? name,
    String? categoryId,
    String? categoryName,
    String? company,
    String? size,
    int? quantity,
    int? heldQuantity,
    String? unit,
    String? baseUnit,
    String? packUnit,
    int? unitsPerPack,
    Map<String, int>? locationQuantities,
    Map<String, int>? heldLocationQuantities,
    String? description,
    int? lowStockThreshold,
    double? costPrice,
    double? sellingPrice,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
    String? createdByName,
    String? updatedBy,
    String? updatedByName,
    String? preferredVendorId,
    String? preferredVendorName,
    String? lastVendorId,
    String? lastVendorName,
    Map<String, double>? vendorPrices,
    String? barcode,
  }) {
    return ProductModel(
      id: id ?? this.id,
      name: name ?? this.name,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      company: company ?? this.company,
      size: size ?? this.size,
      quantity: quantity ?? this.quantity,
      heldQuantity: heldQuantity ?? this.heldQuantity,
      unit: unit ?? this.unit,
      baseUnit: baseUnit ?? this.baseUnit,
      packUnit: packUnit ?? this.packUnit,
      unitsPerPack: normalizeUnitsPerPack(unitsPerPack ?? this.unitsPerPack),
      locationQuantities: locationQuantities ?? this.locationQuantities,
      heldLocationQuantities:
          heldLocationQuantities ?? this.heldLocationQuantities,
      description: description ?? this.description,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      costPrice: costPrice ?? this.costPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      updatedBy: updatedBy ?? this.updatedBy,
      updatedByName: updatedByName ?? this.updatedByName,
      preferredVendorId: preferredVendorId ?? this.preferredVendorId,
      preferredVendorName: preferredVendorName ?? this.preferredVendorName,
      lastVendorId: lastVendorId ?? this.lastVendorId,
      lastVendorName: lastVendorName ?? this.lastVendorName,
      vendorPrices: vendorPrices ?? this.vendorPrices,
      barcode: barcode ?? this.barcode,
    );
  }
}
