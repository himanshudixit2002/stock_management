import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../chart_empty_state.dart';
import '../../config/theme.dart';
import '../../models/stock_transaction_model.dart';

class TransactionLineChart extends StatelessWidget {
  final Map<String, Map<TransactionType, int>> dataByDay;
  final int days;

  /// 'daily', 'weekly', or 'monthly' -- controls bottom axis labels.
  final String granularity;

  const TransactionLineChart({
    super.key,
    required this.dataByDay,
    this.days = 7,
    this.granularity = 'daily',
  });

  String _formatLabel(String key) {
    switch (granularity) {
      case 'weekly':
        // key like "2026-W10" → "W10"
        final wIdx = key.indexOf('W');
        return wIdx >= 0 ? key.substring(wIdx) : key;
      case 'monthly':
        // key like "2026-03" → "Mar"
        final parts = key.split('-');
        if (parts.length == 2) {
          final month = int.tryParse(parts[1]);
          if (month != null && month >= 1 && month <= 12) {
            return DateFormat('MMM').format(DateTime(2000, month));
          }
        }
        return key;
      default:
        final date = DateTime.tryParse(key);
        return date != null ? DateFormat('dd/MM').format(date) : key;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (dataByDay.isEmpty) {
      return const ChartEmptyState(message: 'No transaction data available');
    }

    final allKeys = dataByDay.keys.toList()..sort();
    final keys = allKeys.length > days
        ? allKeys.sublist(allKeys.length - days)
        : allKeys;

    final stockInSpots = <FlSpot>[];
    final stockOutSpots = <FlSpot>[];
    final damageSpots = <FlSpot>[];

    double maxY = 0;

    for (int i = 0; i < keys.length; i++) {
      final day = dataByDay[keys[i]]!;
      final inVal = (day[TransactionType.stockIn] ?? 0).toDouble();
      final outVal = (day[TransactionType.stockOut] ?? 0).toDouble();
      final dmgVal = (day[TransactionType.damage] ?? 0).toDouble();

      stockInSpots.add(FlSpot(i.toDouble(), inVal));
      stockOutSpots.add(FlSpot(i.toDouble(), outVal));
      damageSpots.add(FlSpot(i.toDouble(), dmgVal));

      final localMax = [inVal, outVal, dmgVal].reduce((a, b) => a > b ? a : b);
      if (localMax > maxY) maxY = localMax;
    }

    if (maxY == 0) maxY = 10;

    return LayoutBuilder(
      builder: (context, constraints) {
        final chartH = (constraints.maxWidth * 0.5).clamp(180.0, 300.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: chartH,
              child: LineChart(
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: (maxY / 4).ceilToDouble().clamp(
                      1,
                      9999,
                    ),
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: AppTheme.dividerC(context),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) => Text(
                          value.toInt().toString(),
                          style: TextStyle(
                            fontSize: 10,
                            color: AppTheme.textSec(context),
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= keys.length) {
                            return const SizedBox.shrink();
                          }
                          if (keys.length > 10 && idx % 2 != 0) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _formatLabel(keys[idx]),
                              style: TextStyle(
                                fontSize: 9,
                                color: AppTheme.textSec(context),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minX: 0,
                  maxX: (keys.length - 1).toDouble().clamp(0, 9999),
                  minY: 0,
                  maxY: maxY * 1.15,
                  lineBarsData: [
                    _lineData(stockInSpots, AppTheme.successColor),
                    _lineData(stockOutSpots, AppTheme.primaryColor),
                    _lineData(damageSpots, AppTheme.dangerColor),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          final colors = [
                            AppTheme.successColor,
                            AppTheme.primaryColor,
                            AppTheme.dangerColor,
                          ];
                          final labels = ['In', 'Out', 'Dmg'];
                          return LineTooltipItem(
                            '${labels[spot.barIndex]}: ${spot.y.toInt()}',
                            TextStyle(
                              color: colors[spot.barIndex],
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          );
                        }).toList();
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legend(context, AppTheme.successColor, 'Stock In'),
                const SizedBox(width: 16),
                _legend(context, AppTheme.primaryColor, 'Stock Out'),
                const SizedBox(width: 16),
                _legend(context, AppTheme.dangerColor, 'Damage'),
              ],
            ),
          ],
        );
      },
    );
  }

  LineChartBarData _lineData(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      preventCurveOverShooting: true,
      color: color,
      barWidth: 2.5,
      dotData: FlDotData(
        show: spots.length <= 15,
        getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
          radius: 3,
          color: color,
          strokeWidth: 1.5,
          strokeColor: Colors.white,
        ),
      ),
      belowBarData: BarAreaData(
        show: true,
        color: color.withValues(alpha: 0.08),
      ),
    );
  }

  Widget _legend(BuildContext context, Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 11, color: AppTheme.textSec(context)),
        ),
      ],
    );
  }
}
