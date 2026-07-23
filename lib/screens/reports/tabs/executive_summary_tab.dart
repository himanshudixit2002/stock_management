import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../config/theme.dart';
import '../../../providers/stock_provider.dart';
import '../../../providers/product_provider.dart';
import '../../../models/stock_transaction_model.dart';
import '../../../models/product_model.dart';
import '../../../widgets/glass_panel.dart';
import '../../../widgets/animations.dart';
import '../../../services/report_analytics_service.dart';
import '../widgets/ai_insights_card.dart';
import '../../../widgets/floating_nav_padding.dart';

class ExecutiveSummaryTab extends StatelessWidget {
  final Function(int tabIndex)? onNavigateTab;

  const ExecutiveSummaryTab({super.key, this.onNavigateTab});

  @override
  Widget build(BuildContext context) {
    final stockProvider = context.watch<StockProvider>();
    final productProvider = context.watch<ProductProvider>();
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');

    final transactions = stockProvider.recentTransactions;
    final products = productProvider.products;
    final pMap = {for (final p in products) p.id: p};

    final periodDays = stockProvider.filterStartDate != null && stockProvider.filterEndDate != null
        ? stockProvider.filterEndDate!.difference(stockProvider.filterStartDate!).inDays.abs()
        : 30;

    final analytics = ReportAnalyticsService();
    final deltas = analytics.computePeriodOverPeriodDeltas(
      currentTx: transactions,
      previousTx: const [],
      productMap: pMap,
    );

    final aiInsights = analytics.generateAiExecutiveInsights(
      currentTx: transactions,
      products: products,
      deltas: deltas,
    );

    final anomalies = analytics.detectAnomalies(
      transactions: transactions,
      products: products,
      periodDays: periodDays > 0 ? periodDays : 30,
    );

    int totalIn = 0;
    int totalOut = 0;
    int totalDamage = 0;
    double totalRevenue = 0.0;
    double totalAssetValuation = 0.0;

    for (final p in products) {
      totalAssetValuation += (p.quantity * p.costPrice);
    }

    for (final tx in transactions) {
      final p = pMap[tx.productId];
      final price = p?.sellingPrice ?? 0.0;
      final cost = p?.costPrice ?? 0.0;

      if (tx.type == TransactionType.stockIn) {
        totalIn += tx.quantity;
      } else if (tx.type == TransactionType.stockOut) {
        totalOut += tx.quantity;
        totalRevenue += (tx.quantity * (price > 0 ? price : cost));
      } else if (tx.type == TransactionType.damage) {
        totalDamage += tx.quantity;
      }
    }

    return FadeSlideIn(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + floatingNavContentInset(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AiInsightsCard(
              insights: aiInsights,
              anomalies: anomalies,
              onAnomalyAction: (anomalyId) {
                if (anomalyId == 'critical_stockout' || anomalyId == 'dead_stock_accumulation') {
                  onNavigateTab?.call(3);
                }
              },
            ),

            Text(
              'Executive Metrics & Valuation',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPri(context),
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    context,
                    title: 'Total Asset Valuation',
                    value: currency.format(totalAssetValuation),
                    icon: Icons.account_balance_wallet_rounded,
                    gradientColors: [Colors.blue.shade700, Colors.indigo.shade800],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricCard(
                    context,
                    title: 'Est. Outbound Sales',
                    value: currency.format(totalRevenue),
                    icon: Icons.trending_up_rounded,
                    gradientColors: [Colors.teal.shade700, Colors.teal.shade900],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _buildSubStatCard(
                    context,
                    title: 'Stock In Units',
                    value: '$totalIn',
                    icon: Icons.download_rounded,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSubStatCard(
                    context,
                    title: 'Stock Out Units',
                    value: '$totalOut',
                    icon: Icons.upload_rounded,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSubStatCard(
                    context,
                    title: 'Damaged Units',
                    value: '$totalDamage',
                    icon: Icons.warning_rounded,
                    color: Colors.redAccent,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            GlassPanel(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Top Moving Products',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPri(context),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => onNavigateTab?.call(1),
                        icon: const Icon(Icons.table_chart_outlined, size: 16),
                        label: const Text('Custom Builder'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (transactions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(
                          'No transaction data in this period',
                          style: TextStyle(color: AppTheme.textSec(context)),
                        ),
                      ),
                    )
                  else
                    ..._buildTopProductsList(context, transactions, pMap),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required List<Color> gradientColors,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: gradientColors.first.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.white70,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, color: Colors.white, size: 18),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubStatCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return GlassPanel(
      padding: const EdgeInsets.all(12),
      borderRadius: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
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
    );
  }

  List<Widget> _buildTopProductsList(
    BuildContext context,
    List<StockTransactionModel> txs,
    Map<String, ProductModel> pMap,
  ) {
    final Map<String, int> qtyMap = {};
    for (final tx in txs) {
      if (tx.type == TransactionType.stockOut) {
        qtyMap[tx.productId] = (qtyMap[tx.productId] ?? 0) + tx.quantity;
      }
    }

    final sortedEntries = qtyMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topEntries = sortedEntries.take(5).toList();

    if (topEntries.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text('No outbound sales recorded', style: TextStyle(color: AppTheme.textSec(context))),
        )
      ];
    }

    return topEntries.map((e) {
      final product = pMap[e.key];
      final name = product?.name ?? e.key;
      final category = product?.categoryName ?? 'General';
      final price = product?.sellingPrice ?? 0.0;
      final totalPrice = price * e.value;

      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : 'P',
            style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
        subtitle: Text(category, style: TextStyle(fontSize: 11.5, color: AppTheme.textSec(context))),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${e.value} sold',
              style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
            ),
            if (price > 0)
              Text(
                '₹${totalPrice.toStringAsFixed(0)}',
                style: TextStyle(fontSize: 11, color: AppTheme.textSec(context)),
              ),
          ],
        ),
      );
    }).toList();
  }
}
