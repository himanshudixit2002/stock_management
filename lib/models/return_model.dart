import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

enum ReturnType { customerReturn, vendorReturn }

enum ReturnStatus { pending, approved, processed, rejected }

class ReturnItem {
  final String productId;
  final String productName;
  final int quantity;
  final String reason;
  final String condition;

  ReturnItem({
    required this.productId,
    this.productName = '',
    required this.quantity,
    this.reason = '',
    this.condition = '',
  });

  factory ReturnItem.fromMap(Map<String, dynamic> map) {
    return ReturnItem(
      productId: safeString(map['productId']),
      productName: safeString(map['productName']),
      quantity: safeInt(map['quantity']),
      reason: safeString(map['reason']),
      condition: safeString(map['condition']),
    );
  }

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'productName': productName,
    'quantity': quantity,
    'reason': reason,
    'condition': condition,
  };

  ReturnItem copyWith({
    String? productId,
    String? productName,
    int? quantity,
    String? reason,
    String? condition,
  }) {
    return ReturnItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      reason: reason ?? this.reason,
      condition: condition ?? this.condition,
    );
  }
}

class ReturnModel {
  final String id;
  final ReturnType type;
  final String relatedOrderId;

  /// Human-readable snapshot when the user picked an order (party, status, date, etc.).
  final String relatedOrderSummary;
  final String customerId;
  final String customerName;
  final String vendorId;
  final String vendorName;
  final List<ReturnItem> items;
  final ReturnStatus status;
  final double refundAmount;
  final String notes;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;

  ReturnModel({
    required this.id,
    required this.type,
    this.relatedOrderId = '',
    this.relatedOrderSummary = '',
    this.customerId = '',
    this.customerName = '',
    this.vendorId = '',
    this.vendorName = '',
    this.items = const [],
    this.status = ReturnStatus.pending,
    this.refundAmount = 0,
    this.notes = '',
    this.createdBy = '',
    this.createdByName = '',
    required this.createdAt,
    required this.updatedAt,
  });

  String get typeLabel => switch (type) {
    ReturnType.customerReturn => 'Customer Return',
    ReturnType.vendorReturn => 'Vendor Return',
  };

  String get statusLabel => switch (status) {
    ReturnStatus.pending => 'Pending',
    ReturnStatus.approved => 'Approved',
    ReturnStatus.processed => 'Processed',
    ReturnStatus.rejected => 'Rejected',
  };

  static ReturnType _typeFromString(String s) => switch (s) {
    'vendorReturn' => ReturnType.vendorReturn,
    _ => ReturnType.customerReturn,
  };

  static String _typeToString(ReturnType t) => switch (t) {
    ReturnType.customerReturn => 'customerReturn',
    ReturnType.vendorReturn => 'vendorReturn',
  };

  static ReturnStatus _statusFromString(String s) => switch (s) {
    'approved' => ReturnStatus.approved,
    'processed' => ReturnStatus.processed,
    'rejected' => ReturnStatus.rejected,
    _ => ReturnStatus.pending,
  };

  static String _statusToString(ReturnStatus s) => switch (s) {
    ReturnStatus.pending => 'pending',
    ReturnStatus.approved => 'approved',
    ReturnStatus.processed => 'processed',
    ReturnStatus.rejected => 'rejected',
  };

  factory ReturnModel.fromMap(Map<String, dynamic> map, String docId) {
    List<ReturnItem> items = [];
    if (map['items'] is List) {
      items = (map['items'] as List)
          .map((e) => ReturnItem.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    }
    return ReturnModel(
      id: docId,
      type: _typeFromString(safeString(map['type'], 'customerReturn')),
      relatedOrderId: safeString(map['relatedOrderId']),
      relatedOrderSummary: safeString(map['relatedOrderSummary']),
      customerId: safeString(map['customerId']),
      customerName: safeString(map['customerName']),
      vendorId: safeString(map['vendorId']),
      vendorName: safeString(map['vendorName']),
      items: items,
      status: _statusFromString(safeString(map['status'], 'pending')),
      refundAmount: safeDouble(map['refundAmount']),
      notes: safeString(map['notes']),
      createdBy: safeString(map['createdBy']),
      createdByName: safeString(map['createdByName']),
      createdAt: safeTimestamp(map['createdAt']),
      updatedAt: safeTimestamp(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'type': _typeToString(type),
    'relatedOrderId': relatedOrderId,
    'relatedOrderSummary': relatedOrderSummary,
    'customerId': customerId,
    'customerName': customerName,
    'vendorId': vendorId,
    'vendorName': vendorName,
    'items': items.map((e) => e.toMap()).toList(),
    'status': _statusToString(status),
    'refundAmount': refundAmount,
    'notes': notes,
    'createdBy': createdBy,
    'createdByName': createdByName,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  ReturnModel copyWith({
    String? id,
    ReturnType? type,
    String? relatedOrderId,
    String? relatedOrderSummary,
    String? customerId,
    String? customerName,
    String? vendorId,
    String? vendorName,
    List<ReturnItem>? items,
    ReturnStatus? status,
    double? refundAmount,
    String? notes,
    String? createdBy,
    String? createdByName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ReturnModel(
      id: id ?? this.id,
      type: type ?? this.type,
      relatedOrderId: relatedOrderId ?? this.relatedOrderId,
      relatedOrderSummary: relatedOrderSummary ?? this.relatedOrderSummary,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      vendorId: vendorId ?? this.vendorId,
      vendorName: vendorName ?? this.vendorName,
      items: items ?? this.items,
      status: status ?? this.status,
      refundAmount: refundAmount ?? this.refundAmount,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
