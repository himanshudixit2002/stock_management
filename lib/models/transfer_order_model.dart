import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

/// Lifecycle of a transfer between two locations.
///
/// The state that matters is [dispatched]: stock has left the source but has
/// not arrived, so it belongs to neither location. The instant `transferStock`
/// path has no way to express that, which is why moving stock has always had to
/// be recorded on the day it landed rather than the day it left.
enum TransferOrderStatus { draft, dispatched, received, cancelled }

/// One product line on a transfer order.
class TransferOrderLine {
  final String productId;
  final String productName;
  final String unit;

  /// What the order asks to move.
  final int quantity;

  /// What actually left the source. Zero until dispatch.
  final int dispatchedQuantity;

  /// What actually arrived. May be less than [dispatchedQuantity] — the
  /// difference is the shortage, which is reported rather than silently
  /// absorbed.
  final int receivedQuantity;

  const TransferOrderLine({
    required this.productId,
    this.productName = '',
    this.unit = '',
    required this.quantity,
    this.dispatchedQuantity = 0,
    this.receivedQuantity = 0,
  });

  /// Units still on the truck: dispatched but not yet received.
  int get inTransitQuantity {
    final diff = dispatchedQuantity - receivedQuantity;
    return diff > 0 ? diff : 0;
  }

  factory TransferOrderLine.fromMap(Map<String, dynamic> map) =>
      TransferOrderLine(
        productId: safeString(map['productId']),
        productName: safeString(map['productName']),
        unit: safeString(map['unit']),
        quantity: safeInt(map['quantity']),
        dispatchedQuantity: safeInt(map['dispatchedQuantity']),
        receivedQuantity: safeInt(map['receivedQuantity']),
      );

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'productName': productName,
    'unit': unit,
    'quantity': quantity,
    'dispatchedQuantity': dispatchedQuantity,
    'receivedQuantity': receivedQuantity,
  };

  TransferOrderLine copyWith({
    String? productId,
    String? productName,
    String? unit,
    int? quantity,
    int? dispatchedQuantity,
    int? receivedQuantity,
  }) => TransferOrderLine(
    productId: productId ?? this.productId,
    productName: productName ?? this.productName,
    unit: unit ?? this.unit,
    quantity: quantity ?? this.quantity,
    dispatchedQuantity: dispatchedQuantity ?? this.dispatchedQuantity,
    receivedQuantity: receivedQuantity ?? this.receivedQuantity,
  );
}

/// A planned movement of stock from one location to another.
class TransferOrderModel {
  final String id;
  final String referenceNumber;
  final String fromLocation;
  final String toLocation;
  final TransferOrderStatus status;
  final List<TransferOrderLine> lines;
  final String notes;

  /// Free text: carrier, vehicle number, docket — whatever the workspace uses
  /// to chase a shipment that has not arrived.
  final String carrier;
  final String trackingReference;

  final DateTime? expectedAt;
  final DateTime? dispatchedAt;
  final DateTime? receivedAt;
  final String dispatchedBy;
  final String dispatchedByName;
  final String receivedBy;
  final String receivedByName;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;

  TransferOrderModel({
    required this.id,
    this.referenceNumber = '',
    required this.fromLocation,
    required this.toLocation,
    this.status = TransferOrderStatus.draft,
    this.lines = const [],
    this.notes = '',
    this.carrier = '',
    this.trackingReference = '',
    this.expectedAt,
    this.dispatchedAt,
    this.receivedAt,
    this.dispatchedBy = '',
    this.dispatchedByName = '',
    this.receivedBy = '',
    this.receivedByName = '',
    this.createdBy = '',
    this.createdByName = '',
    required this.createdAt,
    required this.updatedAt,
  });

  int get totalQuantity =>
      lines.fold(0, (acc, l) => acc + (l.quantity > 0 ? l.quantity : 0));

  int get totalDispatched => lines.fold(0, (acc, l) => acc + l.dispatchedQuantity);

  int get totalReceived => lines.fold(0, (acc, l) => acc + l.receivedQuantity);

  int get totalInTransit => lines.fold(0, (acc, l) => acc + l.inTransitQuantity);

  bool get canDispatch =>
      status == TransferOrderStatus.draft && lines.isNotEmpty && totalQuantity > 0;

  bool get canReceive =>
      status == TransferOrderStatus.dispatched && totalInTransit > 0;

  bool get canCancel =>
      status == TransferOrderStatus.draft ||
      (status == TransferOrderStatus.dispatched && totalReceived == 0);

  bool get canEdit => status == TransferOrderStatus.draft;

  /// True when the order closed with fewer units arriving than left.
  bool get hasShortage =>
      status == TransferOrderStatus.received && totalReceived < totalDispatched;

  /// How many days this shipment has been in transit, or null when it is not.
  int? get daysInTransit {
    if (status != TransferOrderStatus.dispatched || dispatchedAt == null) {
      return null;
    }
    return DateTime.now().difference(dispatchedAt!).inDays;
  }

