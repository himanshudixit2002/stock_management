import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

/// Lifecycle of an internal request to buy.
///
/// Deliberately separate from a purchase order: asking for stock and committing
/// company money are different acts, and until now the only way to do the first
/// was to do the second.
enum RequisitionStatus { draft, submitted, approved, rejected, converted, cancelled }

/// How badly the requester needs it. Drives sorting on the approval queue.
enum RequisitionUrgency { low, normal, high, critical }

/// One requested product line.
class RequisitionLine {
  final String productId;
  final String productName;
  final String unit;
  final int quantity;

  /// What the requester expects it to cost per unit, for the approver's
  /// benefit. Not authoritative — the purchase order carries the real price.
  final double estimatedUnitCost;
  final String note;

  const RequisitionLine({
    required this.productId,
    this.productName = '',
    this.unit = '',
    required this.quantity,
    this.estimatedUnitCost = 0,
    this.note = '',
  });

  double get estimatedTotal => estimatedUnitCost * quantity;

  factory RequisitionLine.fromMap(Map<String, dynamic> map) => RequisitionLine(
    productId: safeString(map['productId']),
    productName: safeString(map['productName']),
    unit: safeString(map['unit']),
    quantity: safeInt(map['quantity']),
    estimatedUnitCost: safeDouble(map['estimatedUnitCost']),
    note: safeString(map['note']),
  );

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'productName': productName,
    'unit': unit,
    'quantity': quantity,
    'estimatedUnitCost': estimatedUnitCost,
    'note': note,
  };

  RequisitionLine copyWith({
    String? productId,
    String? productName,
    String? unit,
    int? quantity,
    double? estimatedUnitCost,
    String? note,
  }) => RequisitionLine(
    productId: productId ?? this.productId,
    productName: productName ?? this.productName,
    unit: unit ?? this.unit,
    quantity: quantity ?? this.quantity,
    estimatedUnitCost: estimatedUnitCost ?? this.estimatedUnitCost,
    note: note ?? this.note,
  );
}

/// A request to purchase, awaiting approval.
class RequisitionModel {
  final String id;
  final String referenceNumber;
  final String title;
  final RequisitionStatus status;
  final RequisitionUrgency urgency;
  final List<RequisitionLine> lines;

  /// Suggested supplier. Carried through to the purchase order on conversion.
  final String vendorId;
  final String vendorName;

  final String department;
  final String justification;
  final DateTime? neededBy;

  final String requestedBy;
  final String requestedByName;
  final DateTime? submittedAt;

  final String decidedBy;
  final String decidedByName;
  final DateTime? decidedAt;

  /// Why an approver rejected it. Required by the UI on rejection so a
  /// requester is never left guessing.
  final String decisionNote;

  /// The purchase order this became, once converted.
  final String purchaseOrderId;
  final String purchaseOrderNumber;

  final DateTime createdAt;
  final DateTime updatedAt;

  RequisitionModel({
    required this.id,
    this.referenceNumber = '',
    this.title = '',
    this.status = RequisitionStatus.draft,
    this.urgency = RequisitionUrgency.normal,
    this.lines = const [],
    this.vendorId = '',
    this.vendorName = '',
    this.department = '',
    this.justification = '',
    this.neededBy,
    this.requestedBy = '',
    this.requestedByName = '',
    this.submittedAt,
    this.decidedBy = '',
    this.decidedByName = '',
    this.decidedAt,
    this.decisionNote = '',
    this.purchaseOrderId = '',
    this.purchaseOrderNumber = '',
    required this.createdAt,
    required this.updatedAt,
  });

  double get estimatedTotal =>
      lines.fold(0.0, (acc, l) => acc + l.estimatedTotal);

  int get totalQuantity =>
      lines.fold(0, (acc, l) => acc + (l.quantity > 0 ? l.quantity : 0));

  bool get canEdit =>
      status == RequisitionStatus.draft || status == RequisitionStatus.rejected;

  bool get canSubmit =>
      canEdit && lines.isNotEmpty && totalQuantity > 0;

  bool get canDecide => status == RequisitionStatus.submitted;

  bool get canConvert =>
      status == RequisitionStatus.approved && purchaseOrderId.isEmpty;

  bool get canCancel =>
      status == RequisitionStatus.draft ||
      status == RequisitionStatus.submitted ||
      status == RequisitionStatus.approved;

  /// True when it has sat in the approval queue past [days] without a decision.
  bool isStale({int days = 3}) {
    if (status != RequisitionStatus.submitted || submittedAt == null) {
      return false;
    }
    return DateTime.now().difference(submittedAt!).inDays >= days;
  }

  String get statusLabel => statusLabelOf(status);

  static String statusLabelOf(RequisitionStatus s) => switch (s) {
    RequisitionStatus.draft => 'Draft',
    RequisitionStatus.submitted => 'Awaiting approval',
    RequisitionStatus.approved => 'Approved',
    RequisitionStatus.rejected => 'Rejected',
    RequisitionStatus.converted => 'Ordered',
    RequisitionStatus.cancelled => 'Cancelled',
  };

  static RequisitionStatus statusFromString(String s) => switch (s) {
    'submitted' => RequisitionStatus.submitted,
    'approved' => RequisitionStatus.approved,
    'rejected' => RequisitionStatus.rejected,
    'converted' => RequisitionStatus.converted,
    'cancelled' => RequisitionStatus.cancelled,
    _ => RequisitionStatus.draft,
  };

