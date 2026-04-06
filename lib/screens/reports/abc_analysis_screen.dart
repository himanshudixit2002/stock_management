import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../config/theme.dart';
import '../../providers/stock_provider.dart';
import '../../providers/product_provider.dart';
import '../../models/stock_transaction_model.dart';
import '../../models/product_model.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/empty_state_widget.dart';
import '../../utils/responsive.dart';

class AbcAnalysisScreen extends StatefulWidget {
  const AbcAnalysisScreen({super.key});

  @override
  State<AbcAnalysisScreen> createState() => _AbcAnalysisScreenState();
}

class _AbcAnalysisScreenState extends State<AbcAnalysisScreen> {
  int _rangeDays = 90;
  DateTimeRange? _customRange;
  int _touchedIndex = -1;

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

  List<_AbcItem> _computeAbcItems(
    StockProvider stockProv,
    ProductProvider productProv,
  ) {
    final range = _effectiveRange;
    final stockOuts = stockProv.allTransactions.where((t) {
      if (t.type != TransactionType.stockOut) return false;
      return !t.date.isBefore(range.start) && !t.date.isAfter(range.end);
    });

    final pMap = <String, ProductModel>{};
    for (final p in productProv.allProducts) {
      pMap[p.id] = p;
    }

    final revenueMap = <String, double>{};
    final nameMap = <String, String>{};
    for (final t in stockOuts) {
      final product = pMap[t.productId];
      final sp = product?.sellingPrice ?? 0;
      final rev = sp * t.quantity;
      revenueMap[t.productId] = (revenueMap[t.productId] ?? 0) + rev;
      nameMap[t.productId] = t.productName.isNotEmpty
          ? t.productName
          : t.productId;
    }

    final items =
        revenueMap.entries
            .map(
              (e) => _AbcItem(
                productId: e.key,
                name: nameMap[e.key] ?? e.key,
                revenue: e.value,
              ),
            )
            .toList()
          ..sort((a, b) => b.revenue.compareTo(a.revenue));

    final totalRevenue = items.fold<double>(
      0,
      (sum, item) => sum + item.revenue,
    );
    double cumulative = 0;
    for (final item in items) {
      item.pctOfTotal = totalRevenue > 0
          ? (item.revenue / totalRevenue) * 100
          : 0;
      cumulative += item.pctOfTotal;
      item.cumulativePct = cumulative;
      if (cumulative <= 80) {
        item.abcClass = 'A';
      } else if (cumulative <= 95) {
        item.abcClass = 'B';
      } else {
        item.abcClass = 'C';
      }
    }

    return items;
  }

  String _fmtCurrency(double v) {
    final fmt = NumberFormat('#,##0.00');
    return '${AppTheme.currencySymbol}${fmt.format(v)}';
  }

