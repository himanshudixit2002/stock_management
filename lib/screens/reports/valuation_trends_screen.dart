import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../config/theme.dart';
import '../../providers/product_provider.dart';
import '../../providers/stock_provider.dart';
import '../../models/product_model.dart';
import '../../models/stock_transaction_model.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../utils/responsive.dart';

class ValuationTrendsScreen extends StatelessWidget {
  const ValuationTrendsScreen({super.key});

  String _fmtCurrency(double v) {
    final fmt = NumberFormat('#,##0.00');
    return '${AppTheme.currencySymbol}${fmt.format(v)}';
  }

  String _fmtCompact(double v) {
    if (v >= 1e7)
      return '${AppTheme.currencySymbol}${(v / 1e7).toStringAsFixed(1)}Cr';
    if (v >= 1e5)
      return '${AppTheme.currencySymbol}${(v / 1e5).toStringAsFixed(1)}L';
    if (v >= 1e3)
      return '${AppTheme.currencySymbol}${(v / 1e3).toStringAsFixed(1)}K';
    return '${AppTheme.currencySymbol}${v.toInt()}';
  }

  @override
  Widget build(BuildContext context) {
    final productProv = context.watch<ProductProvider>();
    final stockProv = context.watch<StockProvider>();
    final allProducts = productProv.allProducts;

    double totalCost = 0;
    double totalSelling = 0;
    final byCategoryVal = <String, _ValEntry>{};
    final byLocation = <String, double>{};

    for (final p in allProducts) {
      totalCost += p.totalCostValue;
      totalSelling += p.totalStockValue;

      final cat = p.categoryName.isNotEmpty ? p.categoryName : 'Uncategorized';
      byCategoryVal.putIfAbsent(cat, () => _ValEntry());
      byCategoryVal[cat]!.cost += p.totalCostValue;
      byCategoryVal[cat]!.selling += p.totalStockValue;

      for (final loc in p.locationQuantities.entries) {
        if (loc.value > 0) {
          byLocation[loc.key] =
              (byLocation[loc.key] ?? 0) + p.costPrice * loc.value;
        }
      }
    }

    final potentialProfit = totalSelling - totalCost;

    final sortedProducts = List<ProductModel>.from(allProducts)
      ..sort((a, b) => b.totalCostValue.compareTo(a.totalCostValue));
    final top10 = sortedProducts.take(10).toList();

    final now = DateTime.now();
    final thisMonthStart = DateTime(now.year, now.month, 1);
    final lastMonthStart = DateTime(now.year, now.month - 1, 1);
    final lastMonthEnd = thisMonthStart.subtract(const Duration(days: 1));

    final thisMonthTxns = stockProv.allTransactions.where(
      (t) =>
          !t.date.isBefore(thisMonthStart) &&
          t.type == TransactionType.stockOut,
    );
    final lastMonthTxns = stockProv.allTransactions.where(
      (t) =>
          !t.date.isBefore(lastMonthStart) &&
          t.date.isBefore(thisMonthStart) &&
          t.type == TransactionType.stockOut,
    );

    final pMap = <String, ProductModel>{};
    for (final p in allProducts) {
      pMap[p.id] = p;
    }

    double thisMonthRev = 0;
    for (final t in thisMonthTxns) {
      final sp = pMap[t.productId]?.sellingPrice ?? 0;
      thisMonthRev += sp * t.quantity;
    }
    double lastMonthRev = 0;
    for (final t in lastMonthTxns) {
      final sp = pMap[t.productId]?.sellingPrice ?? 0;
      lastMonthRev += sp * t.quantity;
    }
    final revChange = lastMonthRev > 0
        ? ((thisMonthRev - lastMonthRev) / lastMonthRev) * 100
        : (thisMonthRev > 0 ? 100.0 : 0.0);

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: const AppBarTitleRow(
          icon: Icons.assessment_rounded,
          color: AppTheme.infoColor,
          title: 'Inventory Valuation',
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.contentMaxWidth(context),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: Responsive.horizontalPadding(context),
              vertical: 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSummaryCards(totalCost, totalSelling, potentialProfit),
                const SizedBox(height: 20),
                _buildPeriodComparison(
                  context,
                  thisMonthRev,
                  lastMonthRev,
                  revChange,
                  now,
                  lastMonthStart,
                  lastMonthEnd,
                ),
                const SizedBox(height: 20),
                _buildCategoryChart(context, byCategoryVal),
                const SizedBox(height: 20),
                _buildLocationChart(byLocation),
                const SizedBox(height: 20),
                _buildTop10List(context, top10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCards(double cost, double selling, double profit) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _ValCard(
              width: cardWidth,
              label: 'Total Cost Value',
              value: _fmtCompact(cost),
              icon: Icons.account_balance_rounded,
              color: AppTheme.primaryColor,
            ),
            _ValCard(
              width: cardWidth,
              label: 'Total Selling Value',
              value: _fmtCompact(selling),
              icon: Icons.sell_rounded,
              color: AppTheme.infoColor,
            ),
            _ValCard(
              width: cardWidth,
              label: 'Potential Profit',
              value: _fmtCompact(profit),
              icon: Icons.trending_up_rounded,
              color: profit >= 0 ? AppTheme.successColor : AppTheme.dangerColor,
            ),
            _ValCard(
              width: cardWidth,
              label: 'Margin',
              value: selling > 0
                  ? '${((selling - cost) / selling * 100).toStringAsFixed(1)}%'
                  : '0%',
              icon: Icons.percent_rounded,
              color: AppTheme.indigoColor,
            ),
          ],
        );
      },
    );
  }

  Widget _buildPeriodComparison(
    BuildContext context,
    double thisMonth,
    double lastMonth,
    double change,
    DateTime now,
    DateTime lastStart,
    DateTime lastEnd,
  ) {
    final thisLabel = DateFormat('MMMM yyyy').format(now);
    final lastLabel = DateFormat('MMMM yyyy').format(lastStart);
    final isPositive = change >= 0;

    return GlassSectionCard(
      title: 'Period Comparison',
      icon: Icons.compare_arrows_rounded,
      iconColor: AppTheme.infoColor,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      thisLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _fmtCurrency(thisMonth),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isPositive
                      ? AppTheme.successColor.withValues(alpha: 0.12)
                      : AppTheme.dangerColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPositive
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                      size: 16,
                      color: isPositive
                          ? AppTheme.successColor
                          : AppTheme.dangerColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${isPositive ? '+' : ''}${change.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isPositive
                            ? AppTheme.successColor
                            : AppTheme.dangerColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      lastLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _fmtCurrency(lastMonth),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChart(
    BuildContext context,
    Map<String, _ValEntry> data,
  ) {
    final sorted = data.entries.toList()
      ..sort((a, b) => b.value.cost.compareTo(a.value.cost));
    if (sorted.isEmpty) return const SizedBox.shrink();

    final maxVal = sorted.first.value.cost;
    final colors = [
      AppTheme.primaryColor,
      AppTheme.infoColor,
      AppTheme.successColor,
      AppTheme.warningColor,
      AppTheme.dangerColor,
      AppTheme.indigoColor,
      AppTheme.accentColor,
    ];

    return GlassSectionCard(
      title: 'Valuation by Category',
      icon: Icons.category_rounded,
      iconColor: AppTheme.primaryColor,
      child: SizedBox(
        height: max(sorted.length * 50.0, 120),
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, gIdx, rod, rIdx) {
                  if (gIdx < sorted.length) {
                    return BarTooltipItem(
                      '${sorted[gIdx].key}\n${_fmtCurrency(rod.toY)}',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    );
                  }
                  return null;
                },
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 80,
                  getTitlesWidget: (v, _) {
                    final idx = v.toInt();
                    if (idx < 0 || idx >= sorted.length) {
                      return const SizedBox.shrink();
                    }
                    return Text(
                      sorted[idx].key.length > 12
                          ? '${sorted[idx].key.substring(0, 12)}...'
                          : sorted[idx].key,
                      style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.textSec(context),
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              drawHorizontalLine: false,
              drawVerticalLine: true,
              verticalInterval: (maxVal / 4).ceilToDouble().clamp(1, 99999),
              getDrawingVerticalLine: (v) =>
                  FlLine(color: AppTheme.dividerC(context), strokeWidth: 1),
            ),
            maxY: maxVal * 1.15,
            barGroups: List.generate(sorted.length, (i) {
              return BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: sorted[i].value.cost,
                    width: 18,
                    color: colors[i % colors.length],
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(6),
                    ),
                  ),
                ],
              );
            }),
          ),
          swapAnimationDuration: const Duration(milliseconds: 250),
        ),
      ),
    );
  }

  Widget _buildLocationChart(Map<String, double> data) {
    final sorted = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (sorted.isEmpty) return const SizedBox.shrink();

    final maxVal = sorted.first.value;

    return GlassSectionCard(
      title: 'Valuation by Location',
      icon: Icons.location_on_rounded,
      iconColor: AppTheme.infoColor,
      child: Column(
        children: sorted.map((entry) {
          final fraction = maxVal > 0 ? entry.value / maxVal : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        entry.key,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      _fmtCurrency(entry.value),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.infoColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: fraction,
                    backgroundColor: AppTheme.infoColor.withValues(alpha: 0.1),
                    color: AppTheme.infoColor,
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTop10List(BuildContext context, List<ProductModel> top10) {
    if (top10.isEmpty) return const SizedBox.shrink();

    return GlassSectionCard(
      title: 'Top 10 Most Valuable Products',
      icon: Icons.star_rounded,
      iconColor: AppTheme.warningColor,
      child: Column(
        children: List.generate(top10.length, (i) {
          final p = top10[i];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: i < 3
                        ? AppTheme.warningColor.withValues(alpha: 0.15)
                        : AppTheme.dividerC(context),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: i < 3
                            ? AppTheme.warningColor
                            : AppTheme.textSec(context),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${p.quantity} ${p.unit} @ ${_fmtCurrency(p.costPrice)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSec(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  _fmtCurrency(p.totalCostValue),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _ValEntry {
  double cost = 0;
  double selling = 0;
}

class _ValCard extends StatelessWidget {
  final double width;
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _ValCard({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: GlassPanel(
        useContentVariant: true,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSec(context),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
