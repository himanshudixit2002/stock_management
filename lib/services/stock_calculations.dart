import 'dart:math' as math;

import '../models/product_model.dart';
import '../models/stock_transaction_model.dart';

/// Pure calculation functions for stock data — testable without Firebase.
class StockCalculations {
  StockCalculations._();

  // --- Demand -------------------------------------------------------------
  //
  // These live here because four screens each rolled their own and disagreed:
  // the reorder list and the forecast divided by a fixed 30 and measured
  // against on-hand; the reports service divided by its selected period; the AI
  // dashboard counted damage as demand as well. Meanwhile
  // ProductModel.needsReorder correctly uses availableQuantity — so the list of
  // products flagged for reorder and the days-of-supply printed beside them
  // were computed off different stock figures.

  /// Units of [productId] sold per day over the [windowDays] ending now.
  ///
  /// Only stock-out counts. Damage is a loss, not demand: ordering more stock
  /// because units were dropped conflates two different problems, and it was
  /// the reason the AI dashboard's velocity ran higher than every other screen.
  ///
  /// The divisor is the window *observed*, not the window asked for: a
  /// workspace three days old has no 30 days of history, and dividing by 30
  /// understated its burn by a factor of ten. [firstTransactionAt] is the
  /// earliest movement in the whole dataset — pass it to get this correction;
  /// omit it and the full window is assumed.
  static double dailyBurnRate(
    List<StockTransactionModel> transactions,
    String productId, {
    int windowDays = 30,
    DateTime? now,
    DateTime? firstTransactionAt,
  }) {
    if (windowDays <= 0) return 0;
    final end = now ?? DateTime.now();
    final start = end.subtract(Duration(days: windowDays));

    var total = 0;
    for (final t in transactions) {
      if (t.productId != productId) continue;
      if (t.type != TransactionType.stockOut) continue;
      if (t.date.isBefore(start)) continue;
      total += t.quantity;
    }
    if (total == 0) return 0;

    return total / observedDays(windowDays, now: end, firstAt: firstTransactionAt);
  }

  /// Days of history actually available, capped at [windowDays] and never
  /// below 1 (so a single day of data cannot divide by zero).
  static double observedDays(
    int windowDays, {
    DateTime? now,
    DateTime? firstAt,
  }) {
    if (firstAt == null) return windowDays.toDouble();
    final end = now ?? DateTime.now();
    final elapsed = end.difference(firstAt).inHours / 24.0;
    return math.max(1.0, math.min(windowDays.toDouble(), elapsed));
  }

  /// How long [product] lasts at [burnRate] units/day.
  ///
  /// Measured against **available** stock, not on-hand: units already reserved
  /// for an order cannot be sold again. Reading on-hand overstated the runway
  /// exactly where it mattered — 40 on hand with 25 reserved and 5/day of
  /// demand read as 8 days when the truth was 3.
  ///
  /// Returns [double.infinity] when nothing is moving, so callers can say "no
  /// demand" rather than printing a made-up 999.
  static double daysOfSupply(ProductModel product, double burnRate) {
    if (burnRate <= 0) return double.infinity;
    return product.availableQuantity / burnRate;
  }

  /// Units to order so stock covers [leadTimeDays] plus a safety buffer.
  ///
  /// The old suggestion was `lowStockThreshold * 2 - quantity`, which used
  /// neither demand nor lead time: a product selling 50/day from a supplier
  /// with a 21-day lead time and a threshold of 10 was told to order 20 units —
  /// a guaranteed stockout about 19 days before the delivery landed.
  ///
  /// [safetyDays] of extra cover absorbs ordinary variation. Falls back to the
  /// threshold-based figure when there is no demand history to work from.
  static int suggestedReorderQuantity(
    ProductModel product,
    double burnRate, {
    required int leadTimeDays,
    int safetyDays = 7,
  }) {
    if (burnRate <= 0) {
      final fallback = product.lowStockThreshold * 2 - product.availableQuantity;
      return fallback < 1 ? 1 : fallback;
    }
    final cover = leadTimeDays + safetyDays;
    final target = burnRate * cover;
    final needed = (target - product.availableQuantity).ceil();
    return needed < 1 ? 1 : needed;
  }

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