  @override
  Widget build(BuildContext context) {
    final stockProv = context.watch<StockProvider>();
    final productProv = context.watch<ProductProvider>();
    final items = _computeAbcItems(stockProv, productProv);

    final aCount = items.where((i) => i.abcClass == 'A').length;
    final bCount = items.where((i) => i.abcClass == 'B').length;
    final cCount = items.where((i) => i.abcClass == 'C').length;

    final aRevenue = items
        .where((i) => i.abcClass == 'A')
        .fold<double>(0, (s, i) => s + i.revenue);
    final bRevenue = items
        .where((i) => i.abcClass == 'B')
        .fold<double>(0, (s, i) => s + i.revenue);
    final cRevenue = items
        .where((i) => i.abcClass == 'C')
        .fold<double>(0, (s, i) => s + i.revenue);

    final totalPct = items.isNotEmpty
        ? (aCount / items.length * 100).toStringAsFixed(0)
        : '0';

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: const AppBarTitleRow(
          icon: Icons.pie_chart_rounded,
          color: AppTheme.indigoColor,
          title: 'ABC Analysis',
        ),
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
          child: items.isEmpty
              ? const EmptyStateWidget(
                  icon: Icons.analytics_rounded,
                  title: 'No Sales Data',
                  subtitle:
                      'No stock-out transactions found for ABC classification.',
                )
              : SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: Responsive.horizontalPadding(context),
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GlassPanel(
                        useContentVariant: true,
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.lightbulb_outline_rounded,
                              color: AppTheme.warningColor,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '$aCount products ($totalPct%) generate 80% of revenue',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPri(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildPieChart(aRevenue, bRevenue, cRevenue),
                      const SizedBox(height: 16),
                      _buildClassSummary(aCount, bCount, cCount, items.length),
                      const SizedBox(height: 20),
                      _buildProductTable(items),
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
            label: '1 Year',
            selected: _rangeDays == 365 && _customRange == null,
            onTap: () => setState(() {
              _rangeDays = 365;
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

  Widget _buildPieChart(double aRev, double bRev, double cRev) {
    final total = aRev + bRev + cRev;
    if (total == 0) return const SizedBox.shrink();

    return GlassSectionCard(
      title: 'Revenue Distribution',
      child: SizedBox(
        height: 200,
        child: PieChart(
          PieChartData(
            pieTouchData: PieTouchData(
              touchCallback: (event, response) {
                setState(() {
                  if (!event.isInterestedForInteractions ||
                      response == null ||
                      response.touchedSection == null) {
                    _touchedIndex = -1;
                    return;
                  }
                  _touchedIndex = response.touchedSection!.touchedSectionIndex;
                });
              },
            ),
            sectionsSpace: 3,
            centerSpaceRadius: 40,
            sections: [
              _pieSection(0, aRev, total, 'A', AppTheme.successColor),
              _pieSection(1, bRev, total, 'B', AppTheme.warningColor),
              _pieSection(2, cRev, total, 'C', AppTheme.textSec(context)),
            ],
          ),
        ),
      ),
    );
  }

  PieChartSectionData _pieSection(
    int idx,
    double value,
    double total,
    String label,
    Color color,
  ) {
    final isTouched = idx == _touchedIndex;
    final pct = total > 0 ? (value / total * 100) : 0.0;
    return PieChartSectionData(
      color: color,
      value: value,
      title: isTouched
          ? '$label\n${pct.toStringAsFixed(1)}%'
          : '${pct.toStringAsFixed(0)}%',
      radius: isTouched ? 60 : 50,
      titleStyle: TextStyle(
        fontSize: isTouched ? 13 : 11,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
  }

  Widget _buildClassSummary(int a, int b, int c, int total) {
    return Row(
      children: [
        Expanded(
          child: _classBadgeSummary('A', a, total, AppTheme.successColor),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _classBadgeSummary('B', b, total, AppTheme.warningColor),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _classBadgeSummary('C', c, total, AppTheme.textSec(context)),
        ),
      ],
    );
  }

  Widget _classBadgeSummary(String cls, int count, int total, Color color) {
    final pct = total > 0 ? (count / total * 100).toStringAsFixed(0) : '0';
    return GlassPanel(
      useContentVariant: true,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                cls,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$count items',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPri(context),
            ),
          ),
          Text(
            '$pct% of total',
            style: TextStyle(fontSize: 11, color: AppTheme.textSec(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildProductTable(List<_AbcItem> items) {
    return GlassSectionCard(
      title: 'Product Breakdown',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Product',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSec(context),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Revenue',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSec(context),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                SizedBox(
                  width: 40,
                  child: Text(
                    '%',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSec(context),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  child: Text(
                    'Cum %',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSec(context),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                SizedBox(
                  width: 28,
                  child: Text(
                    'Class',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSec(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      item.name,
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      _fmtCurrency(item.revenue),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${item.pctOfTotal.toStringAsFixed(1)}%',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${item.cumulativePct.toStringAsFixed(1)}%',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(width: 28, child: _classBadge(item.abcClass)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _classBadge(String cls) {
    final color = switch (cls) {
      'A' => AppTheme.successColor,
      'B' => AppTheme.warningColor,
      _ => AppTheme.textSec(context),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        cls,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _AbcItem {
  final String productId;
  final String name;
  final double revenue;
  double pctOfTotal = 0;
  double cumulativePct = 0;
  String abcClass = 'C';

  _AbcItem({
    required this.productId,
    required this.name,
    required this.revenue,
  });
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
                ? AppTheme.indigoColor
                : AppTheme.indigoColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppTheme.indigoColor,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
