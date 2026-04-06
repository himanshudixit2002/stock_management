import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

enum InvoiceType { sales, purchase }

enum InvoiceStatus {
  draft,
  sent,
  partiallyPaid,
  paid,
  overdue,
  cancelled,
  refunded,
}

class InvoiceItem {
  final String productId;
  final String productName;
  final int quantity;
  final String unit;
  final double unitPrice;
  final double discountPercent;
  final double taxRate;

  InvoiceItem({
    required this.productId,
    this.productName = '',
    required this.quantity,
    this.unit = 'pcs',
    this.unitPrice = 0,
    this.discountPercent = 0,
    this.taxRate = 0,
  });

  double get lineSubtotal => quantity * unitPrice;
  double get lineDiscount => lineSubtotal * discountPercent.clamp(0, 100) / 100;
  double get lineTaxable => lineSubtotal - lineDiscount;
  double get lineTax => lineTaxable * taxRate / 100;
  double get lineTotal => lineTaxable + lineTax;

  factory InvoiceItem.fromMap(Map<String, dynamic> map) {
    return InvoiceItem(
      productId: safeString(map['productId']),
      productName: safeString(map['productName']),
      quantity: safeInt(map['quantity']),
      unit: safeString(map['unit'], 'pcs'),
      unitPrice: safeDouble(map['unitPrice']),
      discountPercent: safeDouble(map['discountPercent']),
      taxRate: safeDouble(map['taxRate']),
    );
  }

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'productName': productName,
    'quantity': quantity,
    'unit': unit,
    'unitPrice': unitPrice,
    'discountPercent': discountPercent,
    'taxRate': taxRate,
  };

  InvoiceItem copyWith({
    String? productId,
    String? productName,
    int? quantity,
    String? unit,
    double? unitPrice,
    double? discountPercent,
    double? taxRate,
  }) {
    return InvoiceItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      unitPrice: unitPrice ?? this.unitPrice,
      discountPercent: discountPercent ?? this.discountPercent,
      taxRate: taxRate ?? this.taxRate,
    );
  }
}

class PaymentRecord {
  final String id;
  final double amount;
  final DateTime date;
  final String method;
  final String referenceNumber;
  final String notes;

  PaymentRecord({
    required this.id,
    required this.amount,
    required this.date,
    this.method = 'cash',
    this.referenceNumber = '',
    this.notes = '',
  });

  factory PaymentRecord.fromMap(Map<String, dynamic> map) {
    return PaymentRecord(
      id: safeString(map['id']),
      amount: safeDouble(map['amount']),
      date: safeTimestamp(map['date']),
      method: safeString(map['method'], 'cash'),
      referenceNumber: safeString(map['referenceNumber']),
      notes: safeString(map['notes']),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'amount': amount,
    'date': Timestamp.fromDate(date),
    'method': method,
    'referenceNumber': referenceNumber,
    'notes': notes,
  };

  String get methodLabel => switch (method) {
    'cash' => 'Cash',
    'upi' => 'UPI',
    'card' => 'Card',
    'bank' => 'Bank Transfer',
    'cheque' => 'Cheque',
    _ => method,
  };
}

class InvoiceModel {
  final String id;
  final InvoiceType invoiceType;
  final String invoiceNumber;
  final String customerId;
  final String customerName;
  final String customerPhone;
  final String customerAddress;
  final String vendorId;
  final String vendorName;
  final InvoiceStatus status;
  final List<InvoiceItem> items;
  final double discountPercent;
  final double discountAmount;
  final String taxLabel;
  final double subtotal;
  final double totalDiscount;
  final double totalTax;
  final double grandTotal;
  final double amountPaid;
  final double amountDue;
  final List<PaymentRecord> payments;
  final DateTime invoiceDate;
  final DateTime dueDate;
  final String notes;
  final String termsText;
  final String linkedSalesOrderId;
  final String linkedPurchaseOrderId;
  final String linkedCreditNoteId;
  /// True after inventory was adjusted for this document: sales stock removed or purchase stock added.
  final bool stockDeducted;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;

