import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

/// Where a tracked unit currently is in its life.
enum SerialStatus { inStock, allocated, sold, returned, scrapped }

/// One movement in a serial's history, kept inline on the document.
///
/// Serials move a handful of times each, so a subcollection would cost a query
/// per detail view to read three rows. The list is capped when written so a
/// pathological unit cannot grow the document without bound.
class SerialEvent {
  final String action;
  final String note;
  final String referenceType;
  final String referenceId;
  final String userId;
  final String userName;
  final DateTime at;

  const SerialEvent({
    required this.action,
    this.note = '',
    this.referenceType = '',
    this.referenceId = '',
    this.userId = '',
    this.userName = '',
    required this.at,
  });

  factory SerialEvent.fromMap(Map<String, dynamic> map) => SerialEvent(
    action: safeString(map['action']),
    note: safeString(map['note']),
    referenceType: safeString(map['referenceType']),
    referenceId: safeString(map['referenceId']),
    userId: safeString(map['userId']),
    userName: safeString(map['userName']),
    at: safeTimestamp(map['at']),
  );

  Map<String, dynamic> toMap() => {
    'action': action,
    'note': note,
    'referenceType': referenceType,
    'referenceId': referenceId,
    'userId': userId,
    'userName': userName,
    'at': Timestamp.fromDate(at),
  };
}

/// A single physically identifiable unit of a product.
class SerialModel {
  final String id;

  /// The printed identifier. Stored as entered for display.
  final String serialNumber;

  /// [serialNumber] upper-cased with whitespace collapsed, so lookups are
  /// case- and spacing-insensitive without needing a case-insensitive query
  /// Firestore does not offer.
  final String serialKey;

  final String productId;
  final String productName;
  final String batchId;
  final String batchNumber;
  final String location;
  final SerialStatus status;

  /// The document that last moved this unit (an invoice, order or return).
  final String referenceType;
  final String referenceId;
  final String referenceLabel;

  final String notes;
  final DateTime? warrantyUntil;
  final List<SerialEvent> history;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;

  SerialModel({
    required this.id,
    required this.serialNumber,
    String? serialKey,
    required this.productId,
    this.productName = '',
    this.batchId = '',
    this.batchNumber = '',
    this.location = '',
    this.status = SerialStatus.inStock,
    this.referenceType = '',
    this.referenceId = '',
    this.referenceLabel = '',
    this.notes = '',
    this.warrantyUntil,
    this.history = const [],
    this.createdBy = '',
    this.createdByName = '',
    required this.createdAt,
    required this.updatedAt,
  }) : serialKey = serialKey ?? normalizeSerial(serialNumber);

  /// How many history entries a document keeps. Older ones fall off the front.
  static const int historyLimit = 40;

  /// The lookup form of [raw]: trimmed, inner whitespace collapsed, upper-cased.
  static String normalizeSerial(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();

  /// True when this unit is still ours and countable as stock.
  bool get isOnHand =>
      status == SerialStatus.inStock ||
      status == SerialStatus.allocated ||
      status == SerialStatus.returned;

  bool get isUnderWarranty =>
      warrantyUntil != null && warrantyUntil!.isAfter(DateTime.now());

  String get statusLabel => statusLabelOf(status);

  static String statusLabelOf(SerialStatus s) => switch (s) {
    SerialStatus.inStock => 'In stock',
    SerialStatus.allocated => 'Allocated',
    SerialStatus.sold => 'Sold',
    SerialStatus.returned => 'Returned',
    SerialStatus.scrapped => 'Scrapped',
  };

  static SerialStatus statusFromString(String s) => switch (s) {
    'allocated' => SerialStatus.allocated,
    'sold' => SerialStatus.sold,
    'returned' => SerialStatus.returned,
    'scrapped' => SerialStatus.scrapped,
    _ => SerialStatus.inStock,
  };

  static String statusToString(SerialStatus s) => switch (s) {
    SerialStatus.inStock => 'inStock',
    SerialStatus.allocated => 'allocated',
    SerialStatus.sold => 'sold',
    SerialStatus.returned => 'returned',
    SerialStatus.scrapped => 'scrapped',
  };

  /// This unit with [event] appended and its status moved to [status].
  SerialModel withEvent(SerialEvent event, {SerialStatus? status}) {
    final next = [...history, event];
    return copyWith(
      status: status ?? this.status,
      history: next.length > historyLimit
          ? next.sublist(next.length - historyLimit)
          : next,
      updatedAt: event.at,
    );
  }

  factory SerialModel.fromMap(Map<String, dynamic> map, String docId) {
    final rawHistory = map['history'];
    final number = safeString(map['serialNumber']);
    return SerialModel(
      id: docId,
      serialNumber: number,
      // Recomputed when absent so documents written before the key existed
      // still resolve through the same lookup path.
      serialKey: safeString(map['serialKey'], normalizeSerial(number)),
      productId: safeString(map['productId']),
      productName: safeString(map['productName']),
      batchId: safeString(map['batchId']),
      batchNumber: safeString(map['batchNumber']),
      location: safeString(map['location']),
      status: statusFromString(safeString(map['status'], 'inStock')),
      referenceType: safeString(map['referenceType']),
      referenceId: safeString(map['referenceId']),
      referenceLabel: safeString(map['referenceLabel']),
      notes: safeString(map['notes']),
      warrantyUntil: map['warrantyUntil'] == null
          ? null
          : safeTimestamp(map['warrantyUntil']),
      history: rawHistory is List
          ? rawHistory
                .whereType<Map>()
                .map((e) => SerialEvent.fromMap(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
      createdBy: safeString(map['createdBy']),
      createdByName: safeString(map['createdByName']),
      createdAt: safeTimestamp(map['createdAt']),
      updatedAt: safeTimestamp(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'serialNumber': serialNumber,
    'serialKey': serialKey,
    'productId': productId,
    'productName': productName,
    'batchId': batchId,
    'batchNumber': batchNumber,
    'location': location,
    'status': statusToString(status),
    'referenceType': referenceType,
    'referenceId': referenceId,
    'referenceLabel': referenceLabel,
    'notes': notes,
    if (warrantyUntil != null)
      'warrantyUntil': Timestamp.fromDate(warrantyUntil!),
    'history': history.map((e) => e.toMap()).toList(),
    'createdBy': createdBy,
    'createdByName': createdByName,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  SerialModel copyWith({
    String? id,
    String? serialNumber,
    String? productId,
    String? productName,
    String? batchId,
    String? batchNumber,
    String? location,
    SerialStatus? status,
    String? referenceType,
    String? referenceId,
    String? referenceLabel,
    String? notes,
    DateTime? warrantyUntil,
    List<SerialEvent>? history,
    String? createdBy,
    String? createdByName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final number = serialNumber ?? this.serialNumber;
    return SerialModel(
      id: id ?? this.id,
      serialNumber: number,
      serialKey: serialNumber == null ? serialKey : normalizeSerial(number),
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      batchId: batchId ?? this.batchId,
      batchNumber: batchNumber ?? this.batchNumber,
      location: location ?? this.location,
      status: status ?? this.status,
      referenceType: referenceType ?? this.referenceType,
      referenceId: referenceId ?? this.referenceId,
      referenceLabel: referenceLabel ?? this.referenceLabel,
      notes: notes ?? this.notes,
      warrantyUntil: warrantyUntil ?? this.warrantyUntil,
      history: history ?? this.history,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
