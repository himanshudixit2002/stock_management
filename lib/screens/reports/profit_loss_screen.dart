import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../config/theme.dart';
import '../../utils/dialogs.dart';
import '../../providers/stock_provider.dart';
import '../../providers/product_provider.dart';
import '../../models/stock_transaction_model.dart';
import '../../models/product_model.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/empty_state_widget.dart';
import '../../utils/responsive.dart';

class ProfitLossScreen extends StatefulWidget {
  const ProfitLossScreen({super.key});

  @override
  State<ProfitLossScreen> createState() => _ProfitLossScreenState();
}

class _ProfitLossScreenState extends State<ProfitLossScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _rangeDays = 30;
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  DateTimeRange get _effectiveRange {
    if (_customRange != null) return _customRange!;
    final now = DateTime.now();
    return DateTimeRange(
      start: DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: _rangeDays)),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59),
    );
  }

  List<StockTransactionModel> _stockOutInRange(StockProvider stockProv) {
    final range = _effectiveRange;
    return stockProv.allTransactions.where((t) {
      if (t.type != TransactionType.stockOut) return false;
      return !t.date.isBefore(range.start) && !t.date.isAfter(range.end);
    }).toList();
  }

  Map<String, ProductModel> _productMap(ProductProvider productProv) {
    final map = <String, ProductModel>{};
    for (final p in productProv.allProducts) {
      map[p.id] = p;
    }
    return map;
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange:
          _customRange ??
          DateTimeRange(
            start: now.subtract(Duration(days: _rangeDays)),
            end: now,
          ),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(
            context,
          ).colorScheme.copyWith(primary: AppTheme.primaryColor),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _customRange = picked;
        _rangeDays = -1;
      });
    }
  }

  String _fmtCurrency(double v) {
    final fmt = NumberFormat('#,##0.00');
    return '${AppTheme.currencySymbol}${fmt.format(v)}';
  }

  @override
  Widget build(BuildContext context) {
    final stockProv = context.watch<StockProvider>();
    final productProv = context.watch<ProductProvider>();

    final stockOuts = _stockOutInRange(stockProv);
    final pMap = _productMap(productProv);

    double totalRevenue = 0;
    double totalCost = 0;
    final byCategory = <String, _PnLEntry>{};
    final byProduct = <String, _PnLEntry>{};
    final byDay = <String, _PnLEntry>{};
    final dayFmt = DateFormat('yyyy-MM-dd');

    for (final t in stockOuts) {
      final product = pMap[t.productId];
      final sp = product?.sellingPrice ?? 0;
      final cp = product?.costPrice ?? 0;
      final rev = sp * t.quantity;
      final cost = cp * t.quantity;
      totalRevenue += rev;
      totalCost += cost;

      final cat = product?.categoryName ?? 'Uncategorized';
      byCategory.putIfAbsent(cat, () => _PnLEntry(cat));
      byCategory[cat]!.revenue += rev;
      byCategory[cat]!.cost += cost;

      final pName = t.productName.isNotEmpty ? t.productName : t.productId;
      byProduct.putIfAbsent(pName, () => _PnLEntry(pName));
      byProduct[pName]!.revenue += rev;
      byProduct[pName]!.cost += cost;

      final dayKey = dayFmt.format(t.date);
      byDay.putIfAbsent(dayKey, () => _PnLEntry(dayKey));
      byDay[dayKey]!.revenue += rev;
      byDay[dayKey]!.cost += cost;
    }

    final grossProfit = totalRevenue - totalCost;
    final margin = totalRevenue > 0 ? (grossProfit / totalRevenue) * 100 : 0.0;

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: const AppBarTitleRow(
          icon: Icons.account_balance_rounded,
          color: AppTheme.primaryColor,
          title: 'Profit & Loss',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_rounded, size: 20),
            tooltip: 'Export',
            onPressed: () {
              showInfoSnackBar(context, 'Export coming soon');
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _buildDateRangeBar(),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.contentMaxWidth(context),
          ),
          child: stockOuts.isEmpty
              ? const EmptyStateWidget(
                  icon: Icons.receipt_long_rounded,
                  title: 'No Sales Data',
                  subtitle: 'No stock-out transactions found in this period.',
                )
              : SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: Responsive.horizontalPadding(context),
                    vertical: 16,
                  ),
                  child: Column(
                    children: [
                      _buildSummaryCards(
                        totalRevenue,
                        totalCost,
                        grossProfit,
                        margin,
                      ),
                      const SizedBox(height: 20),
                      _buildTrendChart(byDay),
                      const SizedBox(height: 20),
                      _buildBreakdownTabs(byCategory, byProduct, byDay),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildDateRangeBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _RangeChip(
            label: '7 Days',
            selected: _rangeDays == 7 && _customRange == null,
            onTap: () => setState(() {
              _rangeDays = 7;
              _customRange = null;
            }),
          ),
          const SizedBox(width: 8),
          _RangeChip(
            label: '30 Days',
            selected: _rangeDays == 30 && _customRange == null,
            onTap: () => setState(() {
              _rangeDays = 30;
              _customRange = null;
            }),
          ),
          const SizedBox(width: 8),
          _RangeChip(
            label: '90 Days',
            selected: _rangeDays == 90 && _customRange == null,
            onTap: () => setState(() {
              _rangeDays = 90;
              _customRange = null;
            }),
          ),
          const SizedBox(width: 8),
          _RangeChip(
            label: _customRange != null
                ? '${DateFormat('dd MMM').format(_customRange!.start)} – ${DateFormat('dd MMM').format(_customRange!.end)}'
                : 'Custom',
            selected: _customRange != null,
            onTap: _pickCustomRange,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(
    double revenue,
    double cost,
    double profit,
    double margin,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: cardWidth,
              child: _SummaryCard(
                label: 'Total Revenue',
                value: _fmtCurrency(revenue),
                icon: Icons.trending_up_rounded,
                color: AppTheme.successColor,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _SummaryCard(
                label: 'Total Cost',
                value: _fmtCurrency(cost),
                icon: Icons.trending_down_rounded,
                color: AppTheme.dangerColor,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _SummaryCard(
                label: 'Gross Profit',
                value: _fmtCurrency(profit),
                icon: Icons.account_balance_wallet_rounded,
                color: profit >= 0
                    ? AppTheme.primaryColor
                    : AppTheme.dangerColor,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _SummaryCard(
                label: 'Margin %',
                value: '${margin.toStringAsFixed(1)}%',
                icon: Icons.percent_rounded,
                color: margin >= 20
                    ? AppTheme.successColor
                    : margin >= 0
                    ? AppTheme.warningColor
                    : AppTheme.dangerColor,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTrendChart(Map<String, _PnLEntry> byDay) {
    final sortedKeys = byDay.keys.toList()..sort();
    if (sortedKeys.isEmpty) return const SizedBox.shrink();

    final revSpots = <FlSpot>[];
    final costSpots = <FlSpot>[];
    double maxY = 0;

    for (int i = 0; i < sortedKeys.length; i++) {
      final e = byDay[sortedKeys[i]]!;
      revSpots.add(FlSpot(i.toDouble(), e.revenue));
      costSpots.add(FlSpot(i.toDouble(), e.cost));
      if (e.revenue > maxY) maxY = e.revenue;
      if (e.cost > maxY) maxY = e.cost;
    }
    if (maxY == 0) maxY = 100;

    return GlassSectionCard(
      title: 'Revenue vs Cost Trend',
      icon: Icons.show_chart_rounded,
      iconColor: AppTheme.primaryColor,
      child: Column(
        children: [
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: (maxY / 4).ceilToDouble().clamp(1, 99999),
                  getDrawingHorizontalLine: (v) =>
                      FlLine(color: AppTheme.dividerC(context), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      getTitlesWidget: (v, _) => Text(
                        _compactNumber(v),
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
                      reservedSize: 28,
                      interval: 1,
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= sortedKeys.length) {
                          return const SizedBox.shrink();
                        }
                        if (sortedKeys.length > 10 && idx % 3 != 0) {
                          return const SizedBox.shrink();
                        }
                        final d = DateTime.tryParse(sortedKeys[idx]);
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            d != null ? DateFormat('dd/MM').format(d) : '',
                            style: TextStyle(
                              fontSize: 9,
                              color: AppTheme.textSec(context),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: (sortedKeys.length - 1).toDouble().clamp(0, 99999),
                minY: 0,
                maxY: maxY * 1.15,
                lineBarsData: [
                  _line(revSpots, AppTheme.successColor),
                  _line(costSpots, AppTheme.dangerColor),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => spots.map((s) {
                      final labels = ['Revenue', 'Cost'];
                      final colors = [
                        AppTheme.successColor,
                        AppTheme.dangerColor,
                      ];
                      return LineTooltipItem(
                        '${labels[s.barIndex]}: ${_fmtCurrency(s.y)}',
                        TextStyle(
                          color: colors[s.barIndex],
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legend(AppTheme.successColor, 'Revenue'),
              const SizedBox(width: 20),
              _legend(AppTheme.dangerColor, 'Cost'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownTabs(
    Map<String, _PnLEntry> byCategory,
    Map<String, _PnLEntry> byProduct,
    Map<String, _PnLEntry> byDay,
  ) {
    return GlassSectionCard(
      title: 'Breakdown',
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: AppTheme.primaryColor,
            unselectedLabelColor: AppTheme.textSec(context),
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            tabs: const [
              Tab(text: 'By Category'),
              Tab(text: 'By Product'),
              Tab(text: 'By Period'),
            ],
          ),
          SizedBox(
            height: 300,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildBreakdownList(byCategory),
                _buildBreakdownList(byProduct),
                _buildPeriodList(byDay),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownList(Map<String, _PnLEntry> data) {
    final sorted = data.values.toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));
    if (sorted.isEmpty) {
      return Center(
        child: Text(
          'No data',
          style: TextStyle(color: AppTheme.textSec(context)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(top: 12),
      itemCount: sorted.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final e = sorted[i];
        final profit = e.revenue - e.cost;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  e.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  _fmtCurrency(e.revenue),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.successColor,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: Text(
                  _fmtCurrency(profit),
                  style: TextStyle(
                    fontSize: 12,
                    color: profit >= 0
                        ? AppTheme.primaryColor
                        : AppTheme.dangerColor,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPeriodList(Map<String, _PnLEntry> byDay) {
    final sortedKeys = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    if (sortedKeys.isEmpty) {
      return Center(
        child: Text(
          'No data',
          style: TextStyle(color: AppTheme.textSec(context)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(top: 12),
      itemCount: sortedKeys.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final e = byDay[sortedKeys[i]]!;
        final d = DateTime.tryParse(e.name);
        final label = d != null ? DateFormat('dd MMM yyyy').format(d) : e.name;
        final profit = e.revenue - e.cost;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  _fmtCurrency(e.revenue),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.successColor,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: Text(
                  _fmtCurrency(profit),
                  style: TextStyle(
                    fontSize: 12,
                    color: profit >= 0
                        ? AppTheme.primaryColor
                        : AppTheme.dangerColor,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  LineChartBarData _line(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      preventCurveOverShooting: true,
      color: color,
      barWidth: 2.5,
      dotData: FlDotData(
        show: spots.length <= 15,
        getDotPainter: (_, _, _, _) => FlDotCirclePainter(
          radius: 3,
          color: color,
          strokeWidth: 1.5,
          strokeColor: Colors.white,
        ),
      ),
      belowBarData: BarAreaData(
        show: true,
        color: color.withValues(alpha: 0.08),
      ),
    );
  }

  Widget _legend(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 11, color: AppTheme.textSec(context)),
        ),
      ],
    );
  }

  String _compactNumber(double v) {
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
    if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K';
    return v.toInt().toString();
  }
}

class _PnLEntry {
  final String name;
  double revenue = 0;
  double cost = 0;
  _PnLEntry(this.name);
}

class _RangeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primaryColor
                : AppTheme.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppTheme.primaryColor,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
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
    );
  }
}
