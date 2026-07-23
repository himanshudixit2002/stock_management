import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../providers/stock_provider.dart';
import '../../../providers/product_provider.dart';
import '../../../widgets/glass_panel.dart';
import '../../../widgets/animations.dart';
import '../../../widgets/charts/transaction_line_chart.dart';
import '../../../widgets/charts/category_pie_chart.dart';
import '../../../widgets/charts/stock_bar_chart.dart';
import '../../../widgets/charts/top_products_chart.dart';
import '../../../widgets/floating_nav_padding.dart';

class AnalyticsChartsTab extends StatefulWidget {
  const AnalyticsChartsTab({super.key});

  @override
  State<AnalyticsChartsTab> createState() => _AnalyticsChartsTabState();
}

class _AnalyticsChartsTabState extends State<AnalyticsChartsTab> {
  int _chartDays = 7;
  String _chartGranularity = 'daily';

  @override
  Widget build(BuildContext context) {
    final stockProvider = context.watch<StockProvider>();
    final productProvider = context.watch<ProductProvider>();

    // Build chart data from provider

    // Category distribution by quantity moved
    final Map<String, double> categoryData = {};
    for (final product in productProvider.products) {
      if (product.quantity > 0) {
        categoryData[product.categoryName.isNotEmpty ? product.categoryName : 'General'] =
            (categoryData[product.categoryName.isNotEmpty ? product.categoryName : 'General'] ?? 0) +
                product.quantity.toDouble();
      }
    }

    // Stock In vs Out by category
    final Map<String, double> stockInOutData = {
      'Stock In': stockProvider.stockInTotal.toDouble(),
      'Stock Out': stockProvider.stockOutTotal.toDouble(),
      'Damage': stockProvider.damageTotal.toDouble(),
    };

    // Top Products by transactions
    final topProducts = stockProvider.topProductsByQuantityMoved;

    return FadeSlideIn(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + floatingNavContentInset(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Text(
                  'Visual Analytics & Trends',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPri(context),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _dateChip('7D', 7, 'daily'),
                    const SizedBox(width: 6),
                    _dateChip('30D', 30, 'daily'),
                    const SizedBox(width: 6),
                    _dateChip('90D', 90, 'weekly'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Line Chart
            GlassPanel(
              padding: const EdgeInsets.all(16),
              borderRadius: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Text(
                        'Transaction Volume Trend',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPri(context),
                        ),
                      ),
                      _granularityPicker(),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 200,
                    child: TransactionLineChart(
                      dataByDay: stockProvider.transactionsByDay,
                      days: _chartDays,
                      granularity: _chartGranularity,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Pie Chart & Bar Chart Grid (Stacked on Mobile, Row on Desktop)
            Builder(
              builder: (context) {
                final isMobile = MediaQuery.of(context).size.width < 600;

                final categoryMixCard = GlassPanel(
                  padding: const EdgeInsets.all(16),
                  borderRadius: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Category Mix',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPri(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 190,
                        child: CategoryPieChart(data: categoryData),
                      ),
                    ],
                  ),
                );

                final stockActivityCard = GlassPanel(
                  padding: const EdgeInsets.all(16),
                  borderRadius: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Stock Activity',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPri(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 190,
                        child: StockBarChart(data: stockInOutData),
                      ),
                    ],
                  ),
                );

                if (isMobile) {
                  return Column(
                    children: [
                      categoryMixCard,
                      const SizedBox(height: 14),
                      stockActivityCard,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: categoryMixCard),
                    const SizedBox(width: 12),
                    Expanded(child: stockActivityCard),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),

            // Top Products Horizontal Bar Chart
            GlassPanel(
              padding: const EdgeInsets.all(16),
              borderRadius: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Top Products by Volume Moved',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPri(context),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 220,
                    child: TopProductsChart(data: topProducts),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _dateChip(String label, int days, String granularity) {
    return ChoiceChip(
      selected: _chartDays == days,
      label: Text(label),
      onSelected: (sel) {
        if (sel) {
          setState(() {
            _chartDays = days;
            _chartGranularity = granularity;
          });
        }
      },
    );
  }

  Widget _granularityPicker() {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'daily', label: Text('D')),
        ButtonSegment(value: 'weekly', label: Text('W')),
        ButtonSegment(value: 'monthly', label: Text('M')),
      ],
      selected: {_chartGranularity},
      onSelectionChanged: (set) {
        if (set.isNotEmpty) setState(() => _chartGranularity = set.first);
      },
      style: SegmentedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        textStyle: const TextStyle(fontSize: 11),
      ),
    );
  }
}
