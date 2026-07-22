import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../providers/stock_provider.dart';
import '../../../providers/product_provider.dart';
import '../../../widgets/glass_panel.dart';
import '../../../widgets/animations.dart';
import '../../../services/report_analytics_service.dart';
import '../../../widgets/floating_nav_padding.dart';

class PredictiveForecastingTab extends StatefulWidget {
  const PredictiveForecastingTab({super.key});

  @override
  State<PredictiveForecastingTab> createState() => _PredictiveForecastingTabState();
}

class _PredictiveForecastingTabState extends State<PredictiveForecastingTab> {
  HealthQuadrant? _selectedQuadrantFilter;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final stockProvider = context.watch<StockProvider>();
    final productProvider = context.watch<ProductProvider>();

    final transactions = stockProvider.recentTransactions;
    final products = productProvider.products;

    final periodDays = stockProvider.filterStartDate != null && stockProvider.filterEndDate != null
        ? stockProvider.filterEndDate!.difference(stockProvider.filterStartDate!).inDays.abs()
        : 30;

    final analytics = ReportAnalyticsService();
    final forecasts = analytics.computeInventoryHealthForecasts(
      transactions: transactions,
      products: products,
      periodDays: periodDays > 0 ? periodDays : 30,
    );

    final atRiskCount = forecasts.where((f) => f.quadrant == HealthQuadrant.atRisk).length;
    final deadStockCount = forecasts.where((f) => f.quadrant == HealthQuadrant.deadStock).length;
    final overstockedCount = forecasts.where((f) => f.quadrant == HealthQuadrant.overstocked).length;
    final optimalCount = forecasts.where((f) => f.quadrant == HealthQuadrant.optimal).length;

    final filteredForecasts = forecasts.where((f) {
      if (_selectedQuadrantFilter != null && f.quadrant != _selectedQuadrantFilter) {
        return false;
      }
      if (_searchQuery.isNotEmpty &&
          !f.product.name.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    return FadeSlideIn(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stock-Out Forecasting & Inventory Matrix',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPri(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Predictive run-rate analytics estimating remaining days of supply',
              style: TextStyle(fontSize: 12, color: AppTheme.textSec(context)),
            ),
            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: _quadrantCard(
                    context,
                    title: 'At Risk / Stockout',
                    count: atRiskCount,
                    color: Colors.redAccent,
                    icon: Icons.warning_amber_rounded,
                    quadrant: HealthQuadrant.atRisk,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _quadrantCard(
                    context,
                    title: 'Dead Stock',
                    count: deadStockCount,
                    color: Colors.orangeAccent,
                    icon: Icons.hourglass_disabled_rounded,
                    quadrant: HealthQuadrant.deadStock,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _quadrantCard(
                    context,
                    title: 'Overstocked',
                    count: overstockedCount,
                    color: Colors.blueAccent,
                    icon: Icons.inventory_2_rounded,
                    quadrant: HealthQuadrant.overstocked,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _quadrantCard(
                    context,
                    title: 'Optimal Stock',
                    count: optimalCount,
                    color: Colors.green,
                    icon: Icons.check_circle_outline_rounded,
                    quadrant: HealthQuadrant.optimal,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Search forecast catalog...',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                ),
              ),
            ),
            const SizedBox(height: 10),

            Expanded(
              child: filteredForecasts.isEmpty
                  ? Center(
                      child: Text(
                        'No inventory items match this matrix filter',
                        style: TextStyle(color: AppTheme.textSec(context)),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.only(
                        bottom: floatingNavContentInset(context) + 8,
                      ),
                      itemCount: filteredForecasts.length,
                      itemBuilder: (context, index) {
                        final forecast = filteredForecasts[index];
                        final p = forecast.product;
                        final daysStr = forecast.daysOfSupply > 365
                            ? '> 1 Year'
                            : '${forecast.daysOfSupply.toStringAsFixed(0)} Days';

                        Color badgeColor;
                        String quadrantLabel;
                        switch (forecast.quadrant) {
                          case HealthQuadrant.atRisk:
                            badgeColor = Colors.redAccent;
                            quadrantLabel = 'Stockout Danger';
                            break;
                          case HealthQuadrant.deadStock:
                            badgeColor = Colors.orange;
                            quadrantLabel = 'Dead Stock';
                            break;
                          case HealthQuadrant.overstocked:
                            badgeColor = Colors.blue;
                            quadrantLabel = 'Overstocked';
                            break;
                          case HealthQuadrant.optimal:
                            badgeColor = Colors.green;
                            quadrantLabel = 'Optimal';
                            break;
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: GlassPanel(
                            padding: const EdgeInsets.all(12),
                            borderRadius: 12,
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: badgeColor.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.speed_rounded, color: badgeColor, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.name,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Current Qty: ${p.quantity} ${p.unit}  |  Daily Burn: ${forecast.dailyBurnRate.toStringAsFixed(1)}/day',
                                        style: TextStyle(fontSize: 11, color: AppTheme.textSec(context)),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: badgeColor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        quadrantLabel,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: badgeColor,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Run-rate: $daysStr',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quadrantCard(
    BuildContext context, {
    required String title,
    required int count,
    required Color color,
    required IconData icon,
    required HealthQuadrant quadrant,
  }) {
    final isSelected = _selectedQuadrantFilter == quadrant;

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedQuadrantFilter = null;
          } else {
            _selectedQuadrantFilter = quadrant;
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.25) : AppTheme.card(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    count.toString(),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPri(context),
                    ),
                  ),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppTheme.textSec(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
