import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/stock_transaction_model.dart';
import 'package:stock_management/services/stock_calculations.dart';

StockTransactionModel _row(
  TransactionType type,
  int quantity, {
  required DateTime date,
  int? delta,
  String fromUnit = '',
  String toUnit = '',
  int? factor,
}) => StockTransactionModel(
  id: '${type.name}-${date.millisecondsSinceEpoch}',
  productId: 'p1',
  type: type,
  quantity: quantity,
  userId: 'u1',
  date: date,
  quantityDelta: delta,
  fromUnit: fromUnit,
  toUnit: toUnit,
  factor: factor,
);

void main() {
  final conversion = _row(
    TransactionType.unitConversion,
    450,
    date: DateTime(2026, 3, 1),
    delta: 450,
    fromUnit: 'box',
    toUnit: 'pcs',
    factor: 10,
  );

  test('a conversion row round-trips with its units and factor', () {
    final back = StockTransactionModel.fromMap(conversion.toMap(), 'id');
    expect(back.type, TransactionType.unitConversion);
    expect(back.toMap()['type'], 'unit_conversion');
    expect(back.quantityDelta, 450);
    expect(back.fromUnit, 'box');
    expect(back.toUnit, 'pcs');
    expect(back.factor, 10);
  });

  test('other rows do not write the conversion fields', () {
    final map = _row(TransactionType.stockIn, 5, date: DateTime(2026)).toMap();
    expect(map.containsKey('fromUnit'), isFalse);
    expect(map.containsKey('factor'), isFalse);
  });

  test('an unknown type still reads as an adjustment', () {
    // What an older build sees for 'unit_conversion': an adjustment whose
    // effect is its quantityDelta, which keeps its ledger continuous too.
    final row = StockTransactionModel.fromMap({
      'type': 'something_new',
      'quantity': 450,
      'quantityDelta': 450,
    }, 'id');
    expect(row.type, TransactionType.adjustment);
    expect(row.signedEffect, 450);
  });

  test('describes itself as before and after', () {
    expect(conversion.conversionSummary, '50 box → 500 pcs');
    expect(
      _row(TransactionType.stockIn, 5, date: DateTime(2026)).conversionSummary,
      isEmpty,
    );
  });

  test('a ledger across a conversion reconciles to today', () {
    // 50 box in, converted to 500 pcs, then 20 pcs out: 480 pcs on hand.
    final rows = StockCalculations.buildLedger([
      _row(TransactionType.stockIn, 50, date: DateTime(2026, 2, 1)),
      conversion,
      _row(TransactionType.stockOut, 20, date: DateTime(2026, 4, 1)),
    ], closingBalance: 480);
    expect(rows.map((r) => r.balanceAfter), [50, 500, 480]);
  });
}
