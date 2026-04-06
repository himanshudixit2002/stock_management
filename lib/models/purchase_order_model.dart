import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

enum POStatus { draft, sent, partial, received, cancelled }

class POItem {
  final String productId;
  final String productName;
  final int quantity;
  final int receivedQuantity;
  final double unitPrice;

  POItem({
    required this.productId,
    this.productName = '',
    required this.quantity,
    this.receivedQuantity = 0,
    this.unitPrice = 0,
  });

  factory POItem.fromMap(Map<String, dynamic> map) {
    return POItem(
      productId: safeString(map['productId']),
      productName: safeString(map['productName']),
      quantity: safeInt(map['quantity']),
      receivedQuantity: safeInt(map['receivedQuantity']),
      unitPrice: safeDouble(map['unitPrice']),
    );
  }

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'productName': productName,
    'quantity': quantity,
    'receivedQuantity': receivedQuantity,
    'unitPrice': unitPrice,
  };

  POItem copyWith({
    String? productId,
    String? productName,
    int? quantity,
    int? receivedQuantity,
    double? unitPrice,
  }) {
    return POItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      receivedQuantity: receivedQuantity ?? this.receivedQuantity,
      unitPrice: unitPrice ?? this.unitPrice,
    );
  }
}

class PurchaseOrderModel {
  final String id;
  final String vendorId;
  final String vendorName;
  final POStatus status;
  final List<POItem> items;
  final double totalAmount;
  final DateTime expectedDate;
  final DateTime? receivedDate;
  final String notes;
  final String invoiceId;
  /// Set when this PO was auto-created from a purchase bill (standalone bill).
  final String originInvoiceId;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;

  PurchaseOrderModel({
    required this.id,
    required this.vendorId,
    this.vendorName = '',
    this.status = POStatus.draft,
    this.items = const [],
    this.totalAmount = 0,
    required this.expectedDate,
    this.receivedDate,
    this.notes = '',
    this.invoiceId = '',
    this.originInvoiceId = '',
    this.createdBy = '',
    this.createdByName = '',
    required this.createdAt,
    required this.updatedAt,
  });

  String get statusLabel => switch (status) {
    POStatus.draft => 'Draft',
    POStatus.sent => 'Sent',
    POStatus.partial => 'Partially Received',
    POStatus.received => 'Received',
    POStatus.cancelled => 'Cancelled',
  };

  static POStatus _statusFromString(String s) => switch (s) {
    'sent' => POStatus.sent,
    'partial' => POStatus.partial,
    'received' => POStatus.received,
    'cancelled' => POStatus.cancelled,
    _ => POStatus.draft,
  };

  static String _statusToString(POStatus s) => switch (s) {
    POStatus.draft => 'draft',
    POStatus.sent => 'sent',
    POStatus.partial => 'partial',
    POStatus.received => 'received',
    POStatus.cancelled => 'cancelled',
  };

  factory PurchaseOrderModel.fromMap(Map<String, dynamic> map, String docId) {
    List<POItem> items = [];
    if (map['items'] is List) {
      items = (map['items'] as List)
          .map((e) => POItem.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    }
    return PurchaseOrderModel(
      id: docId,
      vendorId: safeString(map['vendorId']),
      vendorName: safeString(map['vendorName']),
      status: _statusFromString(safeString(map['status'], 'draft')),
      items: items,
      totalAmount: safeDouble(map['totalAmount']),
      expectedDate: safeTimestamp(map['expectedDate']),
      receivedDate: map['receivedDate'] != null
          ? safeTimestamp(map['receivedDate'])
          : null,
      notes: safeString(map['notes']),
      invoiceId: safeString(map['invoiceId']),
      originInvoiceId: safeString(map['originInvoiceId']),
      createdBy: safeString(map['createdBy']),
      createdByName: safeString(map['createdByName']),
      createdAt: safeTimestamp(map['createdAt']),
      updatedAt: safeTimestamp(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'vendorId': vendorId,
    'vendorName': vendorName,
    'status': _statusToString(status),
    'items': items.map((e) => e.toMap()).toList(),
    'totalAmount': totalAmount,
    'expectedDate': Timestamp.fromDate(expectedDate),
    if (receivedDate != null)
      'receivedDate': Timestamp.fromDate(receivedDate!),
    'notes': notes,
    'invoiceId': invoiceId,
    'originInvoiceId': originInvoiceId,
    'createdBy': createdBy,
    'createdByName': createdByName,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  PurchaseOrderModel copyWith({
    String? id,
    String? vendorId,
    String? vendorName,
    POStatus? status,
    List<POItem>? items,
    double? totalAmount,
    DateTime? expectedDate,
    DateTime? receivedDate,
    String? notes,
    String? invoiceId,
    String? originInvoiceId,
    String? createdBy,
    String? createdByName,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearReceivedDate = false,
  }) {
    return PurchaseOrderModel(
      id: id ?? this.id,
      vendorId: vendorId ?? this.vendorId,
      vendorName: vendorName ?? this.vendorName,
      status: status ?? this.status,
      items: items ?? this.items,
      totalAmount: totalAmount ?? this.totalAmount,
      expectedDate: expectedDate ?? this.expectedDate,
      receivedDate: clearReceivedDate
          ? null
          : (receivedDate ?? this.receivedDate),
      notes: notes ?? this.notes,
      invoiceId: invoiceId ?? this.invoiceId,
      originInvoiceId: originInvoiceId ?? this.originInvoiceId,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
