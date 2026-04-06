import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

class AuditLogModel {
  final String id;
  final String action;
  final String entityType;
  final String entityId;
  final String entityName;
  final String userId;
  final String userName;
  final Map<String, dynamic> changes;
  final DateTime timestamp;

  AuditLogModel({
    required this.id,
    required this.action,
    required this.entityType,
    this.entityId = '',
    this.entityName = '',
    this.userId = '',
    this.userName = '',
    this.changes = const {},
    required this.timestamp,
  });

  factory AuditLogModel.fromMap(Map<String, dynamic> map, String docId) {
    Map<String, dynamic> changes = {};
    if (map['changes'] != null && map['changes'] is Map) {
      changes = Map<String, dynamic>.from(map['changes']);
    }
    return AuditLogModel(
      id: docId,
      action: safeString(map['action']),
      entityType: safeString(map['entityType']),
      entityId: safeString(map['entityId']),
      entityName: safeString(map['entityName']),
      userId: safeString(map['userId']),
      userName: safeString(map['userName']),
      changes: changes,
      timestamp: safeTimestamp(map['timestamp']),
    );
  }

  Map<String, dynamic> toMap() => {
    'action': action,
    'entityType': entityType,
    'entityId': entityId,
    'entityName': entityName,
    'userId': userId,
    'userName': userName,
    'changes': changes,
    'timestamp': Timestamp.fromDate(timestamp),
  };

  AuditLogModel copyWith({
    String? id,
    String? action,
    String? entityType,
    String? entityId,
    String? entityName,
    String? userId,
    String? userName,
    Map<String, dynamic>? changes,
    DateTime? timestamp,
  }) {
    return AuditLogModel(
      id: id ?? this.id,
      action: action ?? this.action,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      entityName: entityName ?? this.entityName,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      changes: changes ?? this.changes,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
