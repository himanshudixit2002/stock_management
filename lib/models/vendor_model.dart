import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

class VendorModel {
  final String id;
  final String name;
  final String contactName;
  final String email;
  final String phone;
  final String address;
  final int leadTimeDays;
  final double rating;
  final String notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;
  final String createdByName;

  VendorModel({
    required this.id,
    required this.name,
    this.contactName = '',
    this.email = '',
    this.phone = '',
    this.address = '',
    this.leadTimeDays = 0,
    this.rating = 0,
    this.notes = '',
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy = '',
    this.createdByName = '',
  });

  factory VendorModel.fromMap(Map<String, dynamic> map, String docId) {
    return VendorModel(
      id: docId,
      name: safeString(map['name']),
      contactName: safeString(map['contactName']),
      email: safeString(map['email']),
      phone: safeString(map['phone']),
      address: safeString(map['address']),
      leadTimeDays: safeInt(map['leadTimeDays']),
      rating: safeDouble(map['rating']),
      notes: safeString(map['notes']),
      isActive: safeBool(map['isActive'], true),
      createdAt: safeTimestamp(map['createdAt']),
      updatedAt: safeTimestamp(map['updatedAt']),
      createdBy: safeString(map['createdBy']),
      createdByName: safeString(map['createdByName']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'contactName': contactName,
      'email': email,
      'phone': phone,
      'address': address,
      'leadTimeDays': leadTimeDays,
      'rating': rating,
      'notes': notes,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'createdBy': createdBy,
      'createdByName': createdByName,
    };
  }

  VendorModel copyWith({
    String? id,
    String? name,
    String? contactName,
    String? email,
    String? phone,
    String? address,
    int? leadTimeDays,
    double? rating,
    String? notes,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
    String? createdByName,
  }) {
    return VendorModel(
      id: id ?? this.id,
      name: name ?? this.name,
      contactName: contactName ?? this.contactName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      leadTimeDays: leadTimeDays ?? this.leadTimeDays,
      rating: rating ?? this.rating,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
    );
  }
}
