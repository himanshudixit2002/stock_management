import '../models/stock_transaction_model.dart';

/// Pure calculation functions for stock data — testable without Firebase.
class StockCalculations {
  StockCalculations._();

  /// Count transactions from today.
  static int todayTransactionCount(List<StockTransactionModel> transactions) {
    final now = DateTime.now();
    return transactions
        .where(
          (t) =>
              t.date.year == now.year &&
              t.date.month == now.month &&
              t.date.day == now.day,
        )
        .length;
  }

  /// Get the N most recent transactions.
  static List<StockTransactionModel> recentTransactions(
    List<StockTransactionModel> transactions, {
    int limit = 5,
  }) {
    return transactions.take(limit).toList();
  }

  /// Filter transactions by type.
  static List<StockTransactionModel> filterByType(
    List<StockTransactionModel> transactions,
    TransactionType type,
  ) {
    return transactions.where((t) => t.type == type).toList();
  }

  /// Filter transactions for a specific product.
  static List<StockTransactionModel> filterByProduct(
    List<StockTransactionModel> transactions,
    String productId,
  ) {
    return transactions.where((t) => t.productId == productId).toList();
  }

  /// Calculate net stock change from a list of transactions.
  ///
  /// Adjustments count towards the net — they move stock like anything else.
  /// A legacy adjustment with no recorded direction contributes nothing, since
  /// guessing a sign would be worse than under-counting; [hasUnknownDirection]
  /// lets a caller tell the user the figure is incomplete.
  static int netStockChange(List<StockTransactionModel> transactions) {
    int net = 0;
    for (final t in transactions) {
      net += t.signedEffect ?? 0;
    }
    return net;
  }

  /// True when any row's direction could not be determined, so a net figure
  /// derived from [transactions] understates the real movement.
  static bool hasUnknownDirection(List<StockTransactionModel> transactions) {
    return transactions.any((t) => t.signedEffect == null);
  }

  /// Builds a running-balance ledger, oldest first.
  ///
  /// [closingBalance] is the product's current on-hand quantity; the opening
  /// balance is derived by unwinding every movement from it, so the ledger
  /// always reconciles to what the product actually holds today.
  static List<LedgerRow> buildLedger(
    List<StockTransactionModel> transactions, {
    required int closingBalance,
  }) {
    final ordered = List<StockTransactionModel>.from(transactions)
      ..sort((a, b) => a.date.compareTo(b.date));

    var balance = closingBalance - netStockChange(ordered);
    final rows = <LedgerRow>[];
    for (final t in ordered) {
      final effect = t.signedEffect;
      balance += effect ?? 0;
      rows.add(
        LedgerRow(transaction: t, effect: effect, balanceAfter: balance),
      );
    }
    return rows;
  }
}

/// One line of a running-balance stock ledger.
class LedgerRow {
  final StockTransactionModel transaction;

  /// Signed effect on stock, or null when the direction was never recorded.
  final int? effect;
  final int balanceAfter;

  const LedgerRow({
    required this.transaction,
    required this.effect,
    required this.balanceAfter,
  });
}
