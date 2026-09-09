import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

/// How a charge is spread across the lines of a receipt.
enum AllocationBasis {
  /// Proportional to each line's extended value. The default, and the right
  /// answer for duty and insurance.
  value,

  /// Proportional to units received. The right answer for handling.
  quantity,

  /// Equal share per line. The right answer for per-line paperwork fees.
  equal,
}

/// Lifecycle of a landed-cost sheet.
enum LandedCostStatus { draft, applied, reversed }

/// One charge incurred bringing a shipment in.
class LandedCostCharge {
  final String label;
  final double amount;
  final AllocationBasis basis;
  final String reference;

  const LandedCostCharge({
    required this.label,
    required this.amount,
    this.basis = AllocationBasis.value,
    this.reference = '',
  });

  factory LandedCostCharge.fromMap(Map<String, dynamic> map) =>
      LandedCostCharge(
        label: safeString(map['label']),
        amount: safeDouble(map['amount']),
        basis: basisFromString(safeString(map['basis'], 'value')),
        reference: safeString(map['reference']),
      );

  Map<String, dynamic> toMap() => {
    'label': label,
    'amount': amount,
    'basis': basisToString(basis),
    'reference': reference,
  };

  LandedCostCharge copyWith({
    String? label,
    double? amount,
    AllocationBasis? basis,
    String? reference,
  }) => LandedCostCharge(
    label: label ?? this.label,
    amount: amount ?? this.amount,
    basis: basis ?? this.basis,
    reference: reference ?? this.reference,
  );

  static AllocationBasis basisFromString(String s) => switch (s) {
    'quantity' => AllocationBasis.quantity,
    'equal' => AllocationBasis.equal,
    _ => AllocationBasis.value,
  };

  static String basisToString(AllocationBasis b) => switch (b) {
    AllocationBasis.value => 'value',
    AllocationBasis.quantity => 'quantity',
    AllocationBasis.equal => 'equal',
  };

  static String basisLabelOf(AllocationBasis b) => switch (b) {
    AllocationBasis.value => 'By line value',
    AllocationBasis.quantity => 'By quantity',
    AllocationBasis.equal => 'Split equally',
  };

  String get basisLabel => basisLabelOf(basis);
}

/// One receipt line a sheet allocates onto.
class LandedCostLine {
  final String productId;
  final String productName;
  final int quantity;

  /// What the supplier charged per unit, before landed costs.
  final double baseUnitCost;

  /// The share of the sheet's charges assigned to this line, in total (not per
  /// unit). Computed by the allocator and stored so an applied sheet stays
  /// auditable even if the charges are later edited.
  final double allocatedAmount;

  /// The product's cost price before this sheet was applied, so a reversal can
  /// put it back exactly.
  final double previousUnitCost;

  const LandedCostLine({
    required this.productId,
    this.productName = '',
    required this.quantity,
    this.baseUnitCost = 0,
    this.allocatedAmount = 0,
    this.previousUnitCost = 0,
  });

  double get baseValue => baseUnitCost * quantity;

  /// The per-unit cost once this line's share of the charges is added.
  double get landedUnitCost {
    if (quantity <= 0) return baseUnitCost;
    return baseUnitCost + allocatedAmount / quantity;
  }

  /// How much the unit cost moved, as a percentage of the base cost.
  double get upliftPercent {
    if (baseUnitCost <= 0) return 0;
    return (landedUnitCost - baseUnitCost) / baseUnitCost * 100;
  }

  factory LandedCostLine.fromMap(Map<String, dynamic> map) => LandedCostLine(
    productId: safeString(map['productId']),
    productName: safeString(map['productName']),
    quantity: safeInt(map['quantity']),
    baseUnitCost: safeDouble(map['baseUnitCost']),
    allocatedAmount: safeDouble(map['allocatedAmount']),
    previousUnitCost: safeDouble(map['previousUnitCost']),
  );

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'productName': productName,
    'quantity': quantity,
    'baseUnitCost': baseUnitCost,
    'allocatedAmount': allocatedAmount,
    'previousUnitCost': previousUnitCost,
  };

  LandedCostLine copyWith({
    String? productId,
    String? productName,
    int? quantity,
    double? baseUnitCost,
    double? allocatedAmount,
    double? previousUnitCost,
  }) => LandedCostLine(
    productId: productId ?? this.productId,
    productName: productName ?? this.productName,
    quantity: quantity ?? this.quantity,
    baseUnitCost: baseUnitCost ?? this.baseUnitCost,
    allocatedAmount: allocatedAmount ?? this.allocatedAmount,
    previousUnitCost: previousUnitCost ?? this.previousUnitCost,
  );
}

/// Freight, duty and handling attached to a received shipment, and the effect
/// they had on each product's cost price.
class LandedCostModel {
  final String id;
  final String referenceNumber;

  /// The purchase order this sheet costs. Optional: a sheet can be raised for
  /// a receipt that was never ordered through the app.
  final String purchaseOrderId;
  final String purchaseOrderNumber;
  final String vendorId;
  final String vendorName;

  final LandedCostStatus status;
  final List<LandedCostCharge> charges;
  final List<LandedCostLine> lines;
  final String notes;

  final DateTime shipmentDate;
  final String appliedBy;
  final String appliedByName;
  final DateTime? appliedAt;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;