  bool get isOverdue =>
      status == TransferOrderStatus.dispatched &&
      expectedAt != null &&
      expectedAt!.isBefore(DateTime.now());

  String get statusLabel => statusLabelOf(status);

  static String statusLabelOf(TransferOrderStatus s) => switch (s) {
    TransferOrderStatus.draft => 'Draft',
    TransferOrderStatus.dispatched => 'In transit',
    TransferOrderStatus.received => 'Received',
    TransferOrderStatus.cancelled => 'Cancelled',
  };

  static TransferOrderStatus statusFromString(String s) => switch (s) {
    'dispatched' => TransferOrderStatus.dispatched,
    'received' => TransferOrderStatus.received,
    'cancelled' => TransferOrderStatus.cancelled,
    _ => TransferOrderStatus.draft,
  };

  static String statusToString(TransferOrderStatus s) => switch (s) {
    TransferOrderStatus.draft => 'draft',
    TransferOrderStatus.dispatched => 'dispatched',
    TransferOrderStatus.received => 'received',
    TransferOrderStatus.cancelled => 'cancelled',
  };

  factory TransferOrderModel.fromMap(Map<String, dynamic> map, String docId) {
    final rawLines = map['lines'];
    return TransferOrderModel(
      id: docId,
      referenceNumber: safeString(map['referenceNumber']),
      fromLocation: safeString(map['fromLocation']),
      toLocation: safeString(map['toLocation']),
      status: statusFromString(safeString(map['status'], 'draft')),
      lines: rawLines is List
          ? rawLines
                .whereType<Map>()
                .map(
                  (e) =>
                      TransferOrderLine.fromMap(Map<String, dynamic>.from(e)),
                )
                .toList()
          : const [],
      notes: safeString(map['notes']),
      carrier: safeString(map['carrier']),
      trackingReference: safeString(map['trackingReference']),
      expectedAt: map['expectedAt'] == null
          ? null
          : safeTimestamp(map['expectedAt']),
      dispatchedAt: map['dispatchedAt'] == null
          ? null
          : safeTimestamp(map['dispatchedAt']),
      receivedAt: map['receivedAt'] == null
          ? null
          : safeTimestamp(map['receivedAt']),
      dispatchedBy: safeString(map['dispatchedBy']),
      dispatchedByName: safeString(map['dispatchedByName']),
      receivedBy: safeString(map['receivedBy']),
      receivedByName: safeString(map['receivedByName']),
      createdBy: safeString(map['createdBy']),
      createdByName: safeString(map['createdByName']),
      createdAt: safeTimestamp(map['createdAt']),
      updatedAt: safeTimestamp(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'referenceNumber': referenceNumber,
    'fromLocation': fromLocation,
    'toLocation': toLocation,
    'status': statusToString(status),
    'lines': lines.map((l) => l.toMap()).toList(),
    'notes': notes,
    'carrier': carrier,
    'trackingReference': trackingReference,
    if (expectedAt != null) 'expectedAt': Timestamp.fromDate(expectedAt!),
    if (dispatchedAt != null) 'dispatchedAt': Timestamp.fromDate(dispatchedAt!),
    if (receivedAt != null) 'receivedAt': Timestamp.fromDate(receivedAt!),
    'dispatchedBy': dispatchedBy,
    'dispatchedByName': dispatchedByName,
    'receivedBy': receivedBy,
    'receivedByName': receivedByName,
    'createdBy': createdBy,
    'createdByName': createdByName,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  TransferOrderModel copyWith({
    String? id,
    String? referenceNumber,
    String? fromLocation,
    String? toLocation,
    TransferOrderStatus? status,
    List<TransferOrderLine>? lines,
    String? notes,
    String? carrier,
    String? trackingReference,
    DateTime? expectedAt,
    DateTime? dispatchedAt,
    DateTime? receivedAt,
    String? dispatchedBy,
    String? dispatchedByName,
    String? receivedBy,
    String? receivedByName,
    String? createdBy,
    String? createdByName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => TransferOrderModel(
    id: id ?? this.id,
    referenceNumber: referenceNumber ?? this.referenceNumber,
    fromLocation: fromLocation ?? this.fromLocation,
    toLocation: toLocation ?? this.toLocation,
    status: status ?? this.status,
    lines: lines ?? this.lines,
    notes: notes ?? this.notes,
    carrier: carrier ?? this.carrier,
    trackingReference: trackingReference ?? this.trackingReference,
    expectedAt: expectedAt ?? this.expectedAt,
    dispatchedAt: dispatchedAt ?? this.dispatchedAt,
    receivedAt: receivedAt ?? this.receivedAt,
    dispatchedBy: dispatchedBy ?? this.dispatchedBy,
    dispatchedByName: dispatchedByName ?? this.dispatchedByName,
    receivedBy: receivedBy ?? this.receivedBy,
    receivedByName: receivedByName ?? this.receivedByName,
    createdBy: createdBy ?? this.createdBy,
    createdByName: createdByName ?? this.createdByName,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
