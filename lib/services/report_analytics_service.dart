import 'dart:math';
import '../models/stock_transaction_model.dart';
import '../models/product_model.dart';

/// Represents a period-over-period comparison result for a specific metric.
class MetricDelta {
  final double current;
  final double previous;
  final double absoluteDelta;
  final double percentChange; // e.g. +14.5 or -5.2
  final bool isPositive;

  const MetricDelta({
    required this.current,
    required this.previous,
    required this.absoluteDelta,
    required this.percentChange,
    required this.isPositive,
  });

  factory MetricDelta.compute(double current, double previous) {
    final diff = current - previous;
    final pct = previous != 0 ? (diff / previous) * 100 : (current > 0 ? 100.0 : 0.0);
    return MetricDelta(
      current: current,
      previous: previous,
      absoluteDelta: diff,
      percentChange: pct,
      isPositive: diff >= 0,
    );
  }
}

/// Anomaly alert data model for operational risk flagging.
enum AnomalySeverity { info, warning, danger }

class AnomalyAlert {
  final String id;
  final String title;
  final String description;
  final AnomalySeverity severity;
  final String actionLabel;
  final String? targetId;

  const AnomalyAlert({
    required this.id,
    required this.title,
    required this.description,
    required this.severity,
    required this.actionLabel,
    this.targetId,
  });
}

/// Forecast metrics for product run-rate & inventory health.
enum HealthQuadrant { overstocked, optimal, atRisk, deadStock }

class ProductHealthForecast {
  final ProductModel product;
  final double dailyBurnRate;
  final double daysOfSupply;
  final HealthQuadrant quadrant;
  final int totalOutInPeriod;
  final int totalInInPeriod;

  const ProductHealthForecast({
    required this.product,
    required this.dailyBurnRate,
    required this.daysOfSupply,
    required this.quadrant,
    required this.totalOutInPeriod,
    required this.totalInInPeriod,
  });
}

/// Dynamic Row for the Custom Report Builder.
class CustomReportRow {
  final String groupName;
  final double salesRevenue;
  final double estimatedCost;
  final double profit;
  final double profitMarginPct;
  final int stockInQty;
  final int stockOutQty;
  final int damageQty;
  final double damageValue;

  const CustomReportRow({
    required this.groupName,
    required this.salesRevenue,
    required this.estimatedCost,
    required this.profit,
    required this.profitMarginPct,
    required this.stockInQty,
    required this.stockOutQty,
    required this.damageQty,
    required this.damageValue,
  });
}

/// High-performance analytics service for the Reports module.
class ReportAnalyticsService {
  ReportAnalyticsService._internal();
  static final ReportAnalyticsService _instance = ReportAnalyticsService._internal();
  factory ReportAnalyticsService() => _instance;

  /// Calculates Period-Over-Period deltas between [currentTx] and [previousTx].
  Map<String, MetricDelta> computePeriodOverPeriodDeltas({
    required List<StockTransactionModel> currentTx,
    required List<StockTransactionModel> previousTx,
    required Map<String, ProductModel> productMap,
  }) {
    double currentOutVal = 0, currentDmgVal = 0;
    int currentInQty = 0, currentOutQty = 0, currentDmgQty = 0;

    for (final tx in currentTx) {
      final price = productMap[tx.productId]?.sellingPrice ?? 0.0;
      final cost = productMap[tx.productId]?.costPrice ?? 0.0;
      final val = tx.quantity * (price > 0 ? price : cost);

      switch (tx.type) {
        case TransactionType.stockIn:
          currentInQty += tx.quantity;
          break;
        case TransactionType.stockOut:
          currentOutQty += tx.quantity;
          currentOutVal += val;
          break;
        case TransactionType.damage:
          currentDmgQty += tx.quantity;
          currentDmgVal += val;
          break;
        default:
          break;
      }
    }

    double prevOutVal = 0, prevDmgVal = 0;
    int prevInQty = 0, prevOutQty = 0, prevDmgQty = 0;

    for (final tx in previousTx) {
      final price = productMap[tx.productId]?.sellingPrice ?? 0.0;
      final cost = productMap[tx.productId]?.costPrice ?? 0.0;
      final val = tx.quantity * (price > 0 ? price : cost);

      switch (tx.type) {
        case TransactionType.stockIn:
          prevInQty += tx.quantity;
          break;
        case TransactionType.stockOut:
          prevOutQty += tx.quantity;
          prevOutVal += val;
          break;
        case TransactionType.damage:
          prevDmgQty += tx.quantity;
          prevDmgVal += val;
          break;
        default:
          break;
      }
    }

    final netCurrentQty = currentInQty - currentOutQty - currentDmgQty;
    final netPrevQty = prevInQty - prevOutQty - prevDmgQty;

    return {
      'stockOutValue': MetricDelta.compute(currentOutVal, prevOutVal),
      'stockOutQty': MetricDelta.compute(currentOutQty.toDouble(), prevOutQty.toDouble()),
      'stockInQty': MetricDelta.compute(currentInQty.toDouble(), prevInQty.toDouble()),
      'damageQty': MetricDelta.compute(currentDmgQty.toDouble(), prevDmgQty.toDouble()),
      'damageValue': MetricDelta.compute(currentDmgVal, prevDmgVal),
      'netMovement': MetricDelta.compute(netCurrentQty.toDouble(), netPrevQty.toDouble()),
    };
  }

