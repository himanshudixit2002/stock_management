import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

enum SOStatus { draft, confirmed, dispatched, delivered, cancelled }

class SOItem {
  final String productId;
  final String productName;
  final int quantity;
  final int dispatchedQuantity;
  /// Qty recorded back on this line when a customer return is processed (capped vs dispatched).
  final int returnedQuantity;
  final double unitPrice;

  SOItem({
    required this.productId,
    this.productName = '',
    required this.quantity,
    this.dispatchedQuantity = 0,
    this.returnedQuantity = 0,
    this.unitPrice = 0,
  });

  factory SOItem.fromMap(Map<String, dynamic> map) {
    return SOItem(
      productId: safeString(map['productId']),
      productName: safeString(map['productName']),
      quantity: safeInt(map['quantity']),
      dispatchedQuantity: safeInt(map['dispatchedQuantity']),
      returnedQuantity: safeInt(map['returnedQuantity']),
      unitPrice: safeDouble(map['unitPrice']),
    );
  }

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'productName': productName,
    'quantity': quantity,
    'dispatchedQuantity': dispatchedQuantity,
    'returnedQuantity': returnedQuantity,
    'unitPrice': unitPrice,
  };

  SOItem copyWith({
    String? productId,
    String? productName,
    int? quantity,
    int? dispatchedQuantity,
    int? returnedQuantity,
    double? unitPrice,
  }) {
    return SOItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      dispatchedQuantity: dispatchedQuantity ?? this.dispatchedQuantity,
      returnedQuantity: returnedQuantity ?? this.returnedQuantity,
      unitPrice: unitPrice ?? this.unitPrice,
    );
  }
}

class SalesOrderModel {
  final String id;
  final String customerId;
  final String customerName;
  final SOStatus status;
  final List<SOItem> items;
  final double totalAmount;
  final String notes;
  final String invoiceId;
  /// When set, this order was auto-created from a standalone sales invoice ([originInvoiceId]).
  final String originInvoiceId;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;

  SalesOrderModel({
    required this.id,
    required this.customerId,
    this.customerName = '',
    this.status = SOStatus.draft,
    this.items = const [],
    this.totalAmount = 0,
    this.notes = '',
    this.invoiceId = '',
    this.originInvoiceId = '',
    this.createdBy = '',
    this.createdByName = '',
    required this.createdAt,
    required this.updatedAt,
  });

  String get statusLabel => switch (status) {
    SOStatus.draft => 'Draft',
    SOStatus.confirmed => 'Confirmed',
    SOStatus.dispatched => 'Dispatched',
    SOStatus.delivered => 'Delivered',
    SOStatus.cancelled => 'Cancelled',
  };

  static SOStatus _statusFromString(String s) => switch (s) {
    'confirmed' => SOStatus.confirmed,
    'dispatched' => SOStatus.dispatched,
    'delivered' => SOStatus.delivered,
    'cancelled' => SOStatus.cancelled,
    _ => SOStatus.draft,
  };

  static String _statusToString(SOStatus s) => switch (s) {
    SOStatus.draft => 'draft',
    SOStatus.confirmed => 'confirmed',
    SOStatus.dispatched => 'dispatched',
    SOStatus.delivered => 'delivered',
    SOStatus.cancelled => 'cancelled',
  };

  factory SalesOrderModel.fromMap(Map<String, dynamic> map, String docId) {
    List<SOItem> items = [];
    if (map['items'] is List) {
      items = (map['items'] as List)
          .map((e) => SOItem.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    }
    return SalesOrderModel(
      id: docId,
      customerId: safeString(map['customerId']),
      customerName: safeString(map['customerName']),
      status: _statusFromString(safeString(map['status'], 'draft')),
      items: items,
      totalAmount: safeDouble(map['totalAmount']),
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
    'customerId': customerId,
    'customerName': customerName,
    'status': _statusToString(status),
    'items': items.map((e) => e.toMap()).toList(),
    'totalAmount': totalAmount,
    'notes': notes,
    'invoiceId': invoiceId,
    'originInvoiceId': originInvoiceId,
    'createdBy': createdBy,
    'createdByName': createdByName,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  SalesOrderModel copyWith({
    String? id,
    String? customerId,
    String? customerName,
    SOStatus? status,
    List<SOItem>? items,
    double? totalAmount,
    String? notes,
    String? invoiceId,
    String? originInvoiceId,
    String? createdBy,
    String? createdByName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SalesOrderModel(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      status: status ?? this.status,
      items: items ?? this.items,
      totalAmount: totalAmount ?? this.totalAmount,
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