  InvoiceModel({
    required this.id,
    this.invoiceType = InvoiceType.sales,
    required this.invoiceNumber,
    required this.customerId,
    this.customerName = '',
    this.customerPhone = '',
    this.customerAddress = '',
    this.vendorId = '',
    this.vendorName = '',
    this.status = InvoiceStatus.draft,
    this.items = const [],
    this.discountPercent = 0,
    this.discountAmount = 0,
    this.taxLabel = 'GST',
    this.subtotal = 0,
    this.totalDiscount = 0,
    this.totalTax = 0,
    this.grandTotal = 0,
    this.amountPaid = 0,
    this.amountDue = 0,
    this.payments = const [],
    required this.invoiceDate,
    required this.dueDate,
    this.notes = '',
    this.termsText = '',
    this.linkedSalesOrderId = '',
    this.linkedPurchaseOrderId = '',
    this.linkedCreditNoteId = '',
    this.stockDeducted = false,
    this.createdBy = '',
    this.createdByName = '',
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isSales => invoiceType == InvoiceType.sales;
  bool get isPurchase => invoiceType == InvoiceType.purchase;

  String get partyName => isSales ? customerName : vendorName;
  String get partyId => isSales ? customerId : vendorId;

  String get statusLabel => switch (status) {
    InvoiceStatus.draft => 'Draft',
    InvoiceStatus.sent => 'Sent',
    InvoiceStatus.partiallyPaid => 'Partial',
    InvoiceStatus.paid => 'Paid',
    InvoiceStatus.overdue => 'Overdue',
    InvoiceStatus.cancelled => 'Cancelled',
    InvoiceStatus.refunded => 'Refunded',
  };

  bool get isDraft => status == InvoiceStatus.draft;
  bool get isPaid => status == InvoiceStatus.paid;
  bool get isOverdue => status == InvoiceStatus.overdue;
  bool get isCancelled => status == InvoiceStatus.cancelled;

  int get overdueDays {
    if (status == InvoiceStatus.paid || status == InvoiceStatus.cancelled)
      return 0;
    final now = DateTime.now();
    if (now.isAfter(dueDate)) return now.difference(dueDate).inDays;
    return 0;
  }

  static InvoiceType _typeFromString(String s) => switch (s) {
    'purchase' => InvoiceType.purchase,
    _ => InvoiceType.sales,
  };

  static String _typeToString(InvoiceType t) => switch (t) {
    InvoiceType.sales => 'sales',
    InvoiceType.purchase => 'purchase',
  };

  static InvoiceStatus _statusFromString(String s) => switch (s) {
    'sent' => InvoiceStatus.sent,
    'partiallyPaid' => InvoiceStatus.partiallyPaid,
    'paid' => InvoiceStatus.paid,
    'overdue' => InvoiceStatus.overdue,
    'cancelled' => InvoiceStatus.cancelled,
    'refunded' => InvoiceStatus.refunded,
    _ => InvoiceStatus.draft,
  };

  static String _statusToString(InvoiceStatus s) => switch (s) {
    InvoiceStatus.draft => 'draft',
    InvoiceStatus.sent => 'sent',
    InvoiceStatus.partiallyPaid => 'partiallyPaid',
    InvoiceStatus.paid => 'paid',
    InvoiceStatus.overdue => 'overdue',
    InvoiceStatus.cancelled => 'cancelled',
    InvoiceStatus.refunded => 'refunded',
  };

  factory InvoiceModel.fromMap(Map<String, dynamic> map, String docId) {
    List<InvoiceItem> items = [];
    if (map['items'] is List) {
      items = (map['items'] as List)
          .map((e) => InvoiceItem.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    }
    List<PaymentRecord> payments = [];
    if (map['payments'] is List) {
      payments = (map['payments'] as List)
          .map((e) => PaymentRecord.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    }
    return InvoiceModel(
      id: docId,
      invoiceType: _typeFromString(safeString(map['invoiceType'], 'sales')),
      invoiceNumber: safeString(map['invoiceNumber']),
      customerId: safeString(map['customerId']),
      customerName: safeString(map['customerName']),
      customerPhone: safeString(map['customerPhone']),
      customerAddress: safeString(map['customerAddress']),
      vendorId: safeString(map['vendorId']),
      vendorName: safeString(map['vendorName']),
      status: _statusFromString(safeString(map['status'], 'draft')),
      items: items,
      discountPercent: safeDouble(map['discountPercent']),
      discountAmount: safeDouble(map['discountAmount']),
      taxLabel: safeString(map['taxLabel'], 'GST'),
      subtotal: safeDouble(map['subtotal']),
      totalDiscount: safeDouble(map['totalDiscount']),
      totalTax: safeDouble(map['totalTax']),
      grandTotal: safeDouble(map['grandTotal']),
      amountPaid: safeDouble(map['amountPaid']),
      amountDue: safeDouble(map['amountDue']),
      payments: payments,
      invoiceDate: safeTimestamp(map['invoiceDate']),
      dueDate: safeTimestamp(map['dueDate']),
      notes: safeString(map['notes']),
      termsText: safeString(map['termsText']),
      linkedSalesOrderId: safeString(map['linkedSalesOrderId']),
      linkedPurchaseOrderId: safeString(map['linkedPurchaseOrderId']),
      linkedCreditNoteId: safeString(map['linkedCreditNoteId']),
      stockDeducted: map['stockDeducted'] == true,
      createdBy: safeString(map['createdBy']),
      createdByName: safeString(map['createdByName']),
      createdAt: safeTimestamp(map['createdAt']),
      updatedAt: safeTimestamp(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'invoiceType': _typeToString(invoiceType),
    'invoiceNumber': invoiceNumber,
    'customerId': customerId,
    'customerName': customerName,
    'customerPhone': customerPhone,
    'customerAddress': customerAddress,
    'vendorId': vendorId,
    'vendorName': vendorName,
    'status': _statusToString(status),
    'items': items.map((e) => e.toMap()).toList(),
    'discountPercent': discountPercent,
    'discountAmount': discountAmount,
    'taxLabel': taxLabel,
    'subtotal': subtotal,
    'totalDiscount': totalDiscount,
    'totalTax': totalTax,
    'grandTotal': grandTotal,
    'amountPaid': amountPaid,
    'amountDue': amountDue,
    'payments': payments.map((e) => e.toMap()).toList(),
    'invoiceDate': Timestamp.fromDate(invoiceDate),
    'dueDate': Timestamp.fromDate(dueDate),
    'notes': notes,
    'termsText': termsText,
    'linkedSalesOrderId': linkedSalesOrderId,
    'linkedPurchaseOrderId': linkedPurchaseOrderId,
    'linkedCreditNoteId': linkedCreditNoteId,
    'stockDeducted': stockDeducted,
    'createdBy': createdBy,
    'createdByName': createdByName,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  InvoiceModel copyWith({
    String? id,
    InvoiceType? invoiceType,
    String? invoiceNumber,
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    String? vendorId,
    String? vendorName,
    InvoiceStatus? status,
    List<InvoiceItem>? items,
    double? discountPercent,
    double? discountAmount,
    String? taxLabel,
    double? subtotal,
    double? totalDiscount,
    double? totalTax,
    double? grandTotal,
    double? amountPaid,
    double? amountDue,
    List<PaymentRecord>? payments,
    DateTime? invoiceDate,
    DateTime? dueDate,
    String? notes,
    String? termsText,
    String? linkedSalesOrderId,
    String? linkedPurchaseOrderId,
    String? linkedCreditNoteId,
    bool? stockDeducted,
    String? createdBy,
    String? createdByName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return InvoiceModel(
      id: id ?? this.id,
      invoiceType: invoiceType ?? this.invoiceType,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerAddress: customerAddress ?? this.customerAddress,
      vendorId: vendorId ?? this.vendorId,
      vendorName: vendorName ?? this.vendorName,
      status: status ?? this.status,
      items: items ?? this.items,
      discountPercent: discountPercent ?? this.discountPercent,
      discountAmount: discountAmount ?? this.discountAmount,
      taxLabel: taxLabel ?? this.taxLabel,
      subtotal: subtotal ?? this.subtotal,
      totalDiscount: totalDiscount ?? this.totalDiscount,
      totalTax: totalTax ?? this.totalTax,
      grandTotal: grandTotal ?? this.grandTotal,
      amountPaid: amountPaid ?? this.amountPaid,
      amountDue: amountDue ?? this.amountDue,
      payments: payments ?? this.payments,
      invoiceDate: invoiceDate ?? this.invoiceDate,
      dueDate: dueDate ?? this.dueDate,
      notes: notes ?? this.notes,
      termsText: termsText ?? this.termsText,
      linkedSalesOrderId: linkedSalesOrderId ?? this.linkedSalesOrderId,
      linkedPurchaseOrderId:
          linkedPurchaseOrderId ?? this.linkedPurchaseOrderId,
      linkedCreditNoteId: linkedCreditNoteId ?? this.linkedCreditNoteId,
      stockDeducted: stockDeducted ?? this.stockDeducted,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
