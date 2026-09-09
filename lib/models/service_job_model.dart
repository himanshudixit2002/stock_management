import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

/// Where a repair has got to.
enum ServiceJobStatus {
  received,
  diagnosed,
  inProgress,
  awaitingParts,
  resolved,
  closed,
  cancelled,
}

/// Whether the unit was still covered when it came in.
enum WarrantyState { inWarranty, outOfWarranty, unknown }

/// A part fitted during a repair.
///
/// [issued] is the stock fact and is separate from being listed: a part can be
/// planned during diagnosis and fitted days later, and only fitting moves stock.
/// Issuing is one-way — the flag is what stops the same part being taken out of
/// stock twice by two taps.
class ServicePart {
  final String productId;
  final String productName;
  final String unit;
  final int quantity;

  /// What the customer is charged per unit. Zero on a warranty repair, where
  /// the part still leaves stock but nobody pays for it.
  final double unitPrice;

  final bool chargeable;
  final bool issued;

  const ServicePart({
    required this.productId,
    this.productName = '',
    this.unit = '',
    this.quantity = 1,
    this.unitPrice = 0,
    this.chargeable = true,
    this.issued = false,
  });

  double get lineTotal => chargeable ? quantity * unitPrice : 0;

  factory ServicePart.fromMap(Map<String, dynamic> map) => ServicePart(
    productId: safeString(map['productId']),
    productName: safeString(map['productName']),
    unit: safeString(map['unit']),
    quantity: safeInt(map['quantity'], 1),
    unitPrice: safeDouble(map['unitPrice']),
    chargeable: safeBool(map['chargeable'], true),
    issued: safeBool(map['issued']),
  );

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'productName': productName,
    'unit': unit,
    'quantity': quantity,
    'unitPrice': unitPrice,
    'chargeable': chargeable,
    'issued': issued,
  };

  ServicePart copyWith({
    String? productId,
    String? productName,
    String? unit,
    int? quantity,
    double? unitPrice,
    bool? chargeable,
    bool? issued,
  }) => ServicePart(
    productId: productId ?? this.productId,
    productName: productName ?? this.productName,
    unit: unit ?? this.unit,
    quantity: quantity ?? this.quantity,
    unitPrice: unitPrice ?? this.unitPrice,
    chargeable: chargeable ?? this.chargeable,
    issued: issued ?? this.issued,
  );
}

/// Labour or any other charge on a job.
class ServiceCharge {
  final String label;
  final double amount;

  const ServiceCharge({required this.label, this.amount = 0});

  factory ServiceCharge.fromMap(Map<String, dynamic> map) => ServiceCharge(
    label: safeString(map['label']),
    amount: safeDouble(map['amount']),
  );

  Map<String, dynamic> toMap() => {'label': label, 'amount': amount};

  ServiceCharge copyWith({String? label, double? amount}) =>
      ServiceCharge(label: label ?? this.label, amount: amount ?? this.amount);
}

/// One unit, back from a customer, being repaired.
class ServiceJobModel {
  final String id;
  final String jobNumber;

  final String customerId;
  final String customerName;
  final String customerPhone;

  final String productId;
  final String productName;

  /// The serialised unit this job is about, when there is one. Serial tracking
  /// exists precisely so that a unit can be identified after it has been sold;
  /// this is what consumes it.
  final String serialId;
  final String serialNumber;

  /// Copied from the serial when the job is raised. Copied rather than read
  /// live, because a job's warranty position is a fact about the day it came in
  /// — extending a warranty later must not silently re-bill a closed repair.
  final DateTime? warrantyUntil;

  final ServiceJobStatus status;
  final String faultDescription;
  final String diagnosis;
  final String resolution;

  final List<ServicePart> parts;
  final List<ServiceCharge> charges;

  final String technicianId;
  final String technicianName;

  /// What the customer was told. Drives the overdue flag on the list.
  final DateTime? promisedAt;

  final DateTime receivedAt;
  final DateTime? resolvedAt;
  final DateTime? closedAt;
  final DateTime? partsIssuedAt;

  final String notes;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;

