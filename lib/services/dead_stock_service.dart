import '../models/product_model.dart';
import '../models/stock_transaction_model.dart';

/// How stale a product's demand is.
enum MovementBand { fresh, slowing, stale, dead, neverSold }

/// One product, ranked by how long its stock has sat still.
class DeadStockEntry {
  const DeadStockEntry({
    required this.product,
    required this.daysSinceLastSale,
    required this.lastSaleDate,
    required this.unitsSoldInWindow,
    required this.band,
    required this.valueAtRest,
  });

  final ProductModel product;

  /// Days since the last outbound movement, or null when there has never been
  /// one. Null and "a very large number" are different facts: a product that
  /// has never sold may simply be new.
  final int? daysSinceLastSale;

  final DateTime? lastSaleDate;

  /// Units that went out during the analysis window.
  final int unitsSoldInWindow;

  final MovementBand band;

  /// Cost of the stock currently sitting on the shelf. Cost, not retail: this
  /// is the capital tied up, not the revenue foregone.
  final double valueAtRest;

  bool get isProblem => band == MovementBand.stale || band == MovementBand.dead;
}

/// The whole analysis, with the totals the header shows.
class DeadStockReport {
  const DeadStockReport({
    required this.entries,
    required this.windowDays,
    required this.staleAfterDays,
    required this.deadAfterDays,
    required this.totalValueAtRest,
    required this.deadValue,
    required this.staleValue,
    required this.bandCounts,
    required this.transactionsCovered,
  });

  /// Every analysed product, worst first.
  final List<DeadStockEntry> entries;

  final int windowDays;
  final int staleAfterDays;
  final int deadAfterDays;

  /// Cost value of all stock covered by the report.
  final double totalValueAtRest;

  final double deadValue;
  final double staleValue;
  final Map<MovementBand, int> bandCounts;

  /// How many transactions the analysis actually saw. The transaction stream is
  /// capped, so a workspace with a long history may be judged on a partial
  /// window — the screen says so rather than quietly reporting everything as
  /// dead.
  final int transactionsCovered;

  /// Capital tied up in stock that has stopped moving, as a share of the total.
  double get problemShare {
    if (totalValueAtRest <= 0) return 0;
    return (deadValue + staleValue) / totalValueAtRest;
  }

  int countOf(MovementBand band) => bandCounts[band] ?? 0;

  static const DeadStockReport empty = DeadStockReport(
    entries: [],
    windowDays: 0,
    staleAfterDays: 0,
    deadAfterDays: 0,
    totalValueAtRest: 0,
    deadValue: 0,
    staleValue: 0,
    bandCounts: {},
    transactionsCovered: 0,
  );
}

/// Ranks products by how long their stock has sat without selling.
///
/// Pure and synchronous: it takes the products and transactions the providers
/// already hold, so its numbers are the same ones every other report is built
/// from and it can be unit-tested without Firestore.
class DeadStockService {
  DeadStockService._();

  static const int defaultWindowDays = 90;
  static const int defaultStaleAfterDays = 60;
  static const int defaultDeadAfterDays = 120;

  /// Movement types that count as demand.
  ///
  /// Damage and adjustments are excluded on purpose: writing stock off is not
  /// evidence that anybody wanted it, and treating a write-off as a sale would
  /// hide exactly the products this report exists to find. Transfers move
  /// stock between our own locations, so they are not demand either.
  static bool _isOutbound(StockTransactionModel t) =>
      t.type == TransactionType.stockOut;

