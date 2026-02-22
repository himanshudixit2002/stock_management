import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

enum TransactionType { stockIn, stockOut, damage, transfer }

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
    switch (type) {
      case TransactionType.stockIn:
        return 'Stock In';
      case TransactionType.stockOut:
        return 'Stock Out';
      case TransactionType.damage:
        return 'Damage';
      case TransactionType.transfer:
        return 'Transfer';
    }
  }

  String get typeIcon {
    switch (type) {
      case TransactionType.stockIn:
        return '📦';
      case TransactionType.stockOut:
        return '📤';
      case TransactionType.damage:
        return '⚠️';
      case TransactionType.transfer:
        return '🔄';
    }
  }

  static TransactionType _typeFromString(String type) {
    switch (type) {
      case 'stock_in':
        return TransactionType.stockIn;
      case 'stock_out':
        return TransactionType.stockOut;
      case 'damage':
        return TransactionType.damage;
      case 'transfer':
        return TransactionType.transfer;
      default:
        return TransactionType.stockIn;
    }
  }

  static String _typeToString(TransactionType type) {
    switch (type) {
      case TransactionType.stockIn:
        return 'stock_in';
      case TransactionType.stockOut:
        return 'stock_out';
      case TransactionType.damage:
        return 'damage';
      case TransactionType.transfer:
        return 'transfer';
    }
  }

  factory StockTransactionModel.fromMap(
    Map<String, dynamic> map,
    String docId,
  ) {
    return StockTransactionModel(
      id: docId,
      productId: safeString(map['productId']),
      productName: safeString(map['productName']),
      type: _typeFromString(safeString(map['type'], 'stock_in')),
      quantity: safeInt(map['quantity']),
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
}
