import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../config/theme.dart';
import '../../models/product_model.dart';
import '../../models/stock_transaction_model.dart';
import '../../providers/product_provider.dart';
import '../../providers/stock_provider.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/empty_state_widget.dart';
import '../../config/permissions.dart';
import '../../widgets/permission_gate.dart';
import '../../utils/responsive.dart';
import '../../widgets/shimmer_loading.dart';

class StockForecastScreen extends StatefulWidget {
  const StockForecastScreen({super.key});

  @override
  State<StockForecastScreen> createState() => _StockForecastScreenState();
}

class _StockForecastScreenState extends State<StockForecastScreen> {
  ProductModel? _selectedProduct;
  String _productSearch = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ProductProvider>().loadAnalytics();
    });
  }

  List<_AtRiskProduct> _computeAtRisk(
    List<ProductModel> products,
    List<StockTransactionModel> transactions,
  ) {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));

    final stockOutByProduct = <String, int>{};
    for (final t in transactions) {
      if (t.type == TransactionType.stockOut && t.date.isAfter(thirtyDaysAgo)) {
        stockOutByProduct[t.productId] =
            (stockOutByProduct[t.productId] ?? 0) + t.quantity;
      }
    }

    final atRisk = <_AtRiskProduct>[];
    for (final p in products) {
      final totalOut = stockOutByProduct[p.id] ?? 0;
      final avgDaily = totalOut / 30.0;
      if (avgDaily <= 0) continue;
      final daysLeft = (p.quantity / avgDaily).floor();
      if (daysLeft <= 14) {
        atRisk.add(
          _AtRiskProduct(
            product: p,
            avgDailyUsage: avgDaily,
            daysUntilStockout: daysLeft,
            projectedDate: now.add(Duration(days: daysLeft)),
          ),
        );
      }
    }
    atRisk.sort((a, b) => a.daysUntilStockout.compareTo(b.daysUntilStockout));
    return atRisk;
  }

  _ForecastData? _buildForecastData(List<StockTransactionModel> transactions) {
    if (_selectedProduct == null) return null;
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));

    final relevantTxns =
        transactions
            .where(
              (t) =>
                  t.productId == _selectedProduct!.id &&
                  t.date.isAfter(thirtyDaysAgo),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));

    int totalOut = 0;
    for (final t in relevantTxns) {
      if (t.type == TransactionType.stockOut ||
          t.type == TransactionType.damage) {
        totalOut += t.quantity;
      }
    }

    final avgDailyUsage = totalOut / 30.0;
    final currentQty = _selectedProduct!.quantity;
    final daysLeft = avgDailyUsage > 0
        ? (currentQty / avgDailyUsage).floor()
        : 999;
    final projectedDate = avgDailyUsage > 0
        ? now.add(Duration(days: daysLeft))
        : null;

    // Build historical stock level points (approximate from transactions)
    final historicalSpots = <FlSpot>[];
    final dailyChanges = <int, int>{};

    for (final t in relevantTxns) {
      final dayIndex = t.date.difference(thirtyDaysAgo).inDays.clamp(0, 30);
      final delta = switch (t.type) {
        TransactionType.stockIn || TransactionType.adjustment => t.quantity,
        TransactionType.stockOut || TransactionType.damage => -t.quantity,
        TransactionType.transfer ||
        TransactionType.hold ||
        TransactionType.holdRelease => 0,
      };
      dailyChanges[dayIndex] = (dailyChanges[dayIndex] ?? 0) + delta;
    }

    // Reconstruct backwards from current qty
    int qty = currentQty;
    final dailyLevels = List.filled(31, currentQty);
    for (int day = 30; day >= 0; day--) {
      dailyLevels[day] = qty;
      if (dailyChanges.containsKey(day)) {
        qty -= dailyChanges[day]!;
      }
    }
    for (int i = 0; i <= 30; i++) {
      historicalSpots.add(
        FlSpot(i.toDouble(), math.max(0, dailyLevels[i].toDouble()).toDouble()),
      );
    }

    // Build projected line
    final projectedSpots = <FlSpot>[FlSpot(30.0, currentQty.toDouble())];
    for (int d = 1; d <= 30; d++) {
      final projected = (currentQty - avgDailyUsage * d)
          .clamp(0, double.infinity)
          .toDouble();
      projectedSpots.add(FlSpot((30 + d).toDouble(), projected));
    }

    return _ForecastData(
      historicalSpots: historicalSpots,
      projectedSpots: projectedSpots,
      avgDailyUsage: avgDailyUsage,
      daysUntilStockout: daysLeft,
      projectedDate: projectedDate,
      currentQty: currentQty,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewStockForecast,
      featureName: 'Stock Forecast',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {

    final productProvider = context.watch<ProductProvider>();
    final products = productProvider.analyticsProducts;
    final isLoading = productProvider.isLoadingAnalytics;
    final transactions = context.watch<StockProvider>().allTransactions;
    final atRiskProducts = _computeAtRisk(products, transactions);
    final forecast = _buildForecastData(transactions);

    final filteredProducts = _productSearch.isEmpty
        ? products.take(50).toList()
        : products
              .where(
                (p) =>
                    p.name.toLowerCase().contains(_productSearch.toLowerCase()),
              )
              .take(50)
              .toList();

    return Container(
      decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const AppBarTitleRow(
            icon: Icons.trending_down_rounded,
            color: AppTheme.infoColor,
            title: 'Stock Forecast',
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Responsive.contentMaxWidth(context),
            ),
            child: isLoading && products.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ShimmerLoading(layout: ShimmerLayout.stat),
                        SizedBox(height: 16),
                        Text('Loading product data...'),
                      ],
                    ),
                  )
                : ListView(
                    padding: EdgeInsets.symmetric(
                      horizontal: Responsive.horizontalPadding(context),
                      vertical: 16,
                    ),
                    children: [
                      if (atRiskProducts.isNotEmpty) ...[
                        GlassPanel(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    color: AppTheme.dangerColor,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'At Risk (≤14 days)',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.dangerColor,
                                        ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.dangerColor.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${atRiskProducts.length}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.dangerColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ...atRiskProducts
                                  .take(5)
                                  .map(
                                    (item) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 32,
                                            height: 32,
                                            decoration: BoxDecoration(
                                              color:
                                                  (item.daysUntilStockout <= 3
                                                          ? AppTheme.dangerColor
                                                          : AppTheme
                                                                .warningColor)
                                                      .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Center(
                                              child: Text(
                                                '${item.daysUntilStockout}d',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color:
                                                      item.daysUntilStockout <=
                                                          3
                                                      ? AppTheme.dangerColor
                                                      : AppTheme.warningColor,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              item.product.name,
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: AppTheme.textPri(
                                                  context,
                                                ),
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Text(
                                            'Qty: ${item.product.quantity}',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: AppTheme.textSec(context),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      GlassPanel(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Select Product',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              decoration: InputDecoration(
                                hintText: 'Search product...',
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon: _selectedProduct != null
                                    ? IconButton(
                                        icon: const Icon(Icons.clear_rounded),
                                        onPressed: () => setState(() {
                                          _selectedProduct = null;
                                          _productSearch = '';
                                        }),
                                      )
                                    : null,
                              ),
                              onChanged: (v) =>
                                  setState(() => _productSearch = v),
                            ),
                            if (_selectedProduct != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: AppTheme.primaryColor,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _selectedProduct!.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.primaryColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (_selectedProduct == null &&
                                _productSearch.isNotEmpty)
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxHeight: 200,
                                ),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: filteredProducts.length,
                                  itemBuilder: (_, i) {
                                    final p = filteredProducts[i];
                                    return ListTile(
                                      dense: true,
                                      title: Text(p.name),
                                      subtitle: Text(
                                        'Qty: ${p.quantity} ${p.unit}',
                                      ),
                                      onTap: () => setState(() {
                                        _selectedProduct = p;
                                        _productSearch = '';
                                      }),
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (forecast != null) ...[
                        const SizedBox(height: 16),
                        GlassPanel(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              _ForecastStat(
                                label: 'Current Stock',
                                value: '${forecast.currentQty}',
                                color: AppTheme.primaryColor,
                              ),
                              _ForecastStat(
                                label: 'Avg Daily Use',
                                value: forecast.avgDailyUsage.toStringAsFixed(
                                  1,
                                ),
                                color: AppTheme.infoColor,
                              ),
                              _ForecastStat(
                                label: 'Days Left',
                                value: forecast.daysUntilStockout >= 999
                                    ? '∞'
                                    : '${forecast.daysUntilStockout}',
                                color: forecast.daysUntilStockout <= 7
                                    ? AppTheme.dangerColor
                                    : forecast.daysUntilStockout <= 14
                                    ? AppTheme.warningColor
                                    : AppTheme.successColor,
                              ),
                              _ForecastStat(
                                label: 'Stockout Date',
                                value: forecast.projectedDate != null
                                    ? DateFormat(
                                        'MMM d',
                                      ).format(forecast.projectedDate!)
                                    : 'N/A',
                                color: AppTheme.textPri(context),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        GlassPanel(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Stock Level Forecast',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Past 30 days + 30 day projection',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                height: 220,
                                child: LineChart(
                                  LineChartData(
                                    gridData: FlGridData(
                                      show: true,
                                      drawVerticalLine: false,
                                      horizontalInterval: _chartInterval(
                                        forecast,
                                      ),
                                      getDrawingHorizontalLine: (v) => FlLine(
                                        color: AppTheme.dividerC(context),
                                        strokeWidth: 1,
                                      ),
                                    ),
                                    titlesData: FlTitlesData(
                                      rightTitles: const AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: false,
                                        ),
                                      ),
                                      topTitles: const AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: false,
                                        ),
                                      ),
                                      leftTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          reservedSize: 40,
                                          getTitlesWidget: (v, meta) => Text(
                                            v.toInt().toString(),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: AppTheme.textSec(context),
                                            ),
                                          ),
                                        ),
                                      ),
                                      bottomTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          interval: 15,
                                          getTitlesWidget: (v, meta) {
                                            final day = v.toInt();
                                            if (day == 0)
                                              return Text(
                                                '30d ago',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  color: AppTheme.textSec(
                                                    context,
                                                  ),
                                                ),
                                              );
                                            if (day == 30)
                                              return Text(
                                                'Today',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  color: AppTheme.textSec(
                                                    context,
                                                  ),
                                                ),
                                              );
                                            if (day == 60)
                                              return Text(
                                                '+30d',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  color: AppTheme.textSec(
                                                    context,
                                                  ),
                                                ),
                                              );
                                            return const SizedBox.shrink();
                                          },
                                        ),
                                      ),
                                    ),
                                    borderData: FlBorderData(show: false),
                                    lineBarsData: [
                                      LineChartBarData(
                                        spots: forecast.historicalSpots,
                                        isCurved: true,
                                        color: AppTheme.primaryColor,
                                        barWidth: 2.5,
                                        dotData: const FlDotData(show: false),
                                        belowBarData: BarAreaData(
                                          show: true,
                                          color: AppTheme.primaryColor
                                              .withValues(alpha: 0.08),
                                        ),
                                      ),
                                      LineChartBarData(
                                        spots: forecast.projectedSpots,
                                        isCurved: false,
                                        color: AppTheme.dangerColor,
                                        barWidth: 2,
                                        dotData: const FlDotData(show: false),
                                        dashArray: [6, 4],
                                        belowBarData: BarAreaData(
                                          show: true,
                                          color: AppTheme.dangerColor
                                              .withValues(alpha: 0.05),
                                        ),
                                      ),
                                    ],
                                    extraLinesData: ExtraLinesData(
                                      verticalLines: [
                                        VerticalLine(
                                          x: 30,
                                          color: AppTheme.textSec(
                                            context,
                                          ).withValues(alpha: 0.3),
                                          strokeWidth: 1,
                                          dashArray: [4, 4],
                                        ),
                                      ],
                                    ),
                                    minY: 0,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _LegendDot(
                                    color: AppTheme.primaryColor,
                                    label: 'Actual',
                                  ),
                                  const SizedBox(width: 20),
                                  _LegendDot(
                                    color: AppTheme.dangerColor,
                                    label: 'Projected',
                                    dashed: true,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_selectedProduct == null && atRiskProducts.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 48),
                          child: EmptyStateWidget(
                            icon: Icons.analytics_outlined,
                            title: 'Select a Product',
                            subtitle:
                                'Choose a product above to see its stock forecast.',
                          ),
                        ),
                      const SizedBox(height: 24),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  double _chartInterval(_ForecastData data) {
    final maxVal = [
      ...data.historicalSpots.map((s) => s.y),
      ...data.projectedSpots.map((s) => s.y),
    ].reduce(math.max);
    if (maxVal <= 10) return 2;
    if (maxVal <= 50) return 10;
    if (maxVal <= 200) return 50;
    return 100;
  }
}

class _ForecastData {
  final List<FlSpot> historicalSpots;
  final List<FlSpot> projectedSpots;
  final double avgDailyUsage;
  final int daysUntilStockout;
  final DateTime? projectedDate;
  final int currentQty;

  _ForecastData({
    required this.historicalSpots,
    required this.projectedSpots,
    required this.avgDailyUsage,
    required this.daysUntilStockout,
    required this.projectedDate,
    required this.currentQty,
  });
}

class _AtRiskProduct {
  final ProductModel product;
  final double avgDailyUsage;
  final int daysUntilStockout;
  final DateTime projectedDate;

  _AtRiskProduct({
    required this.product,
    required this.avgDailyUsage,
    required this.daysUntilStockout,
    required this.projectedDate,
  });
}

class _ForecastStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _ForecastStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: AppTheme.textSec(context)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final bool dashed;

  const _LegendDot({
    required this.color,
    required this.label,
    this.dashed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 3,
          decoration: BoxDecoration(
            color: dashed ? Colors.transparent : color,
            border: dashed
                ? Border(bottom: BorderSide(color: color, width: 2))
                : null,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: AppTheme.textSec(context)),
        ),
      ],
    );
  }
}
