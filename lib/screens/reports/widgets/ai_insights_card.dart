import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../../../widgets/glass_panel.dart';
import '../../../services/report_analytics_service.dart';

class AiInsightsCard extends StatelessWidget {
  final List<String> insights;
  final List<AnomalyAlert> anomalies;
  final Function(String actionId)? onAnomalyAction;

  const AiInsightsCard({
    super.key,
    required this.insights,
    required this.anomalies,
    this.onAnomalyAction,
  });

  @override
  Widget build(BuildContext context) {
    if (insights.isEmpty && anomalies.isEmpty) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GlassPanel(
        padding: const EdgeInsets.all(16),
        borderRadius: 16,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primaryColor.withValues(alpha: 0.8),
                        Colors.purpleAccent.withValues(alpha: 0.8),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Operational Intelligence',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPri(context),
                        ),
                      ),
                      Text(
                        'Real-time automated analytics & safety checks',
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
            const SizedBox(height: 14),

            if (anomalies.isNotEmpty) ...[
              ...anomalies.map((anomaly) => _buildAnomalyTile(context, anomaly)),
              const SizedBox(height: 10),
            ],

            ...insights.map((insight) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '• ',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          insight,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: isDark ? Colors.grey[200] : Colors.grey[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildAnomalyTile(BuildContext context, AnomalyAlert anomaly) {
    Color bg;
    Color border;
    IconData icon;

    switch (anomaly.severity) {
      case AnomalySeverity.danger:
        bg = Colors.red.withValues(alpha: 0.12);
        border = Colors.redAccent.withValues(alpha: 0.4);
        icon = Icons.warning_amber_rounded;
        break;
      case AnomalySeverity.warning:
        bg = Colors.orange.withValues(alpha: 0.12);
        border = Colors.orangeAccent.withValues(alpha: 0.4);
        icon = Icons.error_outline_rounded;
        break;
      case AnomalySeverity.info:
        bg = Colors.blue.withValues(alpha: 0.12);
        border = Colors.blueAccent.withValues(alpha: 0.4);
        icon = Icons.info_outline_rounded;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: border.withValues(alpha: 1.0)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  anomaly.title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPri(context),
                  ),
                ),
                Text(
                  anomaly.description,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textSec(context),
                  ),
                ),
              ],
            ),
          ),
          if (onAnomalyAction != null)
            InkWell(
              onTap: () => onAnomalyAction!(anomaly.id),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  anomaly.actionLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
