import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

class CustomerModel {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String address;
  final String company;
  final String notes;
  final int totalOrders;
  final double totalSpent;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;
  final String createdByName;

  CustomerModel({
    required this.id,
    required this.name,
    this.email = '',
    this.phone = '',
    this.address = '',
    this.company = '',
    this.notes = '',
    this.totalOrders = 0,
    this.totalSpent = 0,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy = '',
    this.createdByName = '',
  });

  factory CustomerModel.fromMap(Map<String, dynamic> map, String docId) {
    return CustomerModel(
      id: docId,
      name: safeString(map['name']),
      email: safeString(map['email']),
      phone: safeString(map['phone']),
      address: safeString(map['address']),
      company: safeString(map['company']),
      notes: safeString(map['notes']),
      totalOrders: safeInt(map['totalOrders']),
      totalSpent: safeDouble(map['totalSpent']),
      isActive: safeBool(map['isActive'], true),
      createdAt: safeTimestamp(map['createdAt']),
      updatedAt: safeTimestamp(map['updatedAt']),
      createdBy: safeString(map['createdBy']),
      createdByName: safeString(map['createdByName']),
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'email': email,
    'phone': phone,
    'address': address,
    'company': company,
    'notes': notes,
    'totalOrders': totalOrders,
    'totalSpent': totalSpent,
    'isActive': isActive,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
    'createdBy': createdBy,
    'createdByName': createdByName,
  };

  CustomerModel copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    String? address,
    String? company,
    String? notes,
    int? totalOrders,
    double? totalSpent,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
    String? createdByName,
  }) {
    return CustomerModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      company: company ?? this.company,
      notes: notes ?? this.notes,
      totalOrders: totalOrders ?? this.totalOrders,
      totalSpent: totalSpent ?? this.totalSpent,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
    );
  }
}
