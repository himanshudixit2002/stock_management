import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../animations.dart';
import '../chart_empty_state.dart';
import '../../config/theme.dart';
import '../../utils/currency.dart';

class CategoryPieChart extends StatefulWidget {
  final Map<String, double> data;
  final String valueLabel;
  final bool isCurrency;
  final void Function(String category, double value)? onSliceTap;

  const CategoryPieChart({
    super.key,
    required this.data,
    this.valueLabel = '',
    this.isCurrency = false,
    this.onSliceTap,
  });

  @override
  State<CategoryPieChart> createState() => _CategoryPieChartState();
}

class _CategoryPieChartState extends State<CategoryPieChart> {
  int _touchedIndex = -1;

  /// The slice palette used to live here as six theme tokens plus six raw hex
  /// values that belonged to no palette and had no dark variant — so half the
  /// chart ignored the theme. It is now [AppTheme.chartRamp], which has a
  /// light and a dark set.
  List<Color> _colors(BuildContext context) => AppTheme.chartRamp(context);

  @override
  Widget build(BuildContext context) {
    if (widget.data.isEmpty || widget.data.values.every((v) => v == 0)) {
      return const ChartEmptyState();
    }
    final ramp = _colors(context);

    final entries = widget.data.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<double>(0, (sum, e) => sum + e.value);

    return LayoutBuilder(
      builder: (context, constraints) {
        final chartH = (constraints.maxWidth * 0.5).clamp(180.0, 300.0);
        return FadeSlideIn(
          child: Column(
          children: [
            SizedBox(
              height: chartH,
              child: PieChart(
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeOutCubic,
                PieChartData(
                  pieTouchData: PieTouchData(
                    touchCallback: (event, pieTouchResponse) {
                      final newIdx =
                          (!event.isInterestedForInteractions ||
                              pieTouchResponse == null ||
                              pieTouchResponse.touchedSection == null)
                          ? -1
                          : pieTouchResponse
                                .touchedSection!
                                .touchedSectionIndex;

                      setState(() => _touchedIndex = newIdx);

                      if (widget.onSliceTap != null &&
                          event is FlTapUpEvent &&
                          newIdx >= 0 &&
                          newIdx < entries.length) {
                        widget.onSliceTap!(
                          entries[newIdx].key,
                          entries[newIdx].value,
                        );
                      }
                    },
                  ),
                  borderData: FlBorderData(show: false),
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                  sections: List.generate(entries.length, (i) {
                    final isTouched = i == _touchedIndex;
                    final entry = entries[i];
                    final pct = (entry.value / total * 100).toStringAsFixed(1);
                    final sliceColor = ramp[i % ramp.length];
                    final labelColor =
                        ThemeData.estimateBrightnessForColor(sliceColor) ==
                            Brightness.dark
                        ? Colors.white
                        : Colors.black87;
                    return PieChartSectionData(
                      color: sliceColor,
                      value: entry.value,
                      title: isTouched ? '$pct%' : '',
                      radius: isTouched ? 55 : 45,
                      titleStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: labelColor,
                      ),
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: List.generate(entries.length, (i) {
                final entry = entries[i];
                final valStr = widget.isCurrency
                    ? Money.of(context, entry.value, decimals: 0)
                    : entry.value.toStringAsFixed(0);
                return GestureDetector(
                  onTap: widget.onSliceTap != null
                      ? () => widget.onSliceTap!(entry.key, entry.value)
                      : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: ramp[i % ramp.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${entry.key} ($valStr)',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSec(context),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ],
          ),
        );
      },
    );
  }
}
