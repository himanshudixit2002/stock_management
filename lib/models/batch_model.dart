import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

enum BatchStatus { active, expired, recalled }

class BatchModel {
  final String id;
  final String productId;
  final String productName;
  final String batchNumber;
  final DateTime expiryDate;
  final DateTime? manufacturingDate;
  final int quantity;
  final String location;
  final BatchStatus status;
  final String notes;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;

  BatchModel({
    required this.id,
    required this.productId,
    this.productName = '',
    required this.batchNumber,
    required this.expiryDate,
    this.manufacturingDate,
    this.quantity = 0,
    this.location = '',
    this.status = BatchStatus.active,
    this.notes = '',
    this.createdBy = '',
    this.createdByName = '',
    required this.createdAt,
    required this.updatedAt,
  });

  String get statusLabel => switch (status) {
    BatchStatus.active => 'Active',
    BatchStatus.expired => 'Expired',
    BatchStatus.recalled => 'Recalled',
  };

  static BatchStatus _statusFromString(String s) => switch (s) {
    'expired' => BatchStatus.expired,
    'recalled' => BatchStatus.recalled,
    _ => BatchStatus.active,
  };

  static String _statusToString(BatchStatus s) => switch (s) {
    BatchStatus.active => 'active',
    BatchStatus.expired => 'expired',
    BatchStatus.recalled => 'recalled',
  };

  factory BatchModel.fromMap(Map<String, dynamic> map, String docId) {
    return BatchModel(
      id: docId,
      productId: safeString(map['productId']),
      productName: safeString(map['productName']),
      batchNumber: safeString(map['batchNumber']),
      expiryDate: safeTimestamp(map['expiryDate']),
      manufacturingDate: map['manufacturingDate'] != null
          ? safeTimestamp(map['manufacturingDate'])
          : null,
      quantity: safeInt(map['quantity']),
      location: safeString(map['location']),
      status: _statusFromString(safeString(map['status'], 'active')),
      notes: safeString(map['notes']),
      createdBy: safeString(map['createdBy']),
      createdByName: safeString(map['createdByName']),
      createdAt: safeTimestamp(map['createdAt']),
      updatedAt: safeTimestamp(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'productName': productName,
    'batchNumber': batchNumber,
    'expiryDate': Timestamp.fromDate(expiryDate),
    if (manufacturingDate != null)
      'manufacturingDate': Timestamp.fromDate(manufacturingDate!),
    'quantity': quantity,
    'location': location,
    'status': _statusToString(status),
    'notes': notes,
    'createdBy': createdBy,
    'createdByName': createdByName,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  BatchModel copyWith({
    String? id,
    String? productId,
    String? productName,
    String? batchNumber,
    DateTime? expiryDate,
    DateTime? manufacturingDate,
    int? quantity,
    String? location,
    BatchStatus? status,
    String? notes,
    String? createdBy,
    String? createdByName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BatchModel(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      batchNumber: batchNumber ?? this.batchNumber,
      expiryDate: expiryDate ?? this.expiryDate,
      manufacturingDate: manufacturingDate ?? this.manufacturingDate,
      quantity: quantity ?? this.quantity,
      location: location ?? this.location,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
