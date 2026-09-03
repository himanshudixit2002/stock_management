// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/product_provider.dart';
import '../../providers/stock_provider.dart';
import '../../providers/vendor_provider.dart';
import '../../services/ai_agent_service.dart';
import '../../services/stock_calculations.dart';
import '../animations.dart';

class AutonomousDashboardWidget extends StatefulWidget {
  const AutonomousDashboardWidget({super.key});

  @override
  State<AutonomousDashboardWidget> createState() => _AutonomousDashboardWidgetState();
}

class _AutonomousDashboardWidgetState extends State<AutonomousDashboardWidget> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _autopilotRecs = [];
  List<Map<String, dynamic>> _anomalies = [];
  List<Map<String, dynamic>> _forecasts = [];
  List<Map<String, dynamic>> _transfers = [];

  /// Why the panel has nothing to show, when the reason is a failure.
  ///
  /// Every fetch used to return an empty list on error, so a backend that was
  /// down or a token that was rejected rendered as a confident "no issues" —
  /// the most misleading possible answer for a panel whose whole job is to
  /// raise problems.
  String? _loadError;

  /// True when the inventory sync failed, so any advice below was computed
  /// from whatever the backend last held rather than current stock.
  bool _syncFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAgentData();
    });
  }

  Future<void> _loadAgentData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    var syncOk = true;

    // Sync actual live user inventory items from ProductProvider & StockProvider
    try {
      final productProvider = Provider.of<ProductProvider>(context, listen: false);
      if (!productProvider.isAnalyticsLoaded) {
        await productProvider.loadAnalytics();
      }

      final stockProvider = Provider.of<StockProvider>(context, listen: false);
      final transactions = stockProvider.allTransactions;
      final now = DateTime.now();
      DateTime? firstAt;
      for (final t in transactions) {
        if (firstAt == null || t.date.isBefore(firstAt)) firstAt = t.date;
      }

      // Lead time per vendor, so the backend's reorder-point maths uses the
      // figure the user actually entered against their supplier.
      final vendors = Provider.of<VendorProvider>(context, listen: false).vendors;
      final leadTimeByVendor = {
        for (final v in vendors)
          if (v.leadTimeDays > 0) v.id: v.leadTimeDays,
      };

      final realProducts = productProvider.analyticsProducts.map((p) {
        // The shared definition. This used to count damage as demand and match
        // transaction types by substring on `toString()`, so its velocity ran
        // higher than every other screen's for the same product.
        final double realVelocity = StockCalculations.dailyBurnRate(
          transactions,
          p.id,
          now: now,
          firstTransactionAt: firstAt,
        );

        return {
          'id': p.id,
          'barcode': p.barcode.isNotEmpty ? p.barcode : p.id,
          'name': p.name,
          'stock': p.quantity,
          'min_threshold': p.lowStockThreshold,
          'category': p.categoryName.isNotEmpty ? p.categoryName : 'General',
          'cost_price': p.costPrice,
          'selling_price': p.sellingPrice,
          'sales_velocity': double.parse(realVelocity.toStringAsFixed(2)),
          // The preferred vendor's own lead time. This was hardcoded to 3 for
          // every product, though BACKEND_ARCHITECTURE.md documents it as
          // joined from the vendor and the backend derives reorder_point and
          // safety_stock from it — so a user who set a 21-day lead time got
          // advice computed as if stock could be replaced in three.
          'lead_time_days': leadTimeByVendor[p.preferredVendorId] ?? 7,
          'location': p.locationQuantities.isNotEmpty ? p.locationQuantities.keys.first : 'Main Store',
        };
      }).toList();

      if (realProducts.isNotEmpty) {
        syncOk = await AiAgentService.syncUserInventory(realProducts);
      }
    } catch (e) {
      // Was a bare `catch (_) {}`, so a failed sync was invisible and the
      // recommendations below were presented as though they were based on
      // current stock when they were not.
      debugPrint('Autonomous dashboard inventory sync failed: $e');
      syncOk = false;
    }

    try {
      final results = await Future.wait([
        AiAgentService.fetchAutopilotRecommendations(),
        AiAgentService.fetchAnomalies(),
        AiAgentService.fetchDemandForecasts(),
        AiAgentService.fetchLocationTransferSuggestions(),
      ]);

      if (mounted) {
        setState(() {
          _autopilotRecs = results[0].items;
          _anomalies = results[1].items;
          _forecasts = results[2].items;
          _transfers = results[3].items;
          // Any failure is reported; an empty panel then means "nothing to
          // report", which is the only time it should.
          _loadError = results.firstWhere(
            (r) => r.isError,
            orElse: () => const AgentResult.ok([]),
          ).error;
          _syncFailed = !syncOk;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Autonomous dashboard load error: $e');
      if (mounted) {
        setState(() {
          _loadError = 'Could not load assistant insights.';
          _syncFailed = !syncOk;
          _isLoading = false;
        });
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return FadeSlideIn(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.primaryColor.withValues(alpha: 0.05),
              AppTheme.violetColor.withValues(alpha: 0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.violetColor.withValues(alpha: 0.2),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row with Autonomous Agent Badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.violetColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: AppTheme.violetColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Autonomous Inventory Engine',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPri(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Self-operating predictive scans & stock balance active',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.textSec(context),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: _isLoading 
                      ? const SizedBox(
                          width: 18, 
                          height: 18, 
                          child: CircularProgressIndicator(strokeWidth: 2)
                        )
                      : Icon(Icons.refresh, color: AppTheme.textSec(context)),
                  onPressed: _isLoading ? null : _loadAgentData,
                  tooltip: 'Re-run Autonomous AI Audit',
                ),
              ],
            ),
            const SizedBox(height: 16),

            // A panel that exists to raise problems must never render a failure
            // as an all-clear. These say which it is.
            if (!_isLoading && _loadError != null) ...[
              _Notice(
                icon: Icons.cloud_off_rounded,
                color: AppTheme.dangerColor,
                message:
                    '$_loadError These insights are unavailable — this is not '
                    'a clean bill of health.',
              ),
              const SizedBox(height: 12),
            ] else if (!_isLoading && _syncFailed) ...[
              _Notice(
                icon: Icons.sync_problem_rounded,
                color: AppTheme.warningColor,
                message:
                    'Current stock could not be sent to the assistant, so the '
                    'suggestions below may be based on older figures.',
              ),
              const SizedBox(height: 12),
            ],

            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _isLoading
                  ? const Center(
                      key: ValueKey('loading'),
                      child: Padding(
                        padding: EdgeInsets.all(20.0),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : Column(
                      key: const ValueKey('content'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionHeader('Stock Anomalies & Shrinkage', Icons.warning_amber_rounded, AppTheme.dangerColor),
                        const SizedBox(height: 8),
                        if (_anomalies.isEmpty)
                          _buildEmptyTile(context, 'No anomalies or shrinkage spikes detected.')
                        else ...[
                          ..._anomalies.take(2).map((a) => _buildAnomalyCard(context, a)),
                          if (_anomalies.length > 2)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '+ ${_anomalies.length - 2} more',
                                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppTheme.textSec(context)),
                              ),
                            ),
                        ],

                        const SizedBox(height: 10),

                        _buildSectionHeader('Proactive Auto-Reorder POs', Icons.shopping_cart_checkout, AppTheme.primaryColor),
                        const SizedBox(height: 8),
                        if (_autopilotRecs.isEmpty)
                          _buildEmptyTile(context, 'All stock levels are optimal. No reorders needed.')
                        else ...[
                          ..._autopilotRecs.take(2).map((r) => _buildAutopilotCard(context, r)),
                          if (_autopilotRecs.length > 2)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '+ ${_autopilotRecs.length - 2} more',
                                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppTheme.textSec(context)),
                              ),
                            ),
                        ],

                        const SizedBox(height: 10),

                        _buildSectionHeader('Cross-Location Balance', Icons.swap_horiz_rounded, AppTheme.accentColor),
                        const SizedBox(height: 8),
                        if (_transfers.isEmpty)
                          _buildEmptyTile(context, 'Warehouse & store front stock is balanced.')
                        else ...[
                          ..._transfers.take(2).map((t) => _buildTransferCard(context, t)),
                          if (_transfers.length > 2)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '+ ${_transfers.length - 2} more',
                                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppTheme.textSec(context)),
                              ),
                            ),
                        ],

                        const SizedBox(height: 10),

                        _buildSectionHeader('30-Day Demand Projections', Icons.trending_up_rounded, AppTheme.indigoColor),
                        const SizedBox(height: 8),
                        if (_forecasts.isEmpty)
                          _buildEmptyTile(context, 'No demand velocity data available.')
                        else ...[
                          ..._forecasts.take(2).map((f) => _buildForecastCard(context, f)),
                          if (_forecasts.length > 2)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '+ ${_forecasts.length - 2} more',
                                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppTheme.textSec(context)),
                              ),
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyTile(BuildContext context, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.dividerC(context)),
      ),
      child: Text(
        message,
        style: TextStyle(fontSize: 13, color: AppTheme.textSec(context)),
      ),
    );
  }

  Widget _buildAnomalyCard(BuildContext context, Map<String, dynamic> anomaly) {
    final isCritical = anomaly['severity'] == 'CRITICAL';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isCritical ? AppTheme.dangerColor.withValues(alpha: 0.08) : AppTheme.warningColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isCritical ? AppTheme.dangerColor.withValues(alpha: 0.3) : AppTheme.warningColor.withValues(alpha: 0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  isCritical ? Icons.error_outline : Icons.warning_amber,
                  color: isCritical ? AppTheme.dangerColor : AppTheme.warningColor,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        anomaly['product_name'] ?? 'Product Anomaly',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPri(context)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        anomaly['description'] ?? '',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSec(context)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isCritical ? AppTheme.dangerColor : AppTheme.warningColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    anomaly['severity'] ?? 'ALERT',
                    style: TextStyle(color: AppTheme.onPrimary(context), fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAutopilotCard(BuildContext context, Map<String, dynamic> rec) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppTheme.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.add_shopping_cart, color: AppTheme.primaryColor, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rec['product_name'] ?? 'Item',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPri(context)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Stock: ${rec['current_stock']} | Velocity: ${rec['weekly_sales_velocity']} units/wk',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSec(context)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  flex: 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '+${rec['suggested_reorder_qty']} units',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'AI Draft PO',
                        style: TextStyle(fontSize: 12, color: AppTheme.textMute(context)),
                      ),
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

  Widget _buildTransferCard(BuildContext context, Map<String, dynamic> t) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppTheme.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.2)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.swap_horiz_rounded, color: AppTheme.accentColor, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t['product_name'] ?? 'Product',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPri(context)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Move ${t['suggested_transfer_qty']} units: ${t['from_location']} → ${t['to_location']}',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSec(context)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
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

  Widget _buildForecastCard(BuildContext context, Map<String, dynamic> f) {
    final days = f['days_until_stockout'] ?? 999;
    final isUrgent = days <= 7;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppTheme.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.indigoColor.withValues(alpha: 0.2)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Icons.access_time_filled_rounded,
                  color: isUrgent ? AppTheme.warningColor : AppTheme.indigoColor,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f['product_name'] ?? 'Item',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPri(context)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '30D Demand: ~${f['projected_30d_demand']} units (${f['daily_sales_rate']} units/day)',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSec(context)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isUrgent ? AppTheme.warningColor.withValues(alpha: 0.15) : AppTheme.indigoColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    days >= 999 ? 'Stable' : '$days Days',
                    style: TextStyle(
                      color: isUrgent ? AppTheme.warningColor : AppTheme.indigoColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A one-line status strip inside the assistant panel.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: AppTheme.textSec(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
