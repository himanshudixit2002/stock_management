import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

/// Where an outsourced job has got to.
enum JobWorkStatus {
  draft,
  issued,
  partiallyReceived,
  completed,
  closed,
  cancelled,
}

/// One component sent out to the subcontractor.
///
/// Quantities are per finished unit, exactly as a bill of materials states them,
/// so a partial receipt consumes a proportional share without anybody dividing
/// by hand. [issuedQuantity] and [consumedQuantity] are absolute totals, and
/// their difference is what is physically sitting in somebody else's workshop.
class JobWorkComponent {
  final String productId;
  final String productName;
  final String unit;

  /// Units of this component needed per unit of output.
  final int quantityPerOutput;

  /// Total units actually sent out.
  final int issuedQuantity;

  /// Total units consumed by output received back.
  final int consumedQuantity;

  const JobWorkComponent({
    required this.productId,
    this.productName = '',
    this.unit = '',
    this.quantityPerOutput = 1,
    this.issuedQuantity = 0,
    this.consumedQuantity = 0,
  });

  /// Units still at the vendor.
  int get atVendorQuantity {
    final diff = issuedQuantity - consumedQuantity;
    return diff > 0 ? diff : 0;
  }

  factory JobWorkComponent.fromMap(Map<String, dynamic> map) =>
      JobWorkComponent(
        productId: safeString(map['productId']),
        productName: safeString(map['productName']),
        unit: safeString(map['unit']),
        quantityPerOutput: safeInt(map['quantityPerOutput'], 1),
        issuedQuantity: safeInt(map['issuedQuantity']),
        consumedQuantity: safeInt(map['consumedQuantity']),
      );

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'productName': productName,
    'unit': unit,
    'quantityPerOutput': quantityPerOutput,
    'issuedQuantity': issuedQuantity,
    'consumedQuantity': consumedQuantity,
  };

  JobWorkComponent copyWith({
    String? productId,
    String? productName,
    String? unit,
    int? quantityPerOutput,
    int? issuedQuantity,
    int? consumedQuantity,
  }) => JobWorkComponent(
    productId: productId ?? this.productId,
    productName: productName ?? this.productName,
    unit: unit ?? this.unit,
    quantityPerOutput: quantityPerOutput ?? this.quantityPerOutput,
    issuedQuantity: issuedQuantity ?? this.issuedQuantity,
    consumedQuantity: consumedQuantity ?? this.consumedQuantity,
  );
}

/// Work sent out: components to a vendor, finished goods back.
class JobWorkOrderModel {
  final String id;
  final String referenceNumber;

  final String vendorId;
  final String vendorName;

  /// The recipe this job was drafted from, when it came from one. Kept as a
  /// reference only — the components are copied onto the order, so editing the
  /// BOM afterwards cannot change what a vendor was already sent.
  final String bomId;

  final String outputProductId;
  final String outputProductName;
  final String outputUnit;

  /// Finished units the job is expected to produce.
  final int outputQuantity;

  /// Finished units actually received back so far.
  final int receivedQuantity;

  final List<JobWorkComponent> components;

  /// What the subcontractor charges per finished unit.
  final double jobChargePerUnit;

  /// Freight, packing and anything else that is not per unit, for the whole job.
  final double additionalCharges;

  /// Where components leave from, and where finished goods land.
  final String issueLocation;
  final String receiveLocation;

  final JobWorkStatus status;

  /// When true, receiving writes the computed cost onto the output product and
  /// records a price history row — the same treatment a landed cost sheet gives
  /// a receipt.
  final bool updateOutputCost;

  final DateTime? expectedAt;
  final DateTime? issuedAt;
  final DateTime? lastReceiptAt;
  final DateTime? closedAt;
  final String issuedBy;
  final String issuedByName;
  final String notes;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;

  JobWorkOrderModel({
    required this.id,
    this.referenceNumber = '',
    this.vendorId = '',
    this.vendorName = '',
    this.bomId = '',
    this.outputProductId = '',
    this.outputProductName = '',
    this.outputUnit = '',
    this.outputQuantity = 0,
    this.receivedQuantity = 0,
    this.components = const [],
    this.jobChargePerUnit = 0,
    this.additionalCharges = 0,
    this.issueLocation = '',
    this.receiveLocation = '',
    this.status = JobWorkStatus.draft,
    this.updateOutputCost = false,
    this.expectedAt,
    this.issuedAt,
    this.lastReceiptAt,
    this.closedAt,
    this.issuedBy = '',
    this.issuedByName = '',
    this.notes = '',
    this.createdBy = '',
    this.createdByName = '',
    required this.createdAt,
    required this.updatedAt,
  });

  /// What issuing the whole job takes out of the source location.
  Map<String, int> get issueQuantities => _perProduct(outputQuantity);

