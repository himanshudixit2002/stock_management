import '../models/purchase_order_model.dart';
import '../models/vendor_model.dart';

/// One supplier, measured against their own purchase orders.
class VendorScore {
  const VendorScore({
    required this.vendorId,
    required this.vendorName,
    required this.orderCount,
    required this.completedCount,
    required this.openCount,
    required this.onTimeCount,
    required this.lateCount,
    required this.orderedUnits,
    required this.receivedUnits,
    required this.totalSpend,
    required this.averageLeadTimeDays,
    required this.promisedLeadTimeDays,
    required this.priceTrendPercent,
    required this.score,
  });

  final String vendorId;
  final String vendorName;

  /// Orders raised on this vendor, cancellations excluded.
  final int orderCount;

  /// Orders that have actually been received, fully or in part.
  final int completedCount;

  final int openCount;
  final int onTimeCount;
  final int lateCount;

  final int orderedUnits;
  final int receivedUnits;
  final double totalSpend;

  /// Days from raising the order to receiving it. Null until something arrives.
  final double? averageLeadTimeDays;

  /// What the vendor record claims, for comparison.
  final int promisedLeadTimeDays;

  /// Weighted mean change in unit price across products ordered more than once,
  /// as a percentage. Positive means prices are rising.
  final double priceTrendPercent;

  /// 0..100. Null when there is not enough history to judge — three received
  /// orders. Grading a supplier on one delivery is noise, not a scorecard.
  final double? score;

  double get onTimeRate {
    final judged = onTimeCount + lateCount;
    if (judged <= 0) return 0;
    return onTimeCount / judged;
  }

  /// Received units as a share of what was ordered on completed orders.
  double get fillRate {
    if (orderedUnits <= 0) return 0;
    final value = receivedUnits / orderedUnits;
    return value > 1 ? 1 : value;
  }

  /// Positive when they take longer than they promise.
  double? get leadTimeVariance {
    final actual = averageLeadTimeDays;
    if (actual == null || promisedLeadTimeDays <= 0) return null;
    return actual - promisedLeadTimeDays;
  }

  bool get isRated => score != null;

  /// A–D, or "—" when unrated.
  String get grade {
    final value = score;
    if (value == null) return '—';
    if (value >= 85) return 'A';
    if (value >= 70) return 'B';
    if (value >= 55) return 'C';
    return 'D';
  }
}

/// Every vendor, ranked.
class VendorScorecard {
  const VendorScorecard({
    required this.scores,
    required this.ordersConsidered,
    required this.totalSpend,
    required this.windowDays,
  });

  /// Best first; unrated vendors last.
  final List<VendorScore> scores;

  final int ordersConsidered;
  final double totalSpend;
  final int windowDays;

  List<VendorScore> get rated => scores.where((s) => s.isRated).toList();

  VendorScore? get best {
    final list = rated;
    return list.isEmpty ? null : list.first;
  }

  VendorScore? get worst {
    final list = rated;
    return list.isEmpty ? null : list.last;
  }

  static const VendorScorecard empty = VendorScorecard(
    scores: [],
    ordersConsidered: 0,
    totalSpend: 0,
    windowDays: 0,
  );
}

/// Grades suppliers from the purchase orders already in the workspace.
///
/// Pure and synchronous. Every fact it needs is recorded the moment an order is
/// raised and received — when delivery was expected, when it arrived, how much
/// of it arrived, what it cost — and nothing in the app reads them back. The
/// vendor record's `rating` is typed in by a human and its `leadTimeDays` is a
/// promise; this measures both against what happened.
class VendorScorecardService {
  VendorScorecardService._();

  static const int defaultWindowDays = 365;

  /// Received orders needed before a vendor is graded at all.
  static const int minimumOrdersToRate = 3;

