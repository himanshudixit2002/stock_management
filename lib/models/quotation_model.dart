import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

/// Lifecycle of a priced offer to a customer.
///
/// [expired] is stored rather than only computed, because a quote whose validity
/// has lapsed can still be honoured — a salesperson extends the date instead —
/// and treating "past its date" as identical to "declined" would lose the
/// difference between an offer nobody answered and one that was refused.
enum QuotationStatus { draft, sent, accepted, declined, expired, converted }

/// One priced line on a quotation.
class QuotationLine {
  final String productId;
  final String productName;
  final String unit;
  final int quantity;
  final double unitPrice;
  final double discountPercent;
  final double taxRate;

  const QuotationLine({
    required this.productId,
    this.productName = '',
    this.unit = '',
    this.quantity = 1,
    this.unitPrice = 0,
    this.discountPercent = 0,
    this.taxRate = 0,
  });

  double get gross => quantity * unitPrice;

  double get discountAmount => gross * (discountPercent / 100);

  double get taxable => gross - discountAmount;

  double get taxAmount => taxable * (taxRate / 100);

  double get total => taxable + taxAmount;

  factory QuotationLine.fromMap(Map<String, dynamic> map) => QuotationLine(
    productId: safeString(map['productId']),
    productName: safeString(map['productName']),
    unit: safeString(map['unit']),
    quantity: safeInt(map['quantity'], 1),
    unitPrice: safeDouble(map['unitPrice']),
    discountPercent: safeDouble(map['discountPercent']),
    taxRate: safeDouble(map['taxRate']),
  );

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'productName': productName,
    'unit': unit,
    'quantity': quantity,
    'unitPrice': unitPrice,
    'discountPercent': discountPercent,
    'taxRate': taxRate,
  };

  QuotationLine copyWith({
    String? productId,
    String? productName,
    String? unit,
    int? quantity,
    double? unitPrice,
    double? discountPercent,
    double? taxRate,
  }) => QuotationLine(
    productId: productId ?? this.productId,
    productName: productName ?? this.productName,
    unit: unit ?? this.unit,
    quantity: quantity ?? this.quantity,
    unitPrice: unitPrice ?? this.unitPrice,
    discountPercent: discountPercent ?? this.discountPercent,
    taxRate: taxRate ?? this.taxRate,
  );
}

/// A priced offer, before it is an order.
class QuotationModel {
  final String id;
  final String quoteNumber;
  final String customerId;
  final String customerName;
  final String customerPhone;
  final QuotationStatus status;
  final List<QuotationLine> lines;
  final String notes;
  final String termsText;

  /// The date the prices stop being promised. Null means open-ended.
  final DateTime? validUntil;

  final DateTime? sentAt;
  final DateTime? decidedAt;

  /// Why the customer said no, or which conditions they attached to a yes.
  final String decisionNote;

  /// Set once the quote becomes an order, so the same quote cannot be converted
  /// twice into two orders for one piece of work.
  final String convertedSalesOrderId;

  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;

  QuotationModel({
    required this.id,
    this.quoteNumber = '',
    this.customerId = '',
    this.customerName = '',
    this.customerPhone = '',
    this.status = QuotationStatus.draft,
    this.lines = const [],
    this.notes = '',
    this.termsText = '',
    this.validUntil,
    this.sentAt,
    this.decidedAt,
    this.decisionNote = '',
    this.convertedSalesOrderId = '',
    this.createdBy = '',
    this.createdByName = '',
    required this.createdAt,
    required this.updatedAt,
  });

  double get subtotal => lines.fold(0.0, (acc, l) => acc + l.gross);

  double get totalDiscount => lines.fold(0.0, (acc, l) => acc + l.discountAmount);

  double get totalTax => lines.fold(0.0, (acc, l) => acc + l.taxAmount);

  double get grandTotal => lines.fold(0.0, (acc, l) => acc + l.total);

  int get totalUnits =>
      lines.fold(0, (acc, l) => acc + (l.quantity > 0 ? l.quantity : 0));

  /// Past its validity date while still awaiting an answer.
  ///
  /// Kept separate from [status]: nothing sweeps the collection to re-stamp
  /// lapsed quotes, so the screens decide what to show from this and the writer
  /// stamps [QuotationStatus.expired] only when somebody acts on it.
  bool get hasLapsed =>
      status == QuotationStatus.sent &&
      validUntil != null &&
      validUntil!.isBefore(DateTime.now());

  /// How the quote should read to a user, lapse included.
  QuotationStatus get effectiveStatus =>
      hasLapsed ? QuotationStatus.expired : status;

  /// Days until the offer lapses; negative once it has.
  int? get daysToExpiry {
    final until = validUntil;
    if (until == null) return null;
    return until.difference(DateTime.now()).inDays;
  }

  bool get isOpen =>
      status == QuotationStatus.draft || status == QuotationStatus.sent;

  bool get canEdit =>
      status == QuotationStatus.draft || status == QuotationStatus.sent;

