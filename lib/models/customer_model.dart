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

  /// The most this customer may owe at once. Zero means "no limit set", not
  /// "no credit": a limit of zero would silently stop every credit sale for
  /// every customer that predates this field.
  final double creditLimit;

  /// Days this customer gets to pay. Zero falls back to the workspace default
  /// from billing settings, so a customer with no special terms follows the
  /// company's.
  final int paymentTermDays;

  /// Set by hand to stop further credit regardless of the limit — a disputed
  /// account, a cheque that bounced, a customer being wound up.
  final bool creditHold;

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
    this.creditLimit = 0,
    this.paymentTermDays = 0,
    this.creditHold = false,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy = '',
    this.createdByName = '',
  });

  /// True when a limit has actually been set for this customer.
  bool get hasCreditLimit => creditLimit > 0;

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
      creditLimit: safeDouble(map['creditLimit']),
      paymentTermDays: safeInt(map['paymentTermDays']),
      creditHold: safeBool(map['creditHold']),
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
    'creditLimit': creditLimit,
    'paymentTermDays': paymentTermDays,
    'creditHold': creditHold,
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
    double? creditLimit,
    int? paymentTermDays,
    bool? creditHold,
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
      creditLimit: creditLimit ?? this.creditLimit,
      paymentTermDays: paymentTermDays ?? this.paymentTermDays,
      creditHold: creditHold ?? this.creditHold,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
    );
  }
}