  static VendorScorecard analyse({
    required List<VendorModel> vendors,
    required List<PurchaseOrderModel> orders,
    int windowDays = defaultWindowDays,
    DateTime? asOf,
  }) {
    final now = asOf ?? DateTime.now();
    final cutoff = now.subtract(Duration(days: windowDays));

    final byVendor = <String, List<PurchaseOrderModel>>{};
    var considered = 0;
    var totalSpend = 0.0;

    for (final order in orders) {
      if (order.status == POStatus.cancelled) continue;
      if (order.createdAt.isBefore(cutoff)) continue;
      if (order.vendorId.isEmpty) continue;
      byVendor.putIfAbsent(order.vendorId, () => []).add(order);
      considered++;
      totalSpend += order.totalAmount;
    }

    final names = {for (final v in vendors) v.id: v.name};
    final promised = {for (final v in vendors) v.id: v.leadTimeDays};

    final scores = <VendorScore>[];
    for (final entry in byVendor.entries) {
      scores.add(
        _scoreVendor(
          vendorId: entry.key,
          vendorName: names[entry.key] ?? entry.value.first.vendorName,
          promisedLeadTimeDays: promised[entry.key] ?? 0,
          orders: entry.value,
        ),
      );
    }

    scores.sort((a, b) {
      if (a.isRated != b.isRated) return a.isRated ? -1 : 1;
      if (a.isRated && b.isRated) {
        final byScore = b.score!.compareTo(a.score!);
        if (byScore != 0) return byScore;
      }
      return b.totalSpend.compareTo(a.totalSpend);
    });

    return VendorScorecard(
      scores: scores,
      ordersConsidered: considered,
      totalSpend: totalSpend,
      windowDays: windowDays,
    );
  }

  static VendorScore _scoreVendor({
    required String vendorId,
    required String vendorName,
    required int promisedLeadTimeDays,
    required List<PurchaseOrderModel> orders,
  }) {
    var completed = 0;
    var open = 0;
    var onTime = 0;
    var late = 0;
    var orderedUnits = 0;
    var receivedUnits = 0;
    var spend = 0.0;
    var leadTimeSum = 0;
    var leadTimeCount = 0;

    // productId -> prices in the order they were quoted, for the trend.
    final priceHistory = <String, List<double>>{};
    final sortedOrders = [...orders]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    for (final order in sortedOrders) {
      spend += order.totalAmount;
      final received = order.receivedDate;

      if (received != null) {
        completed++;
        // Expected dates default to a real date on every order, so this is a
        // fair comparison rather than a missing-data guess.
        if (received.isAfter(order.expectedDate)) {
          late++;
        } else {
          onTime++;
        }
        final days = received.difference(order.createdAt).inDays;
        if (days >= 0) {
          leadTimeSum += days;
          leadTimeCount++;
        }
        for (final item in order.items) {
          orderedUnits += item.quantity;
          receivedUnits += item.receivedQuantity;
        }
      } else {
        open++;
      }

      for (final item in order.items) {
        if (item.productId.isEmpty || item.unitPrice <= 0) continue;
        priceHistory.putIfAbsent(item.productId, () => []).add(item.unitPrice);
      }
    }

    // Price movement: first quoted price against the latest, weighted by how
    // many quotes there are, so one repriced staple outweighs a one-off.
    var weightedChange = 0.0;
    var weight = 0.0;
    for (final prices in priceHistory.values) {
      if (prices.length < 2) continue;
      final first = prices.first;
      final last = prices.last;
      if (first <= 0) continue;
      final change = ((last - first) / first) * 100;
      weightedChange += change * prices.length;
      weight += prices.length;
    }
    final priceTrend = weight <= 0 ? 0.0 : weightedChange / weight;

    final averageLeadTime =
        leadTimeCount == 0 ? null : leadTimeSum / leadTimeCount;

    double? score;
    if (completed >= minimumOrdersToRate) {
      final judged = onTime + late;
      final onTimeRate = judged <= 0 ? 0.0 : onTime / judged;
      final fill = orderedUnits <= 0
          ? 0.0
          : (receivedUnits / orderedUnits).clamp(0.0, 1.0);
      // Price stability is worth less than delivery: a supplier who is cheap
      // and never turns up is not a good supplier. A 10% rise costs the whole
      // price component.
      final stability = priceTrend <= 0
          ? 1.0
          : (1 - (priceTrend / 10)).clamp(0.0, 1.0);
      score = (onTimeRate * 45) + (fill * 40) + (stability * 15);
    }

    return VendorScore(
      vendorId: vendorId,
      vendorName: vendorName,
      orderCount: orders.length,
      completedCount: completed,
      openCount: open,
      onTimeCount: onTime,
      lateCount: late,
      orderedUnits: orderedUnits,
      receivedUnits: receivedUnits,
      totalSpend: spend,
      averageLeadTimeDays: averageLeadTime,
      promisedLeadTimeDays: promisedLeadTimeDays,
      priceTrendPercent: priceTrend,
      score: score,
    );
  }
}