  ServiceJobModel({
    required this.id,
    this.jobNumber = '',
    this.customerId = '',
    this.customerName = '',
    this.customerPhone = '',
    this.productId = '',
    this.productName = '',
    this.serialId = '',
    this.serialNumber = '',
    this.warrantyUntil,
    this.status = ServiceJobStatus.received,
    this.faultDescription = '',
    this.diagnosis = '',
    this.resolution = '',
    this.parts = const [],
    this.charges = const [],
    this.technicianId = '',
    this.technicianName = '',
    this.promisedAt,
    required this.receivedAt,
    this.resolvedAt,
    this.closedAt,
    this.partsIssuedAt,
    this.notes = '',
    this.createdBy = '',
    this.createdByName = '',
    required this.createdAt,
    required this.updatedAt,
  });

  /// Warranty position as at [receivedAt] — the day the unit came in, not today.
  WarrantyState get warrantyState {
    final until = warrantyUntil;
    if (until == null) return WarrantyState.unknown;
    return receivedAt.isBefore(until)
        ? WarrantyState.inWarranty
        : WarrantyState.outOfWarranty;
  }

  bool get isUnderWarranty => warrantyState == WarrantyState.inWarranty;

  double get partsTotal => parts.fold(0.0, (acc, p) => acc + p.lineTotal);

  double get chargesTotal => charges.fold(0.0, (acc, c) => acc + c.amount);

  double get billableTotal => partsTotal + chargesTotal;

  int get partUnits => parts.fold(0, (acc, p) => acc + p.quantity);

  /// Parts listed but not yet taken out of stock.
  List<ServicePart> get unissuedParts =>
      parts.where((p) => !p.issued && p.quantity > 0).toList();

  bool get hasUnissuedParts => unissuedParts.isNotEmpty;

  bool get isOpen =>
      status != ServiceJobStatus.closed && status != ServiceJobStatus.cancelled;

  int get ageDays => (closedAt ?? DateTime.now()).difference(receivedAt).inDays;

  bool get isOverdue =>
      isOpen &&
      status != ServiceJobStatus.resolved &&
      promisedAt != null &&
      promisedAt!.isBefore(DateTime.now());

  bool get canEdit => isOpen;

  bool get canIssueParts => isOpen && hasUnissuedParts;

  bool get canResolve =>
      isOpen && status != ServiceJobStatus.resolved && !hasUnissuedParts;

  bool get canClose => status == ServiceJobStatus.resolved;

  bool get canCancel => isOpen && !parts.any((p) => p.issued);

  String get statusLabel => statusLabelOf(status);

  static String statusLabelOf(ServiceJobStatus s) => switch (s) {
    ServiceJobStatus.received => 'Received',
    ServiceJobStatus.diagnosed => 'Diagnosed',
    ServiceJobStatus.inProgress => 'In progress',
    ServiceJobStatus.awaitingParts => 'Awaiting parts',
    ServiceJobStatus.resolved => 'Resolved',
    ServiceJobStatus.closed => 'Closed',
    ServiceJobStatus.cancelled => 'Cancelled',
  };

  static ServiceJobStatus statusFromString(String s) => switch (s) {
    'diagnosed' => ServiceJobStatus.diagnosed,
    'inProgress' => ServiceJobStatus.inProgress,
    'awaitingParts' => ServiceJobStatus.awaitingParts,
    'resolved' => ServiceJobStatus.resolved,
    'closed' => ServiceJobStatus.closed,
    'cancelled' => ServiceJobStatus.cancelled,
    _ => ServiceJobStatus.received,
  };

  static String statusToString(ServiceJobStatus s) => s.name;

  static String warrantyLabelOf(WarrantyState w) => switch (w) {
    WarrantyState.inWarranty => 'In warranty',
    WarrantyState.outOfWarranty => 'Out of warranty',
    WarrantyState.unknown => 'Warranty unknown',
  };

