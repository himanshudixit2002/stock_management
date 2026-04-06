import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

class PriceHistoryModel {
  final String id;
  final String productId;
  final String productName;
  final String field;
  final double oldValue;
  final double newValue;
  final String changedBy;
  final String changedByName;
  final DateTime timestamp;

  PriceHistoryModel({
    required this.id,
    required this.productId,
    this.productName = '',
    required this.field,
    this.oldValue = 0,
    this.newValue = 0,
    this.changedBy = '',
    this.changedByName = '',
    required this.timestamp,
  });

  factory PriceHistoryModel.fromMap(Map<String, dynamic> map, String docId) {
    return PriceHistoryModel(
      id: docId,
      productId: safeString(map['productId']),
      productName: safeString(map['productName']),
      field: safeString(map['field']),
      oldValue: safeDouble(map['oldValue']),
      newValue: safeDouble(map['newValue']),
      changedBy: safeString(map['changedBy']),
      changedByName: safeString(map['changedByName']),
      timestamp: safeTimestamp(map['timestamp']),
    );
  }

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'productName': productName,
    'field': field,
    'oldValue': oldValue,
    'newValue': newValue,
    'changedBy': changedBy,
    'changedByName': changedByName,
    'timestamp': Timestamp.fromDate(timestamp),
  };

  PriceHistoryModel copyWith({
    String? id,
    String? productId,
    String? productName,
    String? field,
    double? oldValue,
    double? newValue,
    String? changedBy,
    String? changedByName,
    DateTime? timestamp,
  }) {
    return PriceHistoryModel(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      field: field ?? this.field,
      oldValue: oldValue ?? this.oldValue,
      newValue: newValue ?? this.newValue,
      changedBy: changedBy ?? this.changedBy,
      changedByName: changedByName ?? this.changedByName,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
