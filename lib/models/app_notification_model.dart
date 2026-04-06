import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

class AppNotificationModel {
  final String id;
  final String type;
  final String title;
  final String message;
  final bool isRead;
  final String entityType;
  final String entityId;
  final DateTime timestamp;

  AppNotificationModel({
    required this.id,
    required this.type,
    required this.title,
    this.message = '',
    this.isRead = false,
    this.entityType = '',
    this.entityId = '',
    required this.timestamp,
  });

  factory AppNotificationModel.fromMap(Map<String, dynamic> map, String docId) {
    return AppNotificationModel(
      id: docId,
      type: safeString(map['type']),
      title: safeString(map['title']),
      message: safeString(map['message']),
      isRead: safeBool(map['isRead']),
      entityType: safeString(map['entityType']),
      entityId: safeString(map['entityId']),
      timestamp: safeTimestamp(map['timestamp']),
    );
  }

  Map<String, dynamic> toMap() => {
    'type': type,
    'title': title,
    'message': message,
    'isRead': isRead,
    'entityType': entityType,
    'entityId': entityId,
    'timestamp': Timestamp.fromDate(timestamp),
  };

  AppNotificationModel copyWith({
    String? id,
    String? type,
    String? title,
    String? message,
    bool? isRead,
    String? entityType,
    String? entityId,
    DateTime? timestamp,
  }) {
    return AppNotificationModel(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      message: message ?? this.message,
      isRead: isRead ?? this.isRead,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
