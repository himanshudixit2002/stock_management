import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/ai_agent_service.dart';

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

  @override
  void initState() {
    super.initState();
    _loadAgentData();
  }

  Future<void> _loadAgentData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      AiAgentService.fetchAutopilotRecommendations(),
      AiAgentService.fetchAnomalies(),
      AiAgentService.fetchDemandForecasts(),
      AiAgentService.fetchLocationTransferSuggestions(),
    ]);

    if (mounted) {
      setState(() {
        _autopilotRecs = results[0];
        _anomalies = results[1];
        _forecasts = results[2];
        _transfers = results[3];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryDark.withValues(alpha: 0.05),
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

          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: CircularProgressIndicator(),
              ),
            )
          else ...[
            _buildSectionHeader('Stock Anomalies & Shrinkage', Icons.warning_amber_rounded, AppTheme.dangerColor),
            const SizedBox(height: 8),
            if (_anomalies.isEmpty)
              _buildEmptyTile(context, 'No anomalies or shrinkage spikes detected.')
            else
              ..._anomalies.take(2).map((a) => _buildAnomalyCard(context, a)),

            const SizedBox(height: 14),

            _buildSectionHeader('Proactive Auto-Reorder POs', Icons.shopping_cart_checkout, AppTheme.primaryColor),
            const SizedBox(height: 8),
            if (_autopilotRecs.isEmpty)
              _buildEmptyTile(context, 'All stock levels are optimal. No reorders needed.')
            else
              ..._autopilotRecs.take(2).map((r) => _buildAutopilotCard(context, r)),

            const SizedBox(height: 14),

            _buildSectionHeader('Cross-Location Balance', Icons.swap_horiz_rounded, AppTheme.accentColor),
            const SizedBox(height: 8),
            if (_transfers.isEmpty)
              _buildEmptyTile(context, 'Warehouse & store front stock is balanced.')
            else
              ..._transfers.take(2).map((t) => _buildTransferCard(context, t)),

            const SizedBox(height: 14),

            _buildSectionHeader('30-Day Demand Projections', Icons.trending_up_rounded, AppTheme.indigoColor),
            const SizedBox(height: 8),
            if (_forecasts.isEmpty)
              _buildEmptyTile(context, 'No demand velocity data available.')
            else
              ..._forecasts.take(2).map((f) => _buildForecastCard(context, f)),
          ],
        ],
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCritical ? AppTheme.dangerColor.withValues(alpha: 0.08) : AppTheme.warningColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isCritical ? AppTheme.dangerColor.withValues(alpha: 0.3) : AppTheme.warningColor.withValues(alpha: 0.3)),
      ),
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
                ),
                Text(
                  anomaly['description'] ?? '',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSec(context)),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isCritical ? AppTheme.dangerColor : AppTheme.warningColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              anomaly['severity'] ?? 'ALERT',
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutopilotCard(BuildContext context, Map<String, dynamic> rec) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
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
                ),
                Text(
                  'Stock: ${rec['current_stock']} | Velocity: ${rec['weekly_sales_velocity']} units/wk',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSec(context)),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '+${rec['suggested_reorder_qty']} units',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryDark, fontSize: 13),
              ),
              const Text(
                'AI Draft PO',
                style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTransferCard(BuildContext context, Map<String, dynamic> t) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.2)),
      ),
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
                ),
                Text(
                  'Move ${t['suggested_transfer_qty']} units: ${t['from_location']} → ${t['to_location']}',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSec(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForecastCard(BuildContext context, Map<String, dynamic> f) {
    final days = f['days_until_stockout'] ?? 999;
    final isUrgent = days <= 7;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.indigoColor.withValues(alpha: 0.2)),
      ),
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
                ),
                Text(
                  '30D Demand: ~${f['projected_30d_demand']} units (${f['daily_sales_rate']} units/day)',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSec(context)),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isUrgent ? AppTheme.warningColor.withValues(alpha: 0.15) : AppTheme.indigoColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$days Days Stock',
              style: TextStyle(
                color: isUrgent ? AppTheme.warningColor : AppTheme.indigoColor,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