  factory ServiceJobModel.fromMap(Map<String, dynamic> map, String docId) {
    final rawParts = map['parts'];
    final rawCharges = map['charges'];
    return ServiceJobModel(
      id: docId,
      jobNumber: safeString(map['jobNumber']),
      customerId: safeString(map['customerId']),
      customerName: safeString(map['customerName']),
      customerPhone: safeString(map['customerPhone']),
      productId: safeString(map['productId']),
      productName: safeString(map['productName']),
      serialId: safeString(map['serialId']),
      serialNumber: safeString(map['serialNumber']),
      warrantyUntil: map['warrantyUntil'] == null
          ? null
          : safeTimestamp(map['warrantyUntil']),
      status: statusFromString(safeString(map['status'], 'received')),
      faultDescription: safeString(map['faultDescription']),
      diagnosis: safeString(map['diagnosis']),
      resolution: safeString(map['resolution']),
      parts: rawParts is List
          ? rawParts
                .whereType<Map>()
                .map((e) => ServicePart.fromMap(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
      charges: rawCharges is List
          ? rawCharges
                .whereType<Map>()
                .map((e) => ServiceCharge.fromMap(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
      technicianId: safeString(map['technicianId']),
      technicianName: safeString(map['technicianName']),
      promisedAt: map['promisedAt'] == null
          ? null
          : safeTimestamp(map['promisedAt']),
      receivedAt: safeTimestamp(map['receivedAt']),
      resolvedAt: map['resolvedAt'] == null
          ? null
          : safeTimestamp(map['resolvedAt']),
      closedAt: map['closedAt'] == null ? null : safeTimestamp(map['closedAt']),
      partsIssuedAt: map['partsIssuedAt'] == null
          ? null
          : safeTimestamp(map['partsIssuedAt']),
      notes: safeString(map['notes']),
      createdBy: safeString(map['createdBy']),
      createdByName: safeString(map['createdByName']),
      createdAt: safeTimestamp(map['createdAt']),
      updatedAt: safeTimestamp(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'jobNumber': jobNumber,
    'customerId': customerId,
    'customerName': customerName,
    'customerPhone': customerPhone,
    'productId': productId,
    'productName': productName,
    'serialId': serialId,
    'serialNumber': serialNumber,
    if (warrantyUntil != null)
      'warrantyUntil': Timestamp.fromDate(warrantyUntil!),
    'status': statusToString(status),
    'faultDescription': faultDescription,
    'diagnosis': diagnosis,
    'resolution': resolution,
    'parts': parts.map((p) => p.toMap()).toList(),
    'charges': charges.map((c) => c.toMap()).toList(),
    'technicianId': technicianId,
    'technicianName': technicianName,
    if (promisedAt != null) 'promisedAt': Timestamp.fromDate(promisedAt!),
    'receivedAt': Timestamp.fromDate(receivedAt),
    if (resolvedAt != null) 'resolvedAt': Timestamp.fromDate(resolvedAt!),
    if (closedAt != null) 'closedAt': Timestamp.fromDate(closedAt!),
    if (partsIssuedAt != null)
      'partsIssuedAt': Timestamp.fromDate(partsIssuedAt!),
    'notes': notes,
    'billableTotal': billableTotal,
    'createdBy': createdBy,
    'createdByName': createdByName,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  ServiceJobModel copyWith({
    String? id,
    String? jobNumber,
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? productId,
    String? productName,
    String? serialId,
    String? serialNumber,
    DateTime? warrantyUntil,
    ServiceJobStatus? status,
    String? faultDescription,
    String? diagnosis,
    String? resolution,
    List<ServicePart>? parts,
    List<ServiceCharge>? charges,
    String? technicianId,
    String? technicianName,
    DateTime? promisedAt,
    DateTime? receivedAt,
    DateTime? resolvedAt,
    DateTime? closedAt,
    DateTime? partsIssuedAt,
    String? notes,
    String? createdBy,
    String? createdByName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ServiceJobModel(
    id: id ?? this.id,
    jobNumber: jobNumber ?? this.jobNumber,
    customerId: customerId ?? this.customerId,
    customerName: customerName ?? this.customerName,
    customerPhone: customerPhone ?? this.customerPhone,
    productId: productId ?? this.productId,
    productName: productName ?? this.productName,
    serialId: serialId ?? this.serialId,
    serialNumber: serialNumber ?? this.serialNumber,
    warrantyUntil: warrantyUntil ?? this.warrantyUntil,
    status: status ?? this.status,
    faultDescription: faultDescription ?? this.faultDescription,
    diagnosis: diagnosis ?? this.diagnosis,
    resolution: resolution ?? this.resolution,
    parts: parts ?? this.parts,
    charges: charges ?? this.charges,
    technicianId: technicianId ?? this.technicianId,
    technicianName: technicianName ?? this.technicianName,
    promisedAt: promisedAt ?? this.promisedAt,
    receivedAt: receivedAt ?? this.receivedAt,
    resolvedAt: resolvedAt ?? this.resolvedAt,
    closedAt: closedAt ?? this.closedAt,
    partsIssuedAt: partsIssuedAt ?? this.partsIssuedAt,
    notes: notes ?? this.notes,
    createdBy: createdBy ?? this.createdBy,
    createdByName: createdByName ?? this.createdByName,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
