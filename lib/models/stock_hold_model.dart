import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

enum StockHoldStatus { active, partiallyConsumed, consumed, released, expired }

enum StockHoldSourceType { manual, salesOrder, invoice }

/// A single line item used when creating multiple manual holds in one batch
/// (one challan, many products).
class StockHoldBatchItem {
  final String productId;
  final String productName;
  final int quantity;

  const StockHoldBatchItem({
    required this.productId,
    required this.productName,
    required this.quantity,
  });
}

class StockHoldModel {
  final String id;
  final String productId;
  final String productName;

  /// The reserved location. Empty for location-less (product-level) manual
  /// holds, in which case the despatch location is chosen at despatch time.
  final String location;
  final int quantity;
  final int consumedQuantity;
  final int releasedQuantity;
  final StockHoldStatus status;
  final StockHoldSourceType sourceType;
  final String sourceId;
  final String challanNumber;
  final String reason;
  final String notes;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? expiresAt;

  const StockHoldModel({
    required this.id,
    required this.productId,
    this.productName = '',
    this.location = '',
    required this.quantity,
    this.consumedQuantity = 0,
    this.releasedQuantity = 0,
    this.status = StockHoldStatus.active,
    this.sourceType = StockHoldSourceType.manual,
    this.sourceId = '',
    this.challanNumber = '',
    this.reason = '',
    this.notes = '',
    this.createdBy = '',
    this.createdByName = '',
    required this.createdAt,
    required this.updatedAt,
    this.expiresAt,
  });

  int get remainingQuantity {
    final remaining = quantity - consumedQuantity - releasedQuantity;
    return remaining < 0 ? 0 : remaining;
  }

  /// Whether this hold is tied to a specific location. Location-less holds
  /// (product-level manual reservations) pick a despatch location at despatch.
  bool get hasLocation => location.trim().isNotEmpty;

  /// Manual holds can be unheld/despatched directly. Order-linked holds
  /// (sales order / invoice) must be managed through the order flow so their
  /// dispatched quantity and status stay in sync.
  bool get isManual => sourceType == StockHoldSourceType.manual;

  bool get isOrderLinked => !isManual;

  static StockHoldStatus _statusFromString(String value) {
    return switch (value) {
      'partially_consumed' => StockHoldStatus.partiallyConsumed,
      'consumed' => StockHoldStatus.consumed,
      'released' => StockHoldStatus.released,
      'expired' => StockHoldStatus.expired,
      _ => StockHoldStatus.active,
    };
  }

  static String _statusToString(StockHoldStatus value) {
    return switch (value) {
      StockHoldStatus.active => 'active',
      StockHoldStatus.partiallyConsumed => 'partially_consumed',
      StockHoldStatus.consumed => 'consumed',
      StockHoldStatus.released => 'released',
      StockHoldStatus.expired => 'expired',
    };
  }

  static StockHoldSourceType _sourceFromString(String value) {
    return switch (value) {
      'sales_order' => StockHoldSourceType.salesOrder,
      'invoice' => StockHoldSourceType.invoice,
      _ => StockHoldSourceType.manual,
    };
  }

  static String _sourceToString(StockHoldSourceType value) {
    return switch (value) {
      StockHoldSourceType.manual => 'manual',
      StockHoldSourceType.salesOrder => 'sales_order',
      StockHoldSourceType.invoice => 'invoice',
    };
  }

  factory StockHoldModel.fromMap(Map<String, dynamic> map, String docId) {
    return StockHoldModel(
      id: docId,
      productId: safeString(map['productId']),
      productName: safeString(map['productName']),
      location: safeString(map['location']),
      quantity: safeInt(map['quantity']),
      consumedQuantity: safeInt(map['consumedQuantity']),
      releasedQuantity: safeInt(map['releasedQuantity']),
      status: _statusFromString(safeString(map['status'], 'active')),
      sourceType: _sourceFromString(safeString(map['sourceType'], 'manual')),
      sourceId: safeString(map['sourceId']),
      challanNumber: safeString(map['challanNumber']),
      reason: safeString(map['reason']),
      notes: safeString(map['notes']),
      createdBy: safeString(map['createdBy']),
      createdByName: safeString(map['createdByName']),
      createdAt: safeTimestamp(map['createdAt']),
      updatedAt: safeTimestamp(map['updatedAt']),
      expiresAt: map['expiresAt'] is Timestamp
          ? (map['expiresAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'productName': productName,
      'location': location,
      'quantity': quantity,
      'consumedQuantity': consumedQuantity,
      'releasedQuantity': releasedQuantity,
      'status': _statusToString(status),
      'sourceType': _sourceToString(sourceType),
      'sourceId': sourceId,
      'challanNumber': challanNumber,
      'reason': reason,
      'notes': notes,
      'createdBy': createdBy,
      'createdByName': createdByName,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
    };
  }

  StockHoldModel copyWith({
    String? id,
    String? productId,
    String? productName,
    String? location,
    int? quantity,
    int? consumedQuantity,
    int? releasedQuantity,
    StockHoldStatus? status,
    StockHoldSourceType? sourceType,
    String? sourceId,
    String? challanNumber,
    String? reason,
    String? notes,
    String? createdBy,
    String? createdByName,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? expiresAt,
  }) {
    return StockHoldModel(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      location: location ?? this.location,
      quantity: quantity ?? this.quantity,
      consumedQuantity: consumedQuantity ?? this.consumedQuantity,
      releasedQuantity: releasedQuantity ?? this.releasedQuantity,
      status: status ?? this.status,
      sourceType: sourceType ?? this.sourceType,
      sourceId: sourceId ?? this.sourceId,
      challanNumber: challanNumber ?? this.challanNumber,
      reason: reason ?? this.reason,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}