  bool get canSend => status == QuotationStatus.draft && lines.isNotEmpty;

  bool get canDecide =>
      status == QuotationStatus.sent || status == QuotationStatus.expired;

  /// A quote may only become an order once, and only after a yes.
  bool get canConvert =>
      status == QuotationStatus.accepted && convertedSalesOrderId.isEmpty;

  bool get canDelete => status == QuotationStatus.draft;

  String get statusLabel => statusLabelOf(effectiveStatus);

  static String statusLabelOf(QuotationStatus s) => switch (s) {
    QuotationStatus.draft => 'Draft',
    QuotationStatus.sent => 'Sent',
    QuotationStatus.accepted => 'Accepted',
    QuotationStatus.declined => 'Declined',
    QuotationStatus.expired => 'Expired',
    QuotationStatus.converted => 'Converted',
  };

  static QuotationStatus statusFromString(String s) => switch (s) {
    'sent' => QuotationStatus.sent,
    'accepted' => QuotationStatus.accepted,
    'declined' => QuotationStatus.declined,
    'expired' => QuotationStatus.expired,
    'converted' => QuotationStatus.converted,
    _ => QuotationStatus.draft,
  };

  static String statusToString(QuotationStatus s) => switch (s) {
    QuotationStatus.draft => 'draft',
    QuotationStatus.sent => 'sent',
    QuotationStatus.accepted => 'accepted',
    QuotationStatus.declined => 'declined',
    QuotationStatus.expired => 'expired',
    QuotationStatus.converted => 'converted',
  };

  factory QuotationModel.fromMap(Map<String, dynamic> map, String docId) {
    final rawLines = map['lines'];
    return QuotationModel(
      id: docId,
      quoteNumber: safeString(map['quoteNumber']),
      customerId: safeString(map['customerId']),
      customerName: safeString(map['customerName']),
      customerPhone: safeString(map['customerPhone']),
      status: statusFromString(safeString(map['status'], 'draft')),
      lines: rawLines is List
          ? rawLines
                .whereType<Map>()
                .map((e) => QuotationLine.fromMap(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
      notes: safeString(map['notes']),
      termsText: safeString(map['termsText']),
      validUntil: map['validUntil'] == null
          ? null
          : safeTimestamp(map['validUntil']),
      sentAt: map['sentAt'] == null ? null : safeTimestamp(map['sentAt']),
      decidedAt: map['decidedAt'] == null
          ? null
          : safeTimestamp(map['decidedAt']),
      decisionNote: safeString(map['decisionNote']),
      convertedSalesOrderId: safeString(map['convertedSalesOrderId']),
      createdBy: safeString(map['createdBy']),
      createdByName: safeString(map['createdByName']),
      createdAt: safeTimestamp(map['createdAt']),
      updatedAt: safeTimestamp(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'quoteNumber': quoteNumber,
    'customerId': customerId,
    'customerName': customerName,
    'customerPhone': customerPhone,
    'status': statusToString(status),
    'lines': lines.map((l) => l.toMap()).toList(),
    'notes': notes,
    'termsText': termsText,
    if (validUntil != null) 'validUntil': Timestamp.fromDate(validUntil!),
    if (sentAt != null) 'sentAt': Timestamp.fromDate(sentAt!),
    if (decidedAt != null) 'decidedAt': Timestamp.fromDate(decidedAt!),
    'decisionNote': decisionNote,
    'convertedSalesOrderId': convertedSalesOrderId,
    'createdBy': createdBy,
    'createdByName': createdByName,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
    // Denormalised so the list can sort and the pipeline header can sum without
    // rebuilding every line client-side.
    'grandTotal': grandTotal,
    'totalUnits': totalUnits,
  };

  QuotationModel copyWith({
    String? id,
    String? quoteNumber,
    String? customerId,
    String? customerName,
    String? customerPhone,
    QuotationStatus? status,
    List<QuotationLine>? lines,
    String? notes,
    String? termsText,
    DateTime? validUntil,
    DateTime? sentAt,
    DateTime? decidedAt,
    String? decisionNote,
    String? convertedSalesOrderId,
    String? createdBy,
    String? createdByName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => QuotationModel(
    id: id ?? this.id,
    quoteNumber: quoteNumber ?? this.quoteNumber,
    customerId: customerId ?? this.customerId,
    customerName: customerName ?? this.customerName,
    customerPhone: customerPhone ?? this.customerPhone,
    status: status ?? this.status,
    lines: lines ?? this.lines,
    notes: notes ?? this.notes,
    termsText: termsText ?? this.termsText,
    validUntil: validUntil ?? this.validUntil,
    sentAt: sentAt ?? this.sentAt,
    decidedAt: decidedAt ?? this.decidedAt,
    decisionNote: decisionNote ?? this.decisionNote,
    convertedSalesOrderId:
        convertedSalesOrderId ?? this.convertedSalesOrderId,
    createdBy: createdBy ?? this.createdBy,
    createdByName: createdByName ?? this.createdByName,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
