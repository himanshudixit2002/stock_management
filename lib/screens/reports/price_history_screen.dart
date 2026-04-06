import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../config/theme.dart';
import '../../models/product_model.dart';
import '../../models/price_history_model.dart';
import '../../providers/product_provider.dart';
import '../../providers/price_history_provider.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/empty_state_widget.dart';

class PriceHistoryScreen extends StatefulWidget {
  const PriceHistoryScreen({super.key});

  @override
  State<PriceHistoryScreen> createState() => _PriceHistoryScreenState();
}

class _PriceHistoryScreenState extends State<PriceHistoryScreen> {
  ProductModel? _selectedProduct;
  String _productSearch = '';

  @override
  Widget build(BuildContext context) {
    final history = context.watch<PriceHistoryProvider>().history;
    final isLoading = context.watch<PriceHistoryProvider>().isLoading;

    final filteredHistory = _selectedProduct != null
        ? history.where((h) => h.productId == _selectedProduct!.id).toList()
        : <PriceHistoryModel>[];

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: const AppBarTitleRow(
          icon: Icons.trending_up_rounded,
          color: AppTheme.infoColor,
          title: 'Price History',
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Responsive.contentMaxWidth(context),
            ),
            child: Column(
              children: [
                _buildProductSelector(),
                if (isLoading)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_selectedProduct == null)
                  const Expanded(
                    child: EmptyStateWidget(
                      icon: Icons.trending_up_rounded,
                      title: 'Select a Product',
                      subtitle: 'Choose a product to view its price history.',
                    ),
                  )
                else if (filteredHistory.isEmpty)
                  const Expanded(
                    child: EmptyStateWidget(
                      icon: Icons.history_rounded,
                      title: 'No Price History',
                      subtitle:
                          'No price changes recorded for this product yet.',
                    ),
                  )
                else
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.all(
                        Responsive.horizontalPadding(context),
                      ),
                      children: [
                        _buildChart(filteredHistory),
                        const SizedBox(height: 20),
                        _buildHistoryTable(filteredHistory),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProductSelector() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Material(
        color: AppTheme.inputFill(context),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: _showProductPicker,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.inputBorder(context)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.inventory_2_rounded,
                  color: _selectedProduct != null
                      ? AppTheme.primaryColor
                      : AppTheme.textSec(context),
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedProduct?.name ?? 'Select a product...',
                    style: TextStyle(
                      fontWeight: _selectedProduct != null
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: _selectedProduct != null
                          ? AppTheme.textPri(context)
                          : AppTheme.textSec(context),
                      fontSize: 15,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  color: AppTheme.textSec(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showProductPicker() {
    final products = context.read<ProductProvider>().allProducts;
    _productSearch = '';

    showModalBottomSheet(
      context: context,
      constraints: Responsive.sheetConstraints(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final filtered = _productSearch.isEmpty
                ? products
                : products
                    .where(
                      (p) => p.name
                          .toLowerCase()
                          .contains(_productSearch.toLowerCase()),
                    )
                    .toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              decoration: BoxDecoration(
                color: AppTheme.surface(context),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.emptyIcon(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Search products...',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (v) =>
                          setModalState(() => _productSearch = v),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final p = filtered[i];
                        return ListTile(
                          onTap: () {
                            setState(() => _selectedProduct = p);
                            Navigator.pop(ctx);
                          },
                          leading: const Icon(Icons.inventory_2_rounded),
                          title: Text(
                            p.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(p.categoryName),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildChart(List<PriceHistoryModel> history) {
    final costEntries = history
        .where((h) => h.field == 'costPrice')
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final sellingEntries = history
        .where((h) => h.field == 'sellingPrice')
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (costEntries.isEmpty && sellingEntries.isEmpty) {
      return const SizedBox.shrink();
    }

    List<FlSpot> toSpots(List<PriceHistoryModel> entries) {
      return entries.asMap().entries.map((e) {
        return FlSpot(e.key.toDouble(), e.value.newValue);
      }).toList();
    }

    final costSpots = toSpots(costEntries);
    final sellingSpots = toSpots(sellingEntries);

    return GlassPanel(
      useContentVariant: true,
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Price Trend',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              if (costSpots.isNotEmpty) ...[
                Container(
                  width: 12,
                  height: 3,
                  color: AppTheme.dangerColor,
                ),
                const SizedBox(width: 4),
                Text(
                  'Cost',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSec(context)),
                ),
                const SizedBox(width: 12),
              ],
              if (sellingSpots.isNotEmpty) ...[
                Container(
                  width: 12,
                  height: 3,
                  color: AppTheme.successColor,
                ),
                const SizedBox(width: 4),
                Text(
                  'Selling',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSec(context)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: Responsive.chartHeight(context),
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: _calcInterval(costSpots, sellingSpots),
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: AppTheme.dividerC(context),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      getTitlesWidget: (value, meta) => Text(
                        '${AppTheme.currencySymbol}${value.toInt()}',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.textSec(context),
                        ),
                      ),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  if (costSpots.isNotEmpty)
                    LineChartBarData(
                      spots: costSpots,
                      isCurved: true,
                      color: AppTheme.dangerColor,
                      barWidth: 2.5,
                      dotData: FlDotData(
                        show: costSpots.length <= 20,
                        getDotPainter: (s, d, b, i) => FlDotCirclePainter(
                          radius: 3,
                          color: AppTheme.dangerColor,
                          strokeWidth: 1.5,
                          strokeColor: Colors.white,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppTheme.dangerColor.withValues(alpha: 0.08),
                      ),
                    ),
                  if (sellingSpots.isNotEmpty)
                    LineChartBarData(
                      spots: sellingSpots,
                      isCurved: true,
                      color: AppTheme.successColor,
                      barWidth: 2.5,
                      dotData: FlDotData(
                        show: sellingSpots.length <= 20,
                        getDotPainter: (s, d, b, i) => FlDotCirclePainter(
                          radius: 3,
                          color: AppTheme.successColor,
                          strokeWidth: 1.5,
                          strokeColor: Colors.white,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppTheme.successColor.withValues(alpha: 0.08),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _calcInterval(List<FlSpot> cost, List<FlSpot> selling) {
    final allY = [...cost.map((s) => s.y), ...selling.map((s) => s.y)];
    if (allY.isEmpty) return 100;
    final max = allY.reduce((a, b) => a > b ? a : b);
    final min = allY.reduce((a, b) => a < b ? a : b);
    final range = max - min;
    if (range <= 0) return 100;
    return (range / 4).ceilToDouble();
  }

  Widget _buildHistoryTable(List<PriceHistoryModel> history) {
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

    return GlassPanel(
      useContentVariant: true,
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Change Log',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 12),
          ...history.map((h) {
            final isIncrease = h.newValue > h.oldValue;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isIncrease
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 16,
                    color: isIncrease
                        ? AppTheme.dangerColor
                        : AppTheme.successColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_fieldLabel(h.field)}: '
                          '${AppTheme.currencySymbol}${h.oldValue.toStringAsFixed(2)} → '
                          '${AppTheme.currencySymbol}${h.newValue.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${dateFormat.format(h.timestamp)} • ${h.changedByName.isNotEmpty ? h.changedByName : 'Unknown'}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSec(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  String _fieldLabel(String field) {
    switch (field) {
      case 'costPrice':
        return 'Cost Price';
      case 'sellingPrice':
        return 'Selling Price';
      default:
        return field;
    }
  }
}
