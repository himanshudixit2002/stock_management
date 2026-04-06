import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

class ProductModel {
  final String id;
  final String name;
  final String categoryId;
  final String categoryName;
  final String company;
  final String size;
  final int quantity;
  final String unit;
  final Map<String, int> locationQuantities;
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
    this.unit = 'pcs',
    this.locationQuantities = const {},
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

  List<String> get locations => locationQuantities.keys.toList();

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

    final rawQty = safeInt(map['quantity']);
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
      unit: safeString(map['unit'], 'pcs'),
      locationQuantities: locQty,
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
      'unit': unit,
      'locationQuantities': locationQuantities,
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
    String? unit,
    Map<String, int>? locationQuantities,
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
      unit: unit ?? this.unit,
      locationQuantities: locationQuantities ?? this.locationQuantities,
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
