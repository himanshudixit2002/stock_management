import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

/// Where a shipment is in the pick-pack-ship sequence.
enum ShipmentStatus { draft, picking, packed, dispatched, delivered, cancelled }

/// One line being picked and packed.
///
/// Three quantities rather than one, because they are three different facts and
/// the gaps between them are the errors worth catching: what the order asked
/// for, what the picker found on the shelf, and what actually went in the box.
class ShipmentLine {
  final String productId;
  final String productName;
  final String unit;

  /// Index of the matching line on the sales order. Carried so dispatch can
  /// address the order's own lines without re-matching on product id — the same
  /// product may legitimately appear twice on one order.
  final int orderItemIndex;

  /// What the order line still owed when this shipment was raised.
  final int orderedQuantity;

  final int pickedQuantity;
  final int packedQuantity;

  /// Where the picker took it from.
  final String location;

  const ShipmentLine({
    required this.productId,
    this.productName = '',
    this.unit = '',
    this.orderItemIndex = -1,
    this.orderedQuantity = 0,
    this.pickedQuantity = 0,
    this.packedQuantity = 0,
    this.location = '',
  });

  /// Units the order asked for that are not yet on a pick list.
  int get shortPicked {
    final diff = orderedQuantity - pickedQuantity;
    return diff > 0 ? diff : 0;
  }

  bool get isFullyPicked =>
      orderedQuantity > 0 && pickedQuantity >= orderedQuantity;

  bool get isFullyPacked => packedQuantity >= pickedQuantity && pickedQuantity > 0;

  factory ShipmentLine.fromMap(Map<String, dynamic> map) => ShipmentLine(
    productId: safeString(map['productId']),
    productName: safeString(map['productName']),
    unit: safeString(map['unit']),
    orderItemIndex: safeInt(map['orderItemIndex'], -1),
    orderedQuantity: safeInt(map['orderedQuantity']),
    pickedQuantity: safeInt(map['pickedQuantity']),
    packedQuantity: safeInt(map['packedQuantity']),
    location: safeString(map['location']),
  );

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'productName': productName,
    'unit': unit,
    'orderItemIndex': orderItemIndex,
    'orderedQuantity': orderedQuantity,
    'pickedQuantity': pickedQuantity,
    'packedQuantity': packedQuantity,
    'location': location,
  };

  ShipmentLine copyWith({
    String? productId,
    String? productName,
    String? unit,
    int? orderItemIndex,
    int? orderedQuantity,
    int? pickedQuantity,
    int? packedQuantity,
    String? location,
  }) => ShipmentLine(
    productId: productId ?? this.productId,
    productName: productName ?? this.productName,
    unit: unit ?? this.unit,
    orderItemIndex: orderItemIndex ?? this.orderItemIndex,
    orderedQuantity: orderedQuantity ?? this.orderedQuantity,
    pickedQuantity: pickedQuantity ?? this.pickedQuantity,
    packedQuantity: packedQuantity ?? this.packedQuantity,
    location: location ?? this.location,
  );
}

/// A pick list that becomes a package that becomes a dispatch.
///
/// Deliberately holds no stock logic of its own. Dispatching one calls the sales
/// order dispatch path, which already consumes the order's reserved holds from
/// the locations they were held at; a second implementation of that would either
/// double-deduct stock or leave holds behind.
class ShipmentModel {
  final String id;
  final String shipmentNumber;
  final String salesOrderId;
  final String customerId;
  final String customerName;
  final ShipmentStatus status;
  final List<ShipmentLine> lines;

  /// Where the picker is working from. One shipment, one source location: a
  /// split pick is two shipments, which is also how it is physically packed.
  final String location;

  final int packageCount;
  final double weightKg;
  final String carrier;
  final String trackingReference;
  final String notes;

  final String pickedBy;
  final String pickedByName;
  final DateTime? pickedAt;
  final DateTime? packedAt;
  final DateTime? dispatchedAt;
  final DateTime? deliveredAt;
  final String dispatchedBy;
  final String dispatchedByName;

  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;