  /// Generates AI Natural Language Insights from transaction trends.
  List<String> generateAiExecutiveInsights({
    required List<StockTransactionModel> currentTx,
    required List<ProductModel> products,
    required Map<String, MetricDelta> deltas,
  }) {
    final insights = <String>[];

    final outValDelta = deltas['stockOutValue'];
    if (outValDelta != null) {
      if (outValDelta.percentChange > 10) {
        insights.add(
          '📈 Sales volume grew strongly by ${outValDelta.percentChange.toStringAsFixed(1)}% compared to the prior period.',
        );
      } else if (outValDelta.percentChange < -10) {
        insights.add(
          '📉 Sales volume contracted by ${outValDelta.percentChange.abs().toStringAsFixed(1)}% compared to the prior period.',
        );
      } else {
        insights.add('📊 Outbound demand remained steady with minimal variance vs prior period.');
      }
    }

    final lowStockCount = products.where((p) => p.quantity <= p.lowStockThreshold && p.quantity > 0).length;
    final outCount = products.where((p) => p.quantity <= 0).length;

    if (outCount > 0 || lowStockCount > 0) {
      insights.add(
        '⚠️ $outCount products are completely out of stock and $lowStockCount are below safety thresholds.',
      );
    } else {
      insights.add('✅ Healthy inventory levels across all registered catalog items.');
    }

    final dmgDelta = deltas['damageQty'];
    if (dmgDelta != null && dmgDelta.current > 0) {
      if (dmgDelta.percentChange > 20) {
        insights.add(
          '🚨 Damaged stock items increased by ${dmgDelta.percentChange.toStringAsFixed(1)}%. Review handling procedures.',
        );
      } else {
        insights.add('📦 Damaged stock accounts for ${dmgDelta.current.toInt()} units in the current window.');
      }
    }

    return insights;
  }

  /// Scans for operational anomalies & safety hazards.
  List<AnomalyAlert> detectAnomalies({
    required List<StockTransactionModel> transactions,
    required List<ProductModel> products,
    required int periodDays,
  }) {
    final alerts = <AnomalyAlert>[];

    final outMap = <String, int>{};
    for (final tx in transactions) {
      if (tx.type == TransactionType.stockOut) {
        outMap[tx.productId] = (outMap[tx.productId] ?? 0) + tx.quantity;
      }
    }

    int criticalSupplyCount = 0;
    for (final product in products) {
      final movedOut = outMap[product.id] ?? 0;
      final dailyBurn = movedOut / max(periodDays, 1);
      if (dailyBurn > 0) {
        final daysOfSupply = product.quantity / dailyBurn;
        if (daysOfSupply < 5 && product.quantity > 0) {
          criticalSupplyCount++;
        }
      }
    }

    if (criticalSupplyCount > 0) {
      alerts.add(
        AnomalyAlert(
          id: 'critical_stockout',
          title: 'Immediate Stockout Risk',
          description: '$criticalSupplyCount fast-moving items will run out of stock in under 5 days.',
          severity: AnomalySeverity.danger,
          actionLabel: 'View Forecast',
        ),
      );
    }

    int totalDamage = 0;
    int totalOut = 0;
    for (final tx in transactions) {
      if (tx.type == TransactionType.damage) totalDamage += tx.quantity;
      if (tx.type == TransactionType.stockOut) totalOut += tx.quantity;
    }

    if (totalOut > 0 && (totalDamage / totalOut) > 0.08) {
      final pct = ((totalDamage / totalOut) * 100).toStringAsFixed(1);
      alerts.add(
        AnomalyAlert(
          id: 'high_damage_rate',
          title: 'Elevated Damage Ratio',
          description: 'Damaged items account for $pct% of outbound volume in this date range.',
          severity: AnomalySeverity.warning,
          actionLabel: 'Inspect Damage',
        ),
      );
    }

    int deadStockCount = 0;
    for (final p in products) {
      final moved = outMap[p.id] ?? 0;
      if (moved == 0 && p.quantity > 20) {
        deadStockCount++;
      }
    }

    if (deadStockCount > 0) {
      alerts.add(
        AnomalyAlert(
          id: 'dead_stock_accumulation',
          title: 'Dead Stock Idle Inventory',
          description: '$deadStockCount products have > 20 units with 0 sales movement in $periodDays days.',
          severity: AnomalySeverity.info,
          actionLabel: 'Review Matrix',
        ),
      );
    }

    return alerts;
  }

