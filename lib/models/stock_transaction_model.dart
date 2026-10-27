import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

enum TransactionType {
  stockIn,
  stockOut,
  damage,
  transfer,
  adjustment,
  hold,
  holdRelease,

  /// The product's stock was re-counted in a smaller unit ("50 box" became
  /// "500 pcs"). Carries [StockTransactionModel.quantityDelta] so a ledger
  /// rebuilt from today's balance stays continuous across the change.
  unitConversion,
}

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

  /// Signed effect on stock, where the sign cannot be inferred from [type].
  /// Adjustments store [quantity] as an absolute value, so without this an
  /// adjustment row cannot say whether stock went up or down — which makes a
  /// running-balance ledger impossible to reconcile.
  ///
  /// Null on rows written before this field existed; treat that as unknown
  /// rather than as zero.
  final int? quantityDelta;

  /// For [TransactionType.unitConversion] rows: the unit stock was counted in
  /// before, the unit it is counted in after, and how many of the new one make
  /// one of the old. Empty / null on every other row.
  final String fromUnit;
  final String toUnit;
  final int? factor;

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
    this.quantityDelta,
    this.fromUnit = '',
    this.toUnit = '',
    this.factor,
  });

  /// Signed effect of this row on stock, or null when it cannot be determined
  /// (a legacy adjustment with no [quantityDelta] recorded).
  int? get signedEffect => switch (type) {
    TransactionType.stockIn => quantity,
    TransactionType.stockOut || TransactionType.damage => -quantity,
    TransactionType.adjustment ||
    TransactionType.unitConversion => quantityDelta,
    // Transfers move stock between locations; net product stock is unchanged.
    // Holds only reserve, they do not move anything.
    TransactionType.transfer ||
    TransactionType.hold ||
    TransactionType.holdRelease => 0,
  };

  /// "50 box → 500 pcs" for a [TransactionType.unitConversion] row, empty for
  /// any other. Stock goes from n to n × factor, so the delta is n × (factor −
  /// 1) and n falls out of it without storing a third number.
  String get conversionSummary {
    final f = factor ?? 0;
    if (type != TransactionType.unitConversion || f < 2) return '';
    final before = (quantityDelta ?? 0) ~/ (f - 1);
    return '$before $fromUnit → ${before * f} $toUnit';
  }

  String get typeLabel {
    return switch (type) {
      TransactionType.stockIn => 'Stock In',
      TransactionType.stockOut => 'Stock Out',
      TransactionType.damage => 'Damage',
      TransactionType.transfer => 'Transfer',
      TransactionType.adjustment => 'Adjustment',
      TransactionType.hold => 'Hold',
      TransactionType.holdRelease => 'Hold Release',
      TransactionType.unitConversion => 'Unit Conversion',
    };
  }

  String get typeIcon {
    return switch (type) {
      TransactionType.stockIn => '📦',
      TransactionType.stockOut => '📤',
      TransactionType.damage => '⚠️',
      TransactionType.transfer => '🔄',
      TransactionType.adjustment => '📋',
      TransactionType.hold => '⏸️',
      TransactionType.holdRelease => '▶️',
      TransactionType.unitConversion => '🔁',
    };
  }

  static TransactionType _typeFromString(String type) {
    return switch (type) {
      'stock_in' => TransactionType.stockIn,
      'stock_out' => TransactionType.stockOut,
      'damage' => TransactionType.damage,
      'transfer' => TransactionType.transfer,
      'adjustment' => TransactionType.adjustment,
      'hold' => TransactionType.hold,
      'hold_release' => TransactionType.holdRelease,
      'unit_conversion' => TransactionType.unitConversion,
      _ => TransactionType.adjustment,
    };
  }

  static String _typeToString(TransactionType type) {
    return switch (type) {
      TransactionType.stockIn => 'stock_in',
      TransactionType.stockOut => 'stock_out',
      TransactionType.damage => 'damage',
      TransactionType.transfer => 'transfer',
      TransactionType.adjustment => 'adjustment',
      TransactionType.hold => 'hold',
      TransactionType.holdRelease => 'hold_release',
      TransactionType.unitConversion => 'unit_conversion',
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
      quantityDelta: map['quantityDelta'] == null
          ? null
          : safeInt(map['quantityDelta']),
      fromUnit: safeString(map['fromUnit']),
      toUnit: safeString(map['toUnit']),
      factor: map['factor'] == null ? null : safeInt(map['factor']),
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
      if (quantityDelta != null) 'quantityDelta': quantityDelta,
      if (fromUnit.isNotEmpty) 'fromUnit': fromUnit,
      if (toUnit.isNotEmpty) 'toUnit': toUnit,
      if (factor != null) 'factor': factor,
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
    int? quantityDelta,
    String? fromUnit,
    String? toUnit,
    int? factor,
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
      quantityDelta: quantityDelta ?? this.quantityDelta,
      fromUnit: fromUnit ?? this.fromUnit,
      toUnit: toUnit ?? this.toUnit,
      factor: factor ?? this.factor,
    );
  }
}
