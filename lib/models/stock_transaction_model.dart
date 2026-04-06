import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

enum TransactionType { stockIn, stockOut, damage, transfer, adjustment }

class StockTransactionModel {
  final String id;
  final String productId;
  final String productName;
  final TransactionType type;
  final int quantity;
  final String location;
  final String reason;
  final String userId;
  final String userName;
  final DateTime date;
  final String vendorId;
  final String vendorName;

  StockTransactionModel({
    required this.id,
    required this.productId,
    this.productName = '',
    required this.type,
    required this.quantity,
    this.location = '',
    this.reason = '',
    required this.userId,
    this.userName = '',
    required this.date,
    this.vendorId = '',
    this.vendorName = '',
  });

  String get typeLabel {
    return switch (type) {
      TransactionType.stockIn => 'Stock In',
      TransactionType.stockOut => 'Stock Out',
      TransactionType.damage => 'Damage',
      TransactionType.transfer => 'Transfer',
      TransactionType.adjustment => 'Adjustment',
    };
  }

  String get typeIcon {
    return switch (type) {
      TransactionType.stockIn => '📦',
      TransactionType.stockOut => '📤',
      TransactionType.damage => '⚠️',
      TransactionType.transfer => '🔄',
      TransactionType.adjustment => '📋',
    };
  }

  static TransactionType _typeFromString(String type) {
    return switch (type) {
      'stock_in' => TransactionType.stockIn,
      'stock_out' => TransactionType.stockOut,
      'damage' => TransactionType.damage,
      'transfer' => TransactionType.transfer,
      'adjustment' => TransactionType.adjustment,
      _ => TransactionType.stockIn,
    };
  }

  static String _typeToString(TransactionType type) {
    return switch (type) {
      TransactionType.stockIn => 'stock_in',
      TransactionType.stockOut => 'stock_out',
      TransactionType.damage => 'damage',
      TransactionType.transfer => 'transfer',
      TransactionType.adjustment => 'adjustment',
    };
  }

  factory StockTransactionModel.fromMap(
    Map<String, dynamic> map,
    String docId,
  ) {
    final rawQty = safeInt(map['quantity']);
    return StockTransactionModel(
      id: docId,
      productId: safeString(map['productId']),
      productName: safeString(map['productName']),
      type: _typeFromString(safeString(map['type'], 'stock_in')),
      quantity: rawQty < 0 ? 0 : rawQty,
      location: safeString(map['location']),
      reason: safeString(map['reason']),
      userId: safeString(map['userId']),
      userName: safeString(map['userName']),
      date: safeTimestamp(map['date']),
      vendorId: safeString(map['vendorId']),
      vendorName: safeString(map['vendorName']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'productName': productName,
      'type': _typeToString(type),
      'quantity': quantity,
      'location': location,
      'reason': reason,
      'userId': userId,
      'userName': userName,
      'date': Timestamp.fromDate(date),
      'vendorId': vendorId,
      'vendorName': vendorName,
    };
  }

  StockTransactionModel copyWith({
    String? id,
    String? productId,
    String? productName,
    TransactionType? type,
    int? quantity,
    String? location,
    String? reason,
    String? userId,
    String? userName,
    DateTime? date,
    String? vendorId,
    String? vendorName,
  }) {
    return StockTransactionModel(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      type: type ?? this.type,
      quantity: quantity ?? this.quantity,
      location: location ?? this.location,
      reason: reason ?? this.reason,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      date: date ?? this.date,
      vendorId: vendorId ?? this.vendorId,
      vendorName: vendorName ?? this.vendorName,
    );
  }
}