  LandedCostModel({
    required this.id,
    this.referenceNumber = '',
    this.purchaseOrderId = '',
    this.purchaseOrderNumber = '',
    this.vendorId = '',
    this.vendorName = '',
    this.status = LandedCostStatus.draft,
    this.charges = const [],
    this.lines = const [],
    this.notes = '',
    required this.shipmentDate,
    this.appliedBy = '',
    this.appliedByName = '',
    this.appliedAt,
    this.createdBy = '',
    this.createdByName = '',
    required this.createdAt,
    required this.updatedAt,
  });

  double get totalCharges => charges.fold(0.0, (acc, c) => acc + c.amount);

  double get baseValue => lines.fold(0.0, (acc, l) => acc + l.baseValue);

  double get landedValue => baseValue + totalCharges;

  int get totalQuantity =>
      lines.fold(0, (acc, l) => acc + (l.quantity > 0 ? l.quantity : 0));

  /// Charges as a percentage of the goods value — the single number that says
  /// whether a shipment was expensive to land.
  double get upliftPercent {
    if (baseValue <= 0) return 0;
    return totalCharges / baseValue * 100;
  }

  bool get canApply =>
      status == LandedCostStatus.draft &&
      lines.isNotEmpty &&
      totalCharges > 0 &&
      baseValue > 0;

  bool get canReverse => status == LandedCostStatus.applied;

  bool get canEdit => status == LandedCostStatus.draft;

  String get statusLabel => switch (status) {
    LandedCostStatus.draft => 'Draft',
    LandedCostStatus.applied => 'Applied',
    LandedCostStatus.reversed => 'Reversed',
  };

  static LandedCostStatus statusFromString(String s) => switch (s) {
    'applied' => LandedCostStatus.applied,
    'reversed' => LandedCostStatus.reversed,
    _ => LandedCostStatus.draft,
  };

  static String statusToString(LandedCostStatus s) => switch (s) {
    LandedCostStatus.draft => 'draft',
    LandedCostStatus.applied => 'applied',
    LandedCostStatus.reversed => 'reversed',
  };

  factory LandedCostModel.fromMap(Map<String, dynamic> map, String docId) {
    final rawCharges = map['charges'];
    final rawLines = map['lines'];
    return LandedCostModel(
      id: docId,
      referenceNumber: safeString(map['referenceNumber']),
      purchaseOrderId: safeString(map['purchaseOrderId']),
      purchaseOrderNumber: safeString(map['purchaseOrderNumber']),
      vendorId: safeString(map['vendorId']),
      vendorName: safeString(map['vendorName']),
      status: statusFromString(safeString(map['status'], 'draft')),
      charges: rawCharges is List
          ? rawCharges
                .whereType<Map>()
                .map(
                  (e) => LandedCostCharge.fromMap(Map<String, dynamic>.from(e)),
                )
                .toList()
          : const [],
      lines: rawLines is List
          ? rawLines
                .whereType<Map>()
                .map(
                  (e) => LandedCostLine.fromMap(Map<String, dynamic>.from(e)),
                )
                .toList()
          : const [],
      notes: safeString(map['notes']),
      shipmentDate: safeTimestamp(map['shipmentDate']),
      appliedBy: safeString(map['appliedBy']),
      appliedByName: safeString(map['appliedByName']),
      appliedAt: map['appliedAt'] == null ? null : safeTimestamp(map['appliedAt']),
      createdBy: safeString(map['createdBy']),
      createdByName: safeString(map['createdByName']),
      createdAt: safeTimestamp(map['createdAt']),
      updatedAt: safeTimestamp(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'referenceNumber': referenceNumber,
    'purchaseOrderId': purchaseOrderId,
    'purchaseOrderNumber': purchaseOrderNumber,
    'vendorId': vendorId,
    'vendorName': vendorName,
    'status': statusToString(status),
    'charges': charges.map((c) => c.toMap()).toList(),
    'lines': lines.map((l) => l.toMap()).toList(),
    'notes': notes,
    'shipmentDate': Timestamp.fromDate(shipmentDate),
    'appliedBy': appliedBy,
    'appliedByName': appliedByName,
    if (appliedAt != null) 'appliedAt': Timestamp.fromDate(appliedAt!),
    'createdBy': createdBy,
    'createdByName': createdByName,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  LandedCostModel copyWith({
    String? id,
    String? referenceNumber,
    String? purchaseOrderId,
    String? purchaseOrderNumber,
    String? vendorId,
    String? vendorName,
    LandedCostStatus? status,
    List<LandedCostCharge>? charges,
    List<LandedCostLine>? lines,
    String? notes,
    DateTime? shipmentDate,
    String? appliedBy,
    String? appliedByName,
    DateTime? appliedAt,
    String? createdBy,
    String? createdByName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => LandedCostModel(
    id: id ?? this.id,
    referenceNumber: referenceNumber ?? this.referenceNumber,
    purchaseOrderId: purchaseOrderId ?? this.purchaseOrderId,
    purchaseOrderNumber: purchaseOrderNumber ?? this.purchaseOrderNumber,
    vendorId: vendorId ?? this.vendorId,
    vendorName: vendorName ?? this.vendorName,
    status: status ?? this.status,
    charges: charges ?? this.charges,
    lines: lines ?? this.lines,
    notes: notes ?? this.notes,
    shipmentDate: shipmentDate ?? this.shipmentDate,
    appliedBy: appliedBy ?? this.appliedBy,
    appliedByName: appliedByName ?? this.appliedByName,
    appliedAt: appliedAt ?? this.appliedAt,
    createdBy: createdBy ?? this.createdBy,
    createdByName: createdByName ?? this.createdByName,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