  static String statusToString(RequisitionStatus s) => switch (s) {
    RequisitionStatus.draft => 'draft',
    RequisitionStatus.submitted => 'submitted',
    RequisitionStatus.approved => 'approved',
    RequisitionStatus.rejected => 'rejected',
    RequisitionStatus.converted => 'converted',
    RequisitionStatus.cancelled => 'cancelled',
  };

  String get urgencyLabel => urgencyLabelOf(urgency);

  static String urgencyLabelOf(RequisitionUrgency u) => switch (u) {
    RequisitionUrgency.low => 'Low',
    RequisitionUrgency.normal => 'Normal',
    RequisitionUrgency.high => 'High',
    RequisitionUrgency.critical => 'Critical',
  };

  static RequisitionUrgency urgencyFromString(String s) => switch (s) {
    'low' => RequisitionUrgency.low,
    'high' => RequisitionUrgency.high,
    'critical' => RequisitionUrgency.critical,
    _ => RequisitionUrgency.normal,
  };

  static String urgencyToString(RequisitionUrgency u) => switch (u) {
    RequisitionUrgency.low => 'low',
    RequisitionUrgency.normal => 'normal',
    RequisitionUrgency.high => 'high',
    RequisitionUrgency.critical => 'critical',
  };

  factory RequisitionModel.fromMap(Map<String, dynamic> map, String docId) {
    final rawLines = map['lines'];
    return RequisitionModel(
      id: docId,
      referenceNumber: safeString(map['referenceNumber']),
      title: safeString(map['title']),
      status: statusFromString(safeString(map['status'], 'draft')),
      urgency: urgencyFromString(safeString(map['urgency'], 'normal')),
      lines: rawLines is List
          ? rawLines
                .whereType<Map>()
                .map(
                  (e) => RequisitionLine.fromMap(Map<String, dynamic>.from(e)),
                )
                .toList()
          : const [],
      vendorId: safeString(map['vendorId']),
      vendorName: safeString(map['vendorName']),
      department: safeString(map['department']),
      justification: safeString(map['justification']),
      neededBy: map['neededBy'] == null ? null : safeTimestamp(map['neededBy']),
      requestedBy: safeString(map['requestedBy']),
      requestedByName: safeString(map['requestedByName']),
      submittedAt: map['submittedAt'] == null
          ? null
          : safeTimestamp(map['submittedAt']),
      decidedBy: safeString(map['decidedBy']),
      decidedByName: safeString(map['decidedByName']),
      decidedAt: map['decidedAt'] == null
          ? null
          : safeTimestamp(map['decidedAt']),
      decisionNote: safeString(map['decisionNote']),
      purchaseOrderId: safeString(map['purchaseOrderId']),
      purchaseOrderNumber: safeString(map['purchaseOrderNumber']),
      createdAt: safeTimestamp(map['createdAt']),
      updatedAt: safeTimestamp(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'referenceNumber': referenceNumber,
    'title': title,
    'status': statusToString(status),
    'urgency': urgencyToString(urgency),
    'lines': lines.map((l) => l.toMap()).toList(),
    'vendorId': vendorId,
    'vendorName': vendorName,
    'department': department,
    'justification': justification,
    if (neededBy != null) 'neededBy': Timestamp.fromDate(neededBy!),
    'requestedBy': requestedBy,
    'requestedByName': requestedByName,
    if (submittedAt != null) 'submittedAt': Timestamp.fromDate(submittedAt!),
    'decidedBy': decidedBy,
    'decidedByName': decidedByName,
    if (decidedAt != null) 'decidedAt': Timestamp.fromDate(decidedAt!),
    'decisionNote': decisionNote,
    'purchaseOrderId': purchaseOrderId,
    'purchaseOrderNumber': purchaseOrderNumber,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  RequisitionModel copyWith({
    String? id,
    String? referenceNumber,
    String? title,
    RequisitionStatus? status,
    RequisitionUrgency? urgency,
    List<RequisitionLine>? lines,
    String? vendorId,
    String? vendorName,
    String? department,
    String? justification,
    DateTime? neededBy,
    String? requestedBy,
    String? requestedByName,
    DateTime? submittedAt,
    String? decidedBy,
    String? decidedByName,
    DateTime? decidedAt,
    String? decisionNote,
    String? purchaseOrderId,
    String? purchaseOrderNumber,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => RequisitionModel(
    id: id ?? this.id,
    referenceNumber: referenceNumber ?? this.referenceNumber,
    title: title ?? this.title,
    status: status ?? this.status,
    urgency: urgency ?? this.urgency,
    lines: lines ?? this.lines,
    vendorId: vendorId ?? this.vendorId,
    vendorName: vendorName ?? this.vendorName,
    department: department ?? this.department,
    justification: justification ?? this.justification,
    neededBy: neededBy ?? this.neededBy,
    requestedBy: requestedBy ?? this.requestedBy,
    requestedByName: requestedByName ?? this.requestedByName,
    submittedAt: submittedAt ?? this.submittedAt,
    decidedBy: decidedBy ?? this.decidedBy,
    decidedByName: decidedByName ?? this.decidedByName,
    decidedAt: decidedAt ?? this.decidedAt,
    decisionNote: decisionNote ?? this.decisionNote,
    purchaseOrderId: purchaseOrderId ?? this.purchaseOrderId,
    purchaseOrderNumber: purchaseOrderNumber ?? this.purchaseOrderNumber,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
