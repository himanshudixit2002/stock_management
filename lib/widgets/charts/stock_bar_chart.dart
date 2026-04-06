import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../chart_empty_state.dart';
import '../../config/theme.dart';

class StockBarChart extends StatelessWidget {
  final Map<String, double> data;
  final Color barColor;
  final bool isCurrency;
  final String emptyMessage;

  const StockBarChart({
    super.key,
    required this.data,
    this.barColor = AppTheme.primaryColor,
    this.isCurrency = false,
    this.emptyMessage = 'No data available',
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty || data.values.every((v) => v == 0)) {
      return ChartEmptyState(message: emptyMessage);
    }

    final entries = data.entries.toList();
    final maxVal = entries.fold<double>(0, (m, e) => e.value > m ? e.value : m);

    return LayoutBuilder(
      builder: (context, constraints) {
        final h = (constraints.maxWidth * 0.5).clamp(180.0, 300.0);
        return SizedBox(
          height: h,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxVal * 1.2,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final label = entries[group.x.toInt()].key;
                    final val = rod.toY;
                    final valStr = isCurrency
                        ? '${AppTheme.currencySymbol}${val.toStringAsFixed(0)}'
                        : val.toStringAsFixed(0);
                    return BarTooltipItem(
                      '$label\n$valStr',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= entries.length) {
                        return const SizedBox.shrink();
                      }
                      final label = entries[idx].key;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          label.length > 8
                              ? '${label.substring(0, 7)}...'
                              : label,
                          style: TextStyle(
                            fontSize: 9,
                            color: AppTheme.textSec(context),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 45,
                    getTitlesWidget: (value, meta) {
                      if (value == 0) return const SizedBox.shrink();
                      String label;
                      if (isCurrency) {
                        if (value >= 100000) {
                          label = '${(value / 100000).toStringAsFixed(1)}L';
                        } else if (value >= 1000) {
                          label = '${(value / 1000).toStringAsFixed(1)}K';
                        } else {
                          label = value.toStringAsFixed(0);
                        }
                      } else {
                        label = value.toInt().toString();
                      }
                      return Text(
                        label,
                        style: TextStyle(
                          fontSize: 9,
                          color: AppTheme.textSec(context),
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
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (value) =>
                    FlLine(color: AppTheme.dividerC(context), strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              barGroups: List.generate(entries.length, (i) {
                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: entries[i].value,
                      color: barColor,
                      width: entries.length > 8 ? 12 : 20,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        );
      },
    );
  }
}