  /// What receiving [units] of output consumes from the vendor's bucket.
  Map<String, int> consumptionFor(int units) => _perProduct(units);

  /// Component demand for [units] of output, netted per product.
  ///
  /// Netted rather than keyed straight off the lines, because one product can
  /// legitimately appear on two component lines — and a map comprehension would
  /// keep only the last of them, quietly issuing or consuming too little.
  Map<String, int> _perProduct(int units) {
    if (units <= 0) return const {};
    final demand = <String, int>{};
    for (final c in components) {
      if (c.quantityPerOutput <= 0 || c.productId.isEmpty) continue;
      demand[c.productId] =
          (demand[c.productId] ?? 0) + (c.quantityPerOutput * units);
    }
    return demand;
  }

  /// What one component line contributes for [units] of output. Used to update
  /// the lines themselves, which [_perProduct] cannot do once it has netted
  /// two lines of the same product together.
  int lineQuantityFor(JobWorkComponent component, int units) =>
      component.quantityPerOutput > 0 && units > 0
      ? component.quantityPerOutput * units
      : 0;

  int get remainingOutput {
    final diff = outputQuantity - receivedQuantity;
    return diff > 0 ? diff : 0;
  }

  int get componentUnitsAtVendor =>
      components.fold(0, (acc, c) => acc + c.atVendorQuantity);

  int get componentUnitsIssued =>
      components.fold(0, (acc, c) => acc + c.issuedQuantity);

  /// Total the vendor is owed for the units received so far.
  double get chargesIncurred =>
      (jobChargePerUnit * receivedQuantity) +
      (receivedQuantity > 0 ? additionalCharges : 0);

  /// The whole job's charge if it completes as planned.
  double get chargesPlanned =>
      (jobChargePerUnit * outputQuantity) + additionalCharges;

  /// Conversion charge attributable to one finished unit.
  double get chargePerOutputUnit {
    if (outputQuantity <= 0) return jobChargePerUnit;
    return jobChargePerUnit + (additionalCharges / outputQuantity);
  }

  bool get isOut =>
      status == JobWorkStatus.issued ||
      status == JobWorkStatus.partiallyReceived;

  bool get canEdit => status == JobWorkStatus.draft;

  bool get canIssue =>
      status == JobWorkStatus.draft &&
      components.isNotEmpty &&
      outputQuantity > 0 &&
      outputProductId.isNotEmpty;

  bool get canReceive => isOut && remainingOutput > 0;

  /// Closing settles a job that will never finish: whatever is still at the
  /// vendor is returned to the shelf rather than left in limbo.
  bool get canClose => isOut;

  bool get canCancel => status == JobWorkStatus.draft;

  bool get isOverdue =>
      isOut && expectedAt != null && expectedAt!.isBefore(DateTime.now());

  int? get daysOut {
    if (!isOut || issuedAt == null) return null;
    return DateTime.now().difference(issuedAt!).inDays;
  }

  String get statusLabel => statusLabelOf(status);

  static String statusLabelOf(JobWorkStatus s) => switch (s) {
    JobWorkStatus.draft => 'Draft',
    JobWorkStatus.issued => 'At vendor',
    JobWorkStatus.partiallyReceived => 'Part received',
    JobWorkStatus.completed => 'Completed',
    JobWorkStatus.closed => 'Closed short',
    JobWorkStatus.cancelled => 'Cancelled',
  };

  static JobWorkStatus statusFromString(String s) => switch (s) {
    'issued' => JobWorkStatus.issued,
    'partiallyReceived' => JobWorkStatus.partiallyReceived,
    'completed' => JobWorkStatus.completed,
    'closed' => JobWorkStatus.closed,
    'cancelled' => JobWorkStatus.cancelled,
    _ => JobWorkStatus.draft,
  };

  static String statusToString(JobWorkStatus s) => s.name;