  ShipmentModel({
    required this.id,
    this.shipmentNumber = '',
    this.salesOrderId = '',
    this.customerId = '',
    this.customerName = '',
    this.status = ShipmentStatus.draft,
    this.lines = const [],
    this.location = '',
    this.packageCount = 1,
    this.weightKg = 0,
    this.carrier = '',
    this.trackingReference = '',
    this.notes = '',
    this.pickedBy = '',
    this.pickedByName = '',
    this.pickedAt,
    this.packedAt,
    this.dispatchedAt,
    this.deliveredAt,
    this.dispatchedBy = '',
    this.dispatchedByName = '',
    this.createdBy = '',
    this.createdByName = '',
    required this.createdAt,
    required this.updatedAt,
  });

  int get totalOrdered => lines.fold(0, (acc, l) => acc + l.orderedQuantity);

  int get totalPicked => lines.fold(0, (acc, l) => acc + l.pickedQuantity);

  int get totalPacked => lines.fold(0, (acc, l) => acc + l.packedQuantity);

  /// Share of the requested units that are on the pick list, 0..1.
  double get pickProgress {
    if (totalOrdered <= 0) return 0;
    final value = totalPicked / totalOrdered;
    return value > 1 ? 1 : value;
  }

  bool get isFullyPicked =>
      lines.isNotEmpty && lines.every((l) => l.isFullyPicked);

  /// True when the box holds less than the order asked for. Reported rather
  /// than blocked: a short shipment is a real thing that happens, and the
  /// remainder stays on the order for the next one.
  bool get isShort => totalPacked < totalOrdered;

  bool get canEdit =>
      status == ShipmentStatus.draft || status == ShipmentStatus.picking;

  bool get canPack =>
      (status == ShipmentStatus.draft || status == ShipmentStatus.picking) &&
      totalPicked > 0;

  bool get canDispatch => status == ShipmentStatus.packed && totalPacked > 0;

  bool get canDeliver => status == ShipmentStatus.dispatched;

  bool get canCancel =>
      status != ShipmentStatus.dispatched &&
      status != ShipmentStatus.delivered &&
      status != ShipmentStatus.cancelled;

  /// Units to dispatch, keyed by the sales order's own line index.
  ///
  /// Packed quantity is the truth here, not picked: what leaves the building is
  /// what somebody put in a box.
  Map<int, int> get dispatchByOrderIndex => {
    for (final line in lines)
      if (line.orderItemIndex >= 0 && line.packedQuantity > 0)
        line.orderItemIndex:
            (lines
                .where((l) => l.orderItemIndex == line.orderItemIndex)
                .fold(0, (acc, l) => acc + l.packedQuantity)),
  };

  String get statusLabel => statusLabelOf(status);

  static String statusLabelOf(ShipmentStatus s) => switch (s) {
    ShipmentStatus.draft => 'Draft',
    ShipmentStatus.picking => 'Picking',
    ShipmentStatus.packed => 'Packed',
    ShipmentStatus.dispatched => 'Dispatched',
    ShipmentStatus.delivered => 'Delivered',
    ShipmentStatus.cancelled => 'Cancelled',
  };

  static ShipmentStatus statusFromString(String s) => switch (s) {
    'picking' => ShipmentStatus.picking,
    'packed' => ShipmentStatus.packed,
    'dispatched' => ShipmentStatus.dispatched,
    'delivered' => ShipmentStatus.delivered,
    'cancelled' => ShipmentStatus.cancelled,
    _ => ShipmentStatus.draft,
  };

  static String statusToString(ShipmentStatus s) => switch (s) {
    ShipmentStatus.draft => 'draft',
    ShipmentStatus.picking => 'picking',
    ShipmentStatus.packed => 'packed',
    ShipmentStatus.dispatched => 'dispatched',
    ShipmentStatus.delivered => 'delivered',
    ShipmentStatus.cancelled => 'cancelled',
  };

