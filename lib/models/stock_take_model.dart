import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

enum StockTakeStatus { draft, inProgress, completed }

class StockTakeItem {
  final String productId;
  final String productName;
  final int expectedQty;
  final int countedQty;
  final int variance;
  final String notes;

  StockTakeItem({
    required this.productId,
    this.productName = '',
    this.expectedQty = 0,
    this.countedQty = 0,
    this.variance = 0,
    this.notes = '',
  });

  factory StockTakeItem.fromMap(Map<String, dynamic> map) {
    return StockTakeItem(
      productId: safeString(map['productId']),
      productName: safeString(map['productName']),
      expectedQty: safeInt(map['expectedQty']),
      countedQty: safeInt(map['countedQty']),
      variance: safeInt(map['variance']),
      notes: safeString(map['notes']),
    );
  }

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'productName': productName,
    'expectedQty': expectedQty,
    'countedQty': countedQty,
    'variance': variance,
    'notes': notes,
  };

  StockTakeItem copyWith({
    String? productId,
    String? productName,
    int? expectedQty,
    int? countedQty,
    int? variance,
    String? notes,
  }) {
    return StockTakeItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      expectedQty: expectedQty ?? this.expectedQty,
      countedQty: countedQty ?? this.countedQty,
      variance: variance ?? this.variance,
      notes: notes ?? this.notes,
    );
  }
}

class StockTakeModel {
  final String id;
  final String name;
  final StockTakeStatus status;
  final String locationFilter;
  final String categoryFilter;
  final String createdBy;
  final String createdByName;
  final DateTime startedAt;
  final DateTime? completedAt;
  final List<StockTakeItem> items;

  StockTakeModel({
    required this.id,
    required this.name,
    this.status = StockTakeStatus.draft,
    this.locationFilter = '',
    this.categoryFilter = '',
    this.createdBy = '',
    this.createdByName = '',
    required this.startedAt,
    this.completedAt,
    this.items = const [],
  });

  String get statusLabel => switch (status) {
    StockTakeStatus.draft => 'Draft',
    StockTakeStatus.inProgress => 'In Progress',
    StockTakeStatus.completed => 'Completed',
  };

  static StockTakeStatus _statusFromString(String s) => switch (s) {
    'inProgress' => StockTakeStatus.inProgress,
    'completed' => StockTakeStatus.completed,
    _ => StockTakeStatus.draft,
  };

  static String _statusToString(StockTakeStatus s) => switch (s) {
    StockTakeStatus.draft => 'draft',
    StockTakeStatus.inProgress => 'inProgress',
    StockTakeStatus.completed => 'completed',
  };

  factory StockTakeModel.fromMap(Map<String, dynamic> map, String docId) {
    List<StockTakeItem> items = [];
    if (map['items'] is List) {
      items = (map['items'] as List)
          .map((e) => StockTakeItem.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    }
    return StockTakeModel(
      id: docId,
      name: safeString(map['name']),
      status: _statusFromString(safeString(map['status'], 'draft')),
      locationFilter: safeString(map['locationFilter']),
      categoryFilter: safeString(map['categoryFilter']),
      createdBy: safeString(map['createdBy']),
      createdByName: safeString(map['createdByName']),
      startedAt: safeTimestamp(map['startedAt']),
      completedAt: map['completedAt'] != null
          ? safeTimestamp(map['completedAt'])
          : null,
      items: items,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'status': _statusToString(status),
    'locationFilter': locationFilter,
    'categoryFilter': categoryFilter,
    'createdBy': createdBy,
    'createdByName': createdByName,
    'startedAt': Timestamp.fromDate(startedAt),
    if (completedAt != null) 'completedAt': Timestamp.fromDate(completedAt!),
    'items': items.map((e) => e.toMap()).toList(),
  };

  StockTakeModel copyWith({
    String? id,
    String? name,
    StockTakeStatus? status,
    String? locationFilter,
    String? categoryFilter,
    String? createdBy,
    String? createdByName,
    DateTime? startedAt,
    DateTime? completedAt,
    List<StockTakeItem>? items,
  }) {
    return StockTakeModel(
      id: id ?? this.id,
      name: name ?? this.name,
      status: status ?? this.status,
      locationFilter: locationFilter ?? this.locationFilter,
      categoryFilter: categoryFilter ?? this.categoryFilter,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      items: items ?? this.items,
    );
  }
}