  static DeadStockReport analyse({
    required List<ProductModel> products,
    required List<StockTransactionModel> transactions,
    int windowDays = defaultWindowDays,
    int staleAfterDays = defaultStaleAfterDays,
    int deadAfterDays = defaultDeadAfterDays,
    DateTime? asOf,
    bool includeZeroStock = false,
  }) {
    if (products.isEmpty) return DeadStockReport.empty;

    final now = asOf ?? DateTime.now();
    final windowStart = now.subtract(Duration(days: windowDays));

    final lastSale = <String, DateTime>{};
    final unitsInWindow = <String, int>{};
    var covered = 0;

    for (final t in transactions) {
      if (!_isOutbound(t)) continue;
      covered++;
      final previous = lastSale[t.productId];
      if (previous == null || t.date.isAfter(previous)) {
        lastSale[t.productId] = t.date;
      }
      if (!t.date.isBefore(windowStart)) {
        unitsInWindow[t.productId] =
            (unitsInWindow[t.productId] ?? 0) + t.quantity;
      }
    }

    final entries = <DeadStockEntry>[];
    final counts = <MovementBand, int>{};
    var totalValue = 0.0;
    var deadValue = 0.0;
    var staleValue = 0.0;

    for (final product in products) {
      if (!includeZeroStock && product.quantity <= 0) continue;

      final last = lastSale[product.id];
      final days = last == null ? null : now.difference(last).inDays;
      final band = _bandFor(
        daysSinceLastSale: days,
        staleAfterDays: staleAfterDays,
        deadAfterDays: deadAfterDays,
      );
      final value = product.costPrice * product.quantity;

      totalValue += value;
      if (band == MovementBand.dead || band == MovementBand.neverSold) {
        deadValue += value;
      } else if (band == MovementBand.stale) {
        staleValue += value;
      }
      counts[band] = (counts[band] ?? 0) + 1;

      entries.add(
        DeadStockEntry(
          product: product,
          daysSinceLastSale: days,
          lastSaleDate: last,
          unitsSoldInWindow: unitsInWindow[product.id] ?? 0,
          band: band,
          valueAtRest: value,
        ),
      );
    }

    // Worst first: the most capital tied up in the least-moving stock. Sorting
    // on value alone would bury a warehouse of dead stock under one expensive
    // fast mover; sorting on days alone would lead with a single stale screw.
    entries.sort((a, b) {
      final byBand = _bandRank(b.band).compareTo(_bandRank(a.band));
      if (byBand != 0) return byBand;
      return b.valueAtRest.compareTo(a.valueAtRest);
    });

    return DeadStockReport(
      entries: entries,
      windowDays: windowDays,
      staleAfterDays: staleAfterDays,
      deadAfterDays: deadAfterDays,
      totalValueAtRest: totalValue,
      deadValue: deadValue,
      staleValue: staleValue,
      bandCounts: counts,
      transactionsCovered: covered,
    );
  }

  static MovementBand _bandFor({
    required int? daysSinceLastSale,
    required int staleAfterDays,
    required int deadAfterDays,
  }) {
    if (daysSinceLastSale == null) return MovementBand.neverSold;
    if (daysSinceLastSale >= deadAfterDays) return MovementBand.dead;
    if (daysSinceLastSale >= staleAfterDays) return MovementBand.stale;
    if (daysSinceLastSale >= staleAfterDays ~/ 2) return MovementBand.slowing;
    return MovementBand.fresh;
  }

  static int _bandRank(MovementBand band) => switch (band) {
    MovementBand.fresh => 0,
    MovementBand.slowing => 1,
    MovementBand.stale => 2,
    MovementBand.dead => 3,
    MovementBand.neverSold => 4,
  };

  static String bandLabel(MovementBand band) => switch (band) {
    MovementBand.fresh => 'Moving',
    MovementBand.slowing => 'Slowing',
    MovementBand.stale => 'Stale',
    MovementBand.dead => 'Dead',
    MovementBand.neverSold => 'Never sold',
  };

  static String bandDescription(MovementBand band) => switch (band) {
    MovementBand.fresh => 'Sold recently and still turning over',
    MovementBand.slowing => 'Demand has thinned but has not stopped',
    MovementBand.stale => 'No sale for long enough to be worth reviewing',
    MovementBand.dead => 'No sale in the dead-stock window — capital at rest',
    MovementBand.neverSold => 'No outbound movement on record at all',
  };
}