  factory ShipmentModel.fromMap(Map<String, dynamic> map, String docId) {
    final rawLines = map['lines'];
    return ShipmentModel(
      id: docId,
      shipmentNumber: safeString(map['shipmentNumber']),
      salesOrderId: safeString(map['salesOrderId']),
      customerId: safeString(map['customerId']),
      customerName: safeString(map['customerName']),
      status: statusFromString(safeString(map['status'], 'draft')),
      lines: rawLines is List
          ? rawLines
                .whereType<Map>()
                .map((e) => ShipmentLine.fromMap(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
      location: safeString(map['location']),
      packageCount: safeInt(map['packageCount'], 1),
      weightKg: safeDouble(map['weightKg']),
      carrier: safeString(map['carrier']),
      trackingReference: safeString(map['trackingReference']),
      notes: safeString(map['notes']),
      pickedBy: safeString(map['pickedBy']),
      pickedByName: safeString(map['pickedByName']),
      pickedAt: map['pickedAt'] == null ? null : safeTimestamp(map['pickedAt']),
      packedAt: map['packedAt'] == null ? null : safeTimestamp(map['packedAt']),
      dispatchedAt: map['dispatchedAt'] == null
          ? null
          : safeTimestamp(map['dispatchedAt']),
      deliveredAt: map['deliveredAt'] == null
          ? null
          : safeTimestamp(map['deliveredAt']),
      dispatchedBy: safeString(map['dispatchedBy']),
      dispatchedByName: safeString(map['dispatchedByName']),
      createdBy: safeString(map['createdBy']),
      createdByName: safeString(map['createdByName']),
      createdAt: safeTimestamp(map['createdAt']),
      updatedAt: safeTimestamp(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'shipmentNumber': shipmentNumber,
    'salesOrderId': salesOrderId,
    'customerId': customerId,
    'customerName': customerName,
    'status': statusToString(status),
    'lines': lines.map((l) => l.toMap()).toList(),
    'location': location,
    'packageCount': packageCount,
    'weightKg': weightKg,
    'carrier': carrier,
    'trackingReference': trackingReference,
    'notes': notes,
    'pickedBy': pickedBy,
    'pickedByName': pickedByName,
    if (pickedAt != null) 'pickedAt': Timestamp.fromDate(pickedAt!),
    if (packedAt != null) 'packedAt': Timestamp.fromDate(packedAt!),
    if (dispatchedAt != null) 'dispatchedAt': Timestamp.fromDate(dispatchedAt!),
    if (deliveredAt != null) 'deliveredAt': Timestamp.fromDate(deliveredAt!),
    'dispatchedBy': dispatchedBy,
    'dispatchedByName': dispatchedByName,
    'createdBy': createdBy,
    'createdByName': createdByName,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  ShipmentModel copyWith({
    String? id,
    String? shipmentNumber,
    String? salesOrderId,
    String? customerId,
    String? customerName,
    ShipmentStatus? status,
    List<ShipmentLine>? lines,
    String? location,
    int? packageCount,
    double? weightKg,
    String? carrier,
    String? trackingReference,
    String? notes,
    String? pickedBy,
    String? pickedByName,
    DateTime? pickedAt,
    DateTime? packedAt,
    DateTime? dispatchedAt,
    DateTime? deliveredAt,
    String? dispatchedBy,
    String? dispatchedByName,
    String? createdBy,
    String? createdByName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ShipmentModel(
    id: id ?? this.id,
    shipmentNumber: shipmentNumber ?? this.shipmentNumber,
    salesOrderId: salesOrderId ?? this.salesOrderId,
    customerId: customerId ?? this.customerId,
    customerName: customerName ?? this.customerName,
    status: status ?? this.status,
    lines: lines ?? this.lines,
    location: location ?? this.location,
    packageCount: packageCount ?? this.packageCount,
    weightKg: weightKg ?? this.weightKg,
    carrier: carrier ?? this.carrier,
    trackingReference: trackingReference ?? this.trackingReference,
    notes: notes ?? this.notes,
    pickedBy: pickedBy ?? this.pickedBy,
    pickedByName: pickedByName ?? this.pickedByName,
    pickedAt: pickedAt ?? this.pickedAt,
    packedAt: packedAt ?? this.packedAt,
    dispatchedAt: dispatchedAt ?? this.dispatchedAt,
    deliveredAt: deliveredAt ?? this.deliveredAt,
    dispatchedBy: dispatchedBy ?? this.dispatchedBy,
    dispatchedByName: dispatchedByName ?? this.dispatchedByName,
    createdBy: createdBy ?? this.createdBy,
    createdByName: createdByName ?? this.createdByName,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
