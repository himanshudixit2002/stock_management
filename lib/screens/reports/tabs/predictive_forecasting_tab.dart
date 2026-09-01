import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../providers/stock_provider.dart';
import '../../../models/stock_transaction_model.dart';
import '../../../models/product_model.dart';
import '../../../providers/product_provider.dart';
import '../../../widgets/glass_panel.dart';
import '../../../widgets/animations.dart';
import '../../../services/report_analytics_service.dart';
import '../../../widgets/floating_nav_padding.dart';
import '../../ai/ask_ai_launcher.dart';

class PredictiveForecastingTab extends StatefulWidget {
  const PredictiveForecastingTab({super.key});

  @override
  State<PredictiveForecastingTab> createState() => _PredictiveForecastingTabState();
}

class _PredictiveForecastingTabState extends State<PredictiveForecastingTab> {
  HealthQuadrant? _selectedQuadrantFilter;
  String _searchQuery = '';
  bool _showAiBanner = true;

  // Run-rate forecasting walks every transaction for every product, so the
  // result is memoized against the provider lists it was built from (they are
  // replaced wholesale, making identity a sound staleness check). The quadrant
  // filter and search box below stay per-build — they are a cheap pass over the
  // already-computed forecasts.
  List<StockTransactionModel>? _memoTx;
  List<ProductModel>? _memoProducts;
  int? _memoPeriodDays;
  List<ProductHealthForecast>? _memoForecasts;
  Map<HealthQuadrant, int> _memoCounts = const {};

  List<ProductHealthForecast> _forecastsFor(
    List<StockTransactionModel> transactions,
    List<ProductModel> products,
    int periodDays,
  ) {
    if (_memoForecasts != null &&
        identical(_memoTx, transactions) &&
        identical(_memoProducts, products) &&
        _memoPeriodDays == periodDays) {
      return _memoForecasts!;
    }
    final forecasts = ReportAnalyticsService().computeInventoryHealthForecasts(
      transactions: transactions,
      products: products,
      periodDays: periodDays,
    );
    final counts = <HealthQuadrant, int>{};
    for (final f in forecasts) {
      counts[f.quadrant] = (counts[f.quadrant] ?? 0) + 1;
    }
    _memoTx = transactions;
    _memoProducts = products;
    _memoPeriodDays = periodDays;
    _memoCounts = counts;
    return _memoForecasts = forecasts;
  }

  @override
  Widget build(BuildContext context) {
    final stockProvider = context.watch<StockProvider>();
    final productProvider = context.watch<ProductProvider>();

    final transactions = stockProvider.recentTransactions;
    final products = productProvider.analyticsProducts;

    final range = stockProvider.filterStartDate != null && stockProvider.filterEndDate != null
        ? stockProvider.filterEndDate!.difference(stockProvider.filterStartDate!).inDays.abs()
        : 30;
    final periodDays = range > 0 ? range : 30;

    final forecasts = _forecastsFor(transactions, products, periodDays);

    final atRiskCount = _memoCounts[HealthQuadrant.atRisk] ?? 0;
    final deadStockCount = _memoCounts[HealthQuadrant.deadStock] ?? 0;
    final overstockedCount = _memoCounts[HealthQuadrant.overstocked] ?? 0;
    final optimalCount = _memoCounts[HealthQuadrant.optimal] ?? 0;

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
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Stock-Out Forecasting & Matrix',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPri(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Predictive run-rate analytics estimating remaining days of supply',
                    style: TextStyle(fontSize: 11.5, color: AppTheme.textSec(context)),
                  ),
                  const SizedBox(height: 10),

                  if (_showAiBanner) ...[
                    GestureDetector(
                      onTap: () => openAskAi(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.primaryColor.withValues(alpha: 0.14),
                              AppTheme.accentColor.withValues(alpha: 0.08),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.primaryColor.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.auto_awesome_rounded,
                                color: AppTheme.primaryColor,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '⚡ RAG Smart AI Inventory Audit',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPri(context),
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    'Auto-reorder & detect margin leaks',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textSec(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 16),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                              color: AppTheme.iconMute(context),
                              tooltip: 'Dismiss',
                              onPressed: () => setState(() => _showAiBanner = false),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // 2x2 Matrix Cards
                  Row(
                    children: [
                      Expanded(
                        child: _quadrantCard(
                          context,
                          title: 'At Risk / Out',
                          count: atRiskCount,
                          color: AppTheme.dangerColor,
                          icon: Icons.warning_amber_rounded,
                          quadrant: HealthQuadrant.atRisk,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _quadrantCard(
                          context,
                          title: 'Dead Stock',
                          count: deadStockCount,
                          color: AppTheme.warningColor,
                          icon: Icons.hourglass_disabled_rounded,
                          quadrant: HealthQuadrant.deadStock,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _quadrantCard(
                          context,
                          title: 'Overstocked',
                          count: overstockedCount,
                          color: AppTheme.accentColor,
                          icon: Icons.inventory_2_rounded,
                          quadrant: HealthQuadrant.overstocked,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _quadrantCard(
                          context,
                          title: 'Optimal Stock',
                          count: optimalCount,
                          color: AppTheme.successColor,
                          icon: Icons.check_circle_outline_rounded,
                          quadrant: HealthQuadrant.optimal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),

          // Pinned Search Bar
          SliverPersistentHeader(
            pinned: true,
            delegate: _SearchHeaderDelegate(
              height: 48,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search forecast catalog...',
                    hintStyle: TextStyle(fontSize: 12.5, color: AppTheme.textTer(context)),
                    prefixIcon: Icon(Icons.search_rounded, size: 17, color: AppTheme.iconMute(context)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    isDense: true,
                    filled: true,
                    fillColor: AppTheme.surface(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppTheme.dividerC(context).withValues(alpha: 0.4)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppTheme.dividerC(context).withValues(alpha: 0.4)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Products List
          if (filteredForecasts.isEmpty)
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 40),
                alignment: Alignment.center,
                child: Text(
                  'No inventory items match this matrix filter',
                  style: TextStyle(color: AppTheme.textSec(context), fontSize: 13),
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                floatingNavContentInset(context) + 16,
              ),
              sliver: SliverList.builder(
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
                      badgeColor = AppTheme.dangerColor;
                      quadrantLabel = 'Danger';
                      break;
                    case HealthQuadrant.deadStock:
                      badgeColor = AppTheme.warningColor;
                      quadrantLabel = 'Dead';
                      break;
                    case HealthQuadrant.overstocked:
                      badgeColor = AppTheme.accentColor;
                      quadrantLabel = 'Overstock';
                      break;
                    case HealthQuadrant.optimal:
                      badgeColor = AppTheme.successColor;
                      quadrantLabel = 'Optimal';
                      break;
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: GlassPanel(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      borderRadius: 10,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.speed_rounded, color: badgeColor, size: 17),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 1.5),
                                Text(
                                  'Qty: ${p.quantity} ${p.unit}  •  Burn: ${forecast.dailyBurnRate.toStringAsFixed(1)}/d',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: AppTheme.textSec(context),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: badgeColor.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  quadrantLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: badgeColor,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                daysStr,
                                style: const TextStyle(
                                  fontSize: 11.5,
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.22) : AppTheme.card(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.25),
            width: isSelected ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    count.toString(),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPri(context),
                    ),
                  ),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSec(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

class _SearchHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  _SearchHeaderDelegate({required this.child, this.height = 48.0});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      height: height,
      color: AppTheme.bg(context),
      alignment: Alignment.center,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _SearchHeaderDelegate oldDelegate) {
    return oldDelegate.height != height || oldDelegate.child != child;
  }
}