  factory JobWorkOrderModel.fromMap(Map<String, dynamic> map, String docId) {
    final rawComponents = map['components'];
    return JobWorkOrderModel(
      id: docId,
      referenceNumber: safeString(map['referenceNumber']),
      vendorId: safeString(map['vendorId']),
      vendorName: safeString(map['vendorName']),
      bomId: safeString(map['bomId']),
      outputProductId: safeString(map['outputProductId']),
      outputProductName: safeString(map['outputProductName']),
      outputUnit: safeString(map['outputUnit']),
      outputQuantity: safeInt(map['outputQuantity']),
      receivedQuantity: safeInt(map['receivedQuantity']),
      components: rawComponents is List
          ? rawComponents
                .whereType<Map>()
                .map(
                  (e) => JobWorkComponent.fromMap(Map<String, dynamic>.from(e)),
                )
                .toList()
          : const [],
      jobChargePerUnit: safeDouble(map['jobChargePerUnit']),
      additionalCharges: safeDouble(map['additionalCharges']),
      issueLocation: safeString(map['issueLocation']),
      receiveLocation: safeString(map['receiveLocation']),
      status: statusFromString(safeString(map['status'], 'draft')),
      updateOutputCost: safeBool(map['updateOutputCost']),
      expectedAt: map['expectedAt'] == null
          ? null
          : safeTimestamp(map['expectedAt']),
      issuedAt: map['issuedAt'] == null ? null : safeTimestamp(map['issuedAt']),
      lastReceiptAt: map['lastReceiptAt'] == null
          ? null
          : safeTimestamp(map['lastReceiptAt']),
      closedAt: map['closedAt'] == null ? null : safeTimestamp(map['closedAt']),
      issuedBy: safeString(map['issuedBy']),
      issuedByName: safeString(map['issuedByName']),
      notes: safeString(map['notes']),
      createdBy: safeString(map['createdBy']),
      createdByName: safeString(map['createdByName']),
      createdAt: safeTimestamp(map['createdAt']),
      updatedAt: safeTimestamp(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'referenceNumber': referenceNumber,
    'vendorId': vendorId,
    'vendorName': vendorName,
    'bomId': bomId,
    'outputProductId': outputProductId,
    'outputProductName': outputProductName,
    'outputUnit': outputUnit,
    'outputQuantity': outputQuantity,
    'receivedQuantity': receivedQuantity,
    'components': components.map((c) => c.toMap()).toList(),
    'jobChargePerUnit': jobChargePerUnit,
    'additionalCharges': additionalCharges,
    'issueLocation': issueLocation,
    'receiveLocation': receiveLocation,
    'status': statusToString(status),
    'updateOutputCost': updateOutputCost,
    if (expectedAt != null) 'expectedAt': Timestamp.fromDate(expectedAt!),
    if (issuedAt != null) 'issuedAt': Timestamp.fromDate(issuedAt!),
    if (lastReceiptAt != null)
      'lastReceiptAt': Timestamp.fromDate(lastReceiptAt!),
    if (closedAt != null) 'closedAt': Timestamp.fromDate(closedAt!),
    'issuedBy': issuedBy,
    'issuedByName': issuedByName,
    'notes': notes,
    'createdBy': createdBy,
    'createdByName': createdByName,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  JobWorkOrderModel copyWith({
    String? id,
    String? referenceNumber,
    String? vendorId,
    String? vendorName,
    String? bomId,
    String? outputProductId,
    String? outputProductName,
    String? outputUnit,
    int? outputQuantity,
    int? receivedQuantity,
    List<JobWorkComponent>? components,
    double? jobChargePerUnit,
    double? additionalCharges,
    String? issueLocation,
    String? receiveLocation,
    JobWorkStatus? status,
    bool? updateOutputCost,
    DateTime? expectedAt,
    DateTime? issuedAt,
    DateTime? lastReceiptAt,
    DateTime? closedAt,
    String? issuedBy,
    String? issuedByName,
    String? notes,
    String? createdBy,
    String? createdByName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => JobWorkOrderModel(
    id: id ?? this.id,
    referenceNumber: referenceNumber ?? this.referenceNumber,
    vendorId: vendorId ?? this.vendorId,
    vendorName: vendorName ?? this.vendorName,
    bomId: bomId ?? this.bomId,
    outputProductId: outputProductId ?? this.outputProductId,
    outputProductName: outputProductName ?? this.outputProductName,
    outputUnit: outputUnit ?? this.outputUnit,
    outputQuantity: outputQuantity ?? this.outputQuantity,
    receivedQuantity: receivedQuantity ?? this.receivedQuantity,
    components: components ?? this.components,
    jobChargePerUnit: jobChargePerUnit ?? this.jobChargePerUnit,
    additionalCharges: additionalCharges ?? this.additionalCharges,
    issueLocation: issueLocation ?? this.issueLocation,
    receiveLocation: receiveLocation ?? this.receiveLocation,
    status: status ?? this.status,
    updateOutputCost: updateOutputCost ?? this.updateOutputCost,
    expectedAt: expectedAt ?? this.expectedAt,
    issuedAt: issuedAt ?? this.issuedAt,
    lastReceiptAt: lastReceiptAt ?? this.lastReceiptAt,
    closedAt: closedAt ?? this.closedAt,
    issuedBy: issuedBy ?? this.issuedBy,
    issuedByName: issuedByName ?? this.issuedByName,
    notes: notes ?? this.notes,
    createdBy: createdBy ?? this.createdBy,
    createdByName: createdByName ?? this.createdByName,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
