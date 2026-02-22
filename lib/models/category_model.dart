import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

class CategoryModel {
  final String id;
  final String name;
  final String description;
  final String? parentId;
  final String parentName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;
  final String createdByName;
  final String updatedBy;
  final String updatedByName;

  CategoryModel({
    required this.id,
    required this.name,
    this.description = '',
    this.parentId,
    this.parentName = '',
    required this.createdAt,
    DateTime? updatedAt,
    this.createdBy = '',
    this.createdByName = '',
    this.updatedBy = '',
    this.updatedByName = '',
  }) : updatedAt = updatedAt ?? createdAt;

  bool get isTopLevel => parentId == null || parentId!.isEmpty;
  bool get isSubcategory => !isTopLevel;

  factory CategoryModel.fromMap(Map<String, dynamic> map, String docId) {
    final created = safeTimestamp(map['createdAt']);
    final updated = safeTimestamp(map['updatedAt'], created);
    final rawParentId = safeString(map['parentId']);
    return CategoryModel(
      id: docId,
      name: safeString(map['name']),
      description: safeString(map['description']),
      parentId: rawParentId.isNotEmpty ? rawParentId : null,
      parentName: safeString(map['parentName']),
      createdAt: created,
      updatedAt: updated,
      createdBy: safeString(map['createdBy']),
      createdByName: safeString(map['createdByName']),
      updatedBy: safeString(map['updatedBy']),
      updatedByName: safeString(map['updatedByName']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'parentId': parentId ?? '',
      'parentName': parentName,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'createdBy': createdBy,
      'createdByName': createdByName,
      'updatedBy': updatedBy,
      'updatedByName': updatedByName,
    };
  }

  CategoryModel copyWith({
    String? id,
    String? name,
    String? description,
    String? parentId,
    String? parentName,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
    String? createdByName,
    String? updatedBy,
    String? updatedByName,
  }) {
    return CategoryModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      parentId: parentId ?? this.parentId,
      parentName: parentName ?? this.parentName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      updatedBy: updatedBy ?? this.updatedBy,
      updatedByName: updatedByName ?? this.updatedByName,
    );
  }

  @override
  String toString() => name;
}