  /// Calculates predictive stock-out run-rate forecasts for products.
  List<ProductHealthForecast> computeInventoryHealthForecasts({
    required List<StockTransactionModel> transactions,
    required List<ProductModel> products,
    required int periodDays,
  }) {
    final outMap = <String, int>{};
    final inMap = <String, int>{};

    for (final tx in transactions) {
      if (tx.type == TransactionType.stockOut) {
        outMap[tx.productId] = (outMap[tx.productId] ?? 0) + tx.quantity;
      } else if (tx.type == TransactionType.stockIn) {
        inMap[tx.productId] = (inMap[tx.productId] ?? 0) + tx.quantity;
      }
    }

    final forecasts = <ProductHealthForecast>[];

    for (final product in products) {
      final movedOut = outMap[product.id] ?? 0;
      final movedIn = inMap[product.id] ?? 0;

      final dailyBurn = movedOut / max(periodDays, 1);
      final daysOfSupply = dailyBurn > 0 ? (product.quantity / dailyBurn) : (product.quantity > 0 ? 999.0 : 0.0);

      HealthQuadrant quadrant;
      if (product.quantity <= 0 || daysOfSupply < 14) {
        quadrant = HealthQuadrant.atRisk;
      } else if (movedOut == 0 && product.quantity > 0) {
        quadrant = HealthQuadrant.deadStock;
      } else if (daysOfSupply > 90 && product.quantity > 15) {
        quadrant = HealthQuadrant.overstocked;
      } else {
        quadrant = HealthQuadrant.optimal;
      }

      forecasts.add(
        ProductHealthForecast(
          product: product,
          dailyBurnRate: dailyBurn,
          daysOfSupply: daysOfSupply,
          quadrant: quadrant,
          totalOutInPeriod: movedOut,
          totalInInPeriod: movedIn,
        ),
      );
    }

    forecasts.sort((a, b) => a.daysOfSupply.compareTo(b.daysOfSupply));
    return forecasts;
  }

  /// Aggregates transactions into custom report rows based on selected grouping dimension.
  List<CustomReportRow> generateCustomReport({
    required List<StockTransactionModel> transactions,
    required Map<String, ProductModel> productMap,
    required String groupBy,
  }) {
    final Map<String, Map<String, double>> groupData = {};

    for (final tx in transactions) {
      String key = 'Unassigned';
      if (groupBy == 'category') {
        final p = productMap[tx.productId];
        key = (p != null && p.categoryName.isNotEmpty) ? p.categoryName : 'Uncategorized';
      } else if (groupBy == 'user') {
        key = tx.userName.isNotEmpty ? tx.userName : (tx.userId.isNotEmpty ? tx.userId : 'System');
      } else if (groupBy == 'vendor') {
        key = tx.vendorName.isNotEmpty ? tx.vendorName : 'No Vendor';
      } else if (groupBy == 'type') {
        key = tx.typeLabel;
      }

      groupData.putIfAbsent(key, () => {
        'salesRevenue': 0.0,
        'cost': 0.0,
        'stockInQty': 0.0,
        'stockOutQty': 0.0,
        'damageQty': 0.0,
        'damageVal': 0.0,
      });

      final row = groupData[key]!;
      final p = productMap[tx.productId];
      final price = p?.sellingPrice ?? 0.0;
      final cost = p?.costPrice ?? 0.0;

      if (tx.type == TransactionType.stockOut) {
        row['stockOutQty'] = row['stockOutQty']! + tx.quantity;
        row['salesRevenue'] = row['salesRevenue']! + (tx.quantity * (price > 0 ? price : cost));
        row['cost'] = row['cost']! + (tx.quantity * cost);
      } else if (tx.type == TransactionType.stockIn) {
        row['stockInQty'] = row['stockInQty']! + tx.quantity;
      } else if (tx.type == TransactionType.damage) {
        row['damageQty'] = row['damageQty']! + tx.quantity;
        row['damageVal'] = row['damageVal']! + (tx.quantity * cost);
      }
    }

    final rows = <CustomReportRow>[];
    groupData.forEach((groupName, map) {
      final revenue = map['salesRevenue']!;
      final cost = map['cost']!;
      final profit = revenue - cost;
      final marginPct = revenue > 0 ? (profit / revenue) * 100 : 0.0;

      rows.add(
        CustomReportRow(
          groupName: groupName,
          salesRevenue: revenue,
          estimatedCost: cost,
          profit: profit,
          profitMarginPct: marginPct,
          stockInQty: map['stockInQty']!.toInt(),
          stockOutQty: map['stockOutQty']!.toInt(),
          damageQty: map['damageQty']!.toInt(),
          damageValue: map['damageVal']!,
        ),
      );
    });

    rows.sort((a, b) => b.salesRevenue.compareTo(a.salesRevenue));
    return rows;
  }
}
