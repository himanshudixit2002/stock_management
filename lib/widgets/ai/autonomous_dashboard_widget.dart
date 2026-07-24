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
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Self-operating predictive scans & stock balance active',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
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
                    : const Icon(Icons.refresh, color: AppTheme.textSecondary),
                onPressed: _isLoading ? null : _loadAgentData,
                tooltip: 'Re-run Autonomous AI Audit',
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Scanning 30-day velocity & inventory anomalies...'),
                  ],
                ),
              ),
            )
          else ...[
            // 1. Anomalies Card (If any critical anomalies exist)
            if (_anomalies.isNotEmpty) ...[
              _buildSectionTitle('AI Anomaly & Theft Risk Alerts', Icons.warning_amber_rounded, AppTheme.dangerColor),
              const SizedBox(height: 8),
              ..._anomalies.take(2).map((a) => _buildAnomalyCard(a)),
              const SizedBox(height: 12),
            ],

            // 2. Autopilot Purchase Recommendations
            _buildSectionTitle('Proactive Autopilot Reorders (${_autopilotRecs.length})', Icons.shopping_cart_checkout, AppTheme.primaryColor),
            const SizedBox(height: 8),
            if (_autopilotRecs.isEmpty)
              _buildEmptyTile('All items healthy. No emergency reorders required.')
            else
              ..._autopilotRecs.take(3).map((rec) => _buildAutopilotCard(rec)),

            const SizedBox(height: 12),

            // 3. Location Stock Transfer Balances
            if (_transfers.isNotEmpty) ...[
              _buildSectionTitle('Cross-Location Stock Transfer Balances', Icons.swap_horiz_rounded, AppTheme.accentColor),
              const SizedBox(height: 8),
              ..._transfers.take(2).map((t) => _buildTransferCard(t)),
              const SizedBox(height: 12),
            ],

            // 4. Demand Forecast
            if (_forecasts.isNotEmpty) ...[
              _buildSectionTitle('30-Day Demand & Run-Out Forecast', Icons.trending_up_rounded, AppTheme.indigoColor),
              const SizedBox(height: 8),
              ..._forecasts.take(2).map((f) => _buildForecastCard(f)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
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

  Widget _buildEmptyTile(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Text(
        message,
        style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
      ),
    );
  }

  Widget _buildAnomalyCard(Map<String, dynamic> anomaly) {
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
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  anomaly['description'] ?? '',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
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

  Widget _buildAutopilotCard(Map<String, dynamic> rec) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
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
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  'Stock: ${rec['current_stock']} | Velocity: ${rec['weekly_sales_velocity']} units/wk',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
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

  Widget _buildTransferCard(Map<String, dynamic> t) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
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
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  'Move ${t['suggested_transfer_qty']} units: ${t['from_location']} → ${t['to_location']}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForecastCard(Map<String, dynamic> f) {
    final days = f['days_until_stockout'] ?? 999;
    final isUrgent = days <= 7;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
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
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  '30D Demand: ~${f['projected_30d_demand']} units (${f['daily_sales_rate']} units/day)',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
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
