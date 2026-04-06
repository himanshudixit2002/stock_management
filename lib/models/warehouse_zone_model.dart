import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

class WarehouseZoneModel {
  final String id;
  final String locationName;
  final String zoneName;
  final String binCode;
  final String description;
  final int capacity;
  final int currentStock;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  WarehouseZoneModel({
    required this.id,
    this.locationName = '',
    this.zoneName = '',
    this.binCode = '',
    this.description = '',
    this.capacity = 0,
    this.currentStock = 0,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WarehouseZoneModel.fromMap(Map<String, dynamic> map, String docId) {
    return WarehouseZoneModel(
      id: docId,
      locationName: safeString(map['locationName']),
      zoneName: safeString(map['zoneName']),
      binCode: safeString(map['binCode']),
      description: safeString(map['description']),
      capacity: safeInt(map['capacity']),
      currentStock: safeInt(map['currentStock']),
      isActive: safeBool(map['isActive'], true),
      createdAt: safeTimestamp(map['createdAt']),
      updatedAt: safeTimestamp(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'locationName': locationName,
    'zoneName': zoneName,
    'binCode': binCode,
    'description': description,
    'capacity': capacity,
    'currentStock': currentStock,
    'isActive': isActive,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  WarehouseZoneModel copyWith({
    String? id,
    String? locationName,
    String? zoneName,
    String? binCode,
    String? description,
    int? capacity,
    int? currentStock,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WarehouseZoneModel(
      id: id ?? this.id,
      locationName: locationName ?? this.locationName,
      zoneName: zoneName ?? this.zoneName,
      binCode: binCode ?? this.binCode,
      description: description ?? this.description,
      capacity: capacity ?? this.capacity,
      currentStock: currentStock ?? this.currentStock,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
