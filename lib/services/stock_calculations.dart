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
  static int netStockChange(List<StockTransactionModel> transactions) {
    int net = 0;
    for (final t in transactions) {
      switch (t.type) {
        case TransactionType.stockIn:
          net += t.quantity;
        case TransactionType.stockOut:
        case TransactionType.damage:
          net -= t.quantity;
        case TransactionType.transfer:
        case TransactionType.adjustment:
          break;
      }
    }
    return net;
  }
}
